#!/bin/bash
# run_common.sh — shared helpers (arg parsing, logging, dashboard, parallelism)
# sourced by every scripts/run_sim_<N>_*.sh entry point. Not run directly.
#
# Reproducibility (must match R/sim_dgp_config.R):
#   B=500, n ∈ {500,1000,2000,5000}, p=100 (comparison / GoF / ols_pp)
#   GoF (Section 1): n2=ceil(2*sqrt(n1)), random split, K0=1, seeds 1352..1851
#   Adaptive (Sections 2–4): random split Cauchy, nsplits=3, rho grid 0.5..0.95 step 0.05
#   High-dim: p=floor(0.9n) and p=floor(1.5n); OLS only when p<n (p09 regime)
#   Motivating example (Table 1): simulations/sim_motivating.R, n=100, p=30, B=500 (own seeds)

# Sample sizes and replication count B are overridable for quick smoke tests, e.g.:
#   TWOSTAGEPC_SIM_B=10 TWOSTAGEPC_SIM_NS="500" bash scripts/run_sim_5_comparison.sh --no-dnn --ncores 4 --quiet
if [[ -n "${TWOSTAGEPC_SIM_NS:-}" ]]; then
  read -r -a SIM_NS <<< "${TWOSTAGEPC_SIM_NS}"
else
  SIM_NS=(500 1000 2000 5000)
fi
SIM_B="${TWOSTAGEPC_SIM_B:-500}"
SIM_DGPS=(sparse_linear nonlinear)
SIM_P_COMPARISON=100
SIM_GOF_SEED_START=1352
SIM_GOF_SEED_END=$((SIM_GOF_SEED_START + SIM_B - 1))

# Dashboard/status-tracking order; matches the paper-section order used for the
# numbered run_sim_<N>_*.sh scripts (see README.md).
PIPELINE_SECTIONS=(install motivating gof ols_pp comparison highdim_pn realdata postprocess)

twostagepc_log_repro_config() {
  log "Repro config: B=${SIM_B} n=${SIM_NS[*]} p=${SIM_P_COMPARISON}"
  log "GoF: n2=ceil(2*sqrt(n1)), random split K0=1, seeds ${SIM_GOF_SEED_START}..${SIM_GOF_SEED_END}"
  log "Adaptive: random Cauchy nsplits=3, rho 0.5..0.95 step 0.05 (R/sim_dgp_config.R)"
}

# CPUs allocated to this job (Slurm) or visible on this host.
# Use nproc --all: plain nproc honors OMP_NUM_THREADS and would return 1 after
# twostagepc_limit_threads(), incorrectly capping parallel workers to 1.
twostagepc_available_cpus() {
  if [[ -n "${SLURM_JOB_ID:-}" && -n "${SLURM_CPUS_PER_TASK:-}" ]]; then
    echo "$SLURM_CPUS_PER_TASK"
  elif [[ -n "${SLURM_JOB_ID:-}" && -n "${SLURM_CPUS_ON_NODE:-}" ]]; then
    echo "$SLURM_CPUS_ON_NODE"
  else
    nproc --all 2>/dev/null || nproc 2>/dev/null || echo 1
  fi
}

# One thread per worker: prevent BLAS/TF from spawning extra CPUs inside each R worker.
twostagepc_limit_threads() {
  export OMP_NUM_THREADS=1
  export OPENBLAS_NUM_THREADS=1
  export MKL_NUM_THREADS=1
  export VECLIB_MAXIMUM_THREADS=1
  export NUMEXPR_NUM_THREADS=1
  export OMP_THREAD_LIMIT=1
  export TF_NUM_INTRAOP_THREADS=1
  export TF_NUM_INTEROP_THREADS=1
  export TF_ENABLE_ONEDNN_OPTS=0
}

# Cap R parallel workers to allocated CPUs; always limit nested library threads to 1.
twostagepc_configure_parallelism() {
  twostagepc_limit_threads
  if [[ -z "${RETICULATE_PYTHON:-}" ]]; then
    if [[ -x "${HOME}/.virtualenvs/r-tensorflow/bin/python" ]]; then
      export RETICULATE_PYTHON="${HOME}/.virtualenvs/r-tensorflow/bin/python"
    elif command -v python3 &>/dev/null; then
      export RETICULATE_PYTHON="$(command -v python3)"
    fi
  fi
  local avail
  avail="$(twostagepc_available_cpus)"
  export TWOSTAGEPC_AVAILABLE_CPUS="$avail"

  if [[ -z "${NCORES:-}" || "${NCORES}" == "auto" ]]; then
    NCORES="$avail"
  elif [[ "$NCORES" -gt "$avail" ]]; then
    echo "WARNING: --ncores ${NCORES} exceeds available CPUs (${avail}); capping to ${avail}" >&2
    NCORES="$avail"
  fi
  export TWOSTAGEPC_NCORES="$NCORES"

  if [[ -z "${DNN_NCORES:-}" ]]; then
    DNN_NCORES=8
  elif [[ "$DNN_NCORES" -gt "$avail" ]]; then
    echo "WARNING: --dnn-ncores ${DNN_NCORES} exceeds available CPUs (${avail}); capping to ${avail}" >&2
    DNN_NCORES="$avail"
  fi
  export DNN_NCORES

  # Growing-p SCAD/RF/OLS: high p at n=5000 is memory-heavy; default fewer workers than fixed-p.
  if [[ -z "${HEAVY_NCORES:-}" ]]; then
    HEAVY_NCORES=8
  elif [[ "$HEAVY_NCORES" -gt "$avail" ]]; then
    echo "WARNING: --heavy-ncores ${HEAVY_NCORES} exceeds available CPUs (${avail}); capping to ${avail}" >&2
    HEAVY_NCORES="$avail"
  fi
  export HEAVY_NCORES
}

twostagepc_apply_ncores() {
  NCORES="$1"
  export TWOSTAGEPC_NCORES="$1"
}

twostagepc_parse_args() {
  SKIP_DNN=0
  NCORES=auto
  DNN_NCORES=
  HEAVY_NCORES=
  QUIET=0
  FOREGROUND=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-dnn) SKIP_DNN=1; shift ;;
      --quiet) QUIET=1; shift ;;
      --foreground) FOREGROUND=1; shift ;;
      --ncores)
        if [[ $# -lt 2 ]]; then echo "Usage: --ncores N"; exit 1; fi
        NCORES="$2"
        shift 2
        ;;
      --dnn-ncores)
        if [[ $# -lt 2 ]]; then echo "Usage: --dnn-ncores N"; exit 1; fi
        DNN_NCORES="$2"
        shift 2
        ;;
      --heavy-ncores)
        if [[ $# -lt 2 ]]; then echo "Usage: --heavy-ncores N"; exit 1; fi
        HEAVY_NCORES="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done
  twostagepc_configure_parallelism
}

twostagepc_init_logging() {
  local tag="${1:-run}"
  if [[ -z "${STAMP:-}" ]]; then
    STAMP="$(date +%Y%m%d_%H%M%S)"
  fi
  export STAMP
  local log_root="${TWOSTAGEPC_LOG_DIR:-results/logs}"
  mkdir -p "$log_root"
  MASTER_LOG="${log_root}/pipeline_${STAMP}.log"
  export MASTER_LOG
}

log() {
  if [[ "${QUIET:-0}" -eq 1 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$MASTER_LOG"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MASTER_LOG"
  fi
}

twostagepc_refresh_dashboard() {
  DASHBOARD="${DASHBOARD:-results/DASHBOARD.txt}"
  mkdir -p results/logs
  local tmp section status started finished
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
TwoStagePC pipeline dashboard
Stamp:      ${STAMP:-unknown}
Started:    ${PIPELINE_STARTED:-$(date '+%Y-%m-%d %H:%M:%S')}
NCORES:     ${NCORES:-auto}
AVAIL_CPU:  ${TWOSTAGEPC_AVAILABLE_CPUS:-?}
THREADS:    OMP/BLAS/TF=1 per worker
SKIP_DNN:   ${SKIP_DNN:-0}
Master log: ${MASTER_LOG:-results/logs/pipeline.log}

Monitor:    cat results/DASHBOARD.txt
            tail -f ${MASTER_LOG:-results/logs/pipeline.log}

SECTION           STATUS    STARTED              FINISHED             LOGS
--------------------------------------------------------------------------------
EOF
  for section in "${PIPELINE_SECTIONS[@]}"; do
    local sdir="results/logs/${section}"
    status="$(cat "${sdir}/status.txt" 2>/dev/null || echo PENDING)"
    started="$(cat "${sdir}/started.txt" 2>/dev/null || echo -)"
    finished="$(cat "${sdir}/finished.txt" 2>/dev/null || echo -)"
    printf "%-17s %-9s %-20s %-20s results/logs/%s/\n" \
      "$section" "$status" "$started" "$finished" "$section" >> "$tmp"
  done
  cat >> "$tmp" <<EOF

Data outputs:
  results/gof/                          GoF calibration (Section 3.1)
  results/ols_pp/<dgp>/                 OLS/SCAD adaptive P-P (Section 3.2)
  results/comparison/fixed_p/<dgp>/       Fixed p=100
  results/comparison/growing_p/<dgp>/     Growing p (p09, p15)
  results/realdata/                     Million Song analysis
  results/aggregated/                   all_simulations_summary.csv
  results/figures/                      PDF figures (postprocess)
EOF
  mv "$tmp" "$DASHBOARD"
  cp "$DASHBOARD" results/logs/DASHBOARD.txt
}

twostagepc_section_begin() {
  local section="$1"
  export TWOSTAGEPC_CURRENT_SECTION="$section"
  export TWOSTAGEPC_LOG_DIR="results/logs/${section}"
  mkdir -p "$TWOSTAGEPC_LOG_DIR"
  date '+%Y-%m-%d %H:%M:%S' > "${TWOSTAGEPC_LOG_DIR}/started.txt"
  echo "RUNNING" > "${TWOSTAGEPC_LOG_DIR}/status.txt"
  rm -f "${TWOSTAGEPC_LOG_DIR}/finished.txt"
  twostagepc_refresh_dashboard
  log "=== SECTION BEGIN: ${section} (logs: ${TWOSTAGEPC_LOG_DIR}/) ==="
}

twostagepc_section_done() {
  local section="$1"
  echo "DONE" > "results/logs/${section}/status.txt"
  date '+%Y-%m-%d %H:%M:%S' > "results/logs/${section}/finished.txt"
  twostagepc_refresh_dashboard
  log "=== SECTION DONE: ${section} ==="
}

twostagepc_section_failed() {
  local section="${TWOSTAGEPC_CURRENT_SECTION:-unknown}"
  echo "FAILED" > "results/logs/${section}/status.txt"
  date '+%Y-%m-%d %H:%M:%S' > "results/logs/${section}/finished.txt"
  twostagepc_refresh_dashboard
}

run_one() {
  local name="$1"
  shift
  local logdir="${TWOSTAGEPC_LOG_DIR:-results/logs/misc}"
  mkdir -p "$logdir"
  local logfile="${logdir}/${STAMP}_${name}.log"
  log "START: $*  ->  ${logfile}"
  if Rscript "$@" >> "$logfile" 2>&1; then
    log "OK: $name"
  else
    log "FAILED: $name (see ${logfile})"
    twostagepc_section_failed
    exit 1
  fi
}

twostagepc_log_header() {
  local label="$1"
  log "=== TwoStagePC | ${label} | SKIP_DNN=${SKIP_DNN:-0} | NCORES=${NCORES} | DNN_NCORES=${DNN_NCORES:-8} | HEAVY_NCORES=${HEAVY_NCORES:-8} | AVAIL_CPU=${TWOSTAGEPC_AVAILABLE_CPUS:-?} | nested_threads=1 ==="
  log "Working directory: $(pwd)"
  twostagepc_log_repro_config
}

twostagepc_validate_comparison_dgp() {
  local dgp="$1"
  case "$dgp" in
    sparse_linear|nonlinear) ;;
    *)
      echo "Unknown DGP: ${dgp} (use sparse_linear or nonlinear)"
      exit 1
      ;;
  esac
}

twostagepc_validate_comparison_setting() {
  local setting="$1"
  case "$setting" in
    fixed_p|growing_p09|growing_p15|p09|p15) ;;
    *)
      echo "Unknown setting: ${setting} (use fixed_p, growing_p09, or growing_p15)"
      exit 1
      ;;
  esac
}

twostagepc_normalize_comparison_setting() {
  case "$1" in
    fixed_p) echo "fixed_p" ;;
    growing_p09|p09) echo "growing_p09" ;;
    growing_p15|p15) echo "growing_p15" ;;
    *) echo "$1" ;;
  esac
}

twostagepc_setting_to_regime() {
  case "$(twostagepc_normalize_comparison_setting "$1")" in
    growing_p09) echo "p09" ;;
    growing_p15) echo "p15" ;;
    *) echo "" ;;
  esac
}

twostagepc_run_install() {
  twostagepc_section_begin install
  run_one "install_packages" R/install_packages.R
  twostagepc_section_done install
}

# Table 1 (Introduction motivating example): n=100, p=30, own B/seeds (see simulations/sim_motivating.R).
twostagepc_run_sim_motivating() {
  twostagepc_section_begin motivating
  local motivating_ncores="$TWOSTAGEPC_NCORES"
  if [[ "${SKIP_DNN:-0}" -eq 0 ]]; then
    twostagepc_apply_ncores "${DNN_NCORES:-8}"
  fi
  run_one "sim_motivating" simulations/sim_motivating.R "$SIM_B" "${SKIP_DNN:-0}"
  twostagepc_apply_ncores "$motivating_ncores"
  twostagepc_section_done motivating
}

twostagepc_run_sim_gof() {
  twostagepc_section_begin gof
  run_one "sim_gof" simulations/sim_gof.R "$SIM_B" "${SIM_NS[@]}"
  twostagepc_section_done gof
}

twostagepc_run_sim_ols_pp() {
  twostagepc_section_begin ols_pp
  run_one "sim_ols_pp_ols" simulations/sim_ols_pp.R ols "$SIM_B" "${SIM_NS[@]}"
  twostagepc_section_done ols_pp
}

twostagepc_run_sim_ols_pp_scad() {
  twostagepc_section_begin ols_pp
  run_one "sim_ols_pp_scad" simulations/sim_ols_pp.R scad "$SIM_B" "${SIM_NS[@]}"
  twostagepc_section_done ols_pp
}

twostagepc_run_growing_classic_for_dgp() {
  local dgp="$1" regime="$2"
  local est method
  local classic_ncores="$TWOSTAGEPC_NCORES"
  twostagepc_apply_ncores "${HEAVY_NCORES:-8}"
  log "Growing ${regime} | ${dgp} | classic | NCORES=${TWOSTAGEPC_NCORES} (fixed-p uses ${classic_ncores})"
  for est in scad rf; do
    for method in adaptive fixed; do
      run_one "${dgp}_${regime}_${est}_${method}" \
        simulations/sim_highdim_pn.R "$dgp" "$regime" "$est" "$method" "$SIM_B" "${SIM_NS[@]}"
    done
  done
  if [[ "$regime" == "p09" ]]; then
    for method in adaptive fixed; do
      run_one "${dgp}_${regime}_ols_${method}" \
        simulations/sim_highdim_pn.R "$dgp" "$regime" ols "$method" "$SIM_B" "${SIM_NS[@]}"
    done
  fi
  twostagepc_apply_ncores "$classic_ncores"
}

twostagepc_run_growing_dnn_for_dgp() {
  local dgp="$1" regime="$2"
  local classic_ncores="$TWOSTAGEPC_NCORES"
  twostagepc_apply_ncores "${DNN_NCORES:-8}"
  log "DNN/ensemble | growing ${regime} | ${dgp} | NCORES=${TWOSTAGEPC_NCORES} (classic=${classic_ncores})"
  local method
  for method in adaptive fixed; do
    run_one "${dgp}_${regime}_dnn_${method}" \
      simulations/sim_highdim_pn.R "$dgp" "$regime" dnn "$method" "$SIM_B" "${SIM_NS[@]}"
  done
  run_one "${dgp}_${regime}_ensemble_fixed" \
    simulations/sim_highdim_pn.R "$dgp" "$regime" ensemble fixed "$SIM_B" "${SIM_NS[@]}"
  twostagepc_apply_ncores "$classic_ncores"
}

twostagepc_run_highdim_regime_jobs() {
  local dgp="$1" regime="$2"
  shift 2
  twostagepc_run_growing_classic_for_dgp "$dgp" "$regime"
  if [[ "${SKIP_DNN:-0}" -eq 0 ]]; then
    twostagepc_run_growing_dnn_for_dgp "$dgp" "$regime"
  else
    log "Skipping DNN + ensemble for ${dgp}/${regime} (--no-dnn)"
  fi
}

twostagepc_run_highdim_one_regime() {
  local regime="$1"
  local -a dgps
  if [[ -n "${HIGHDIM_DGPS:-}" ]]; then
    read -r -a dgps <<< "${HIGHDIM_DGPS}"
  else
    dgps=("${SIM_DGPS[@]}")
  fi
  log "Growing-${regime} DGPs: ${dgps[*]}"
  local dgp
  for dgp in "${dgps[@]}"; do
    twostagepc_run_highdim_regime_jobs "$dgp" "$regime" "${SIM_NS[@]}"
  done
}

twostagepc_run_sim_highdim_pn() {
  twostagepc_section_begin highdim_pn
  local regime
  for regime in p09 p15; do
    twostagepc_run_highdim_one_regime "$regime"
  done
  twostagepc_section_done highdim_pn
}

twostagepc_run_comparison_job() {
  local dgp="$1" est="$2" method="$3"
  run_one "${dgp}_${est}_${method}" \
    simulations/sim_comparison.R "$dgp" "$est" "$method" "$SIM_B" "${SIM_NS[@]}"
}

# Fixed p=100: adaptive OLS/SCAD from Section 3.2 (ols_pp); RF/DNN adaptive run here.
twostagepc_run_comparison_classic_for_dgp() {
  local dgp="$1" est
  log "Fixed p | ${dgp} | fixed-ratio OLS/SCAD/RF"
  for est in ols scad rf; do
    twostagepc_run_comparison_job "$dgp" "$est" fixed
  done
  log "Fixed p | ${dgp} | adaptive RF (OLS/SCAD adaptive: reuse ols_pp)"
  twostagepc_run_comparison_job "$dgp" rf adaptive
}

twostagepc_run_comparison_dnn_for_dgp() {
  local dgp="$1"
  local classic_ncores="$TWOSTAGEPC_NCORES"
  twostagepc_apply_ncores "${DNN_NCORES:-8}"
  log "Fixed p | ${dgp} | DNN fixed + adaptive + ensemble fixed (NCORES=${TWOSTAGEPC_NCORES})"
  twostagepc_run_comparison_job "$dgp" dnn fixed
  twostagepc_run_comparison_job "$dgp" dnn adaptive
  twostagepc_run_comparison_job "$dgp" ensemble fixed
  twostagepc_apply_ncores "$classic_ncores"
}

# One comparison cell: setting × DGP × learner group.
#   setting:  fixed_p | growing_p09 | growing_p15
#   dgp:      sparse_linear | nonlinear
#   learners: classic (fixed + rf adaptive) | dnn (fixed + adaptive + ensemble) | all
#   fixed_p adaptive OLS/SCAD: Section 3.2 ols_pp (not re-run here)
twostagepc_run_comparison_cell() {
  local setting="$1" dgp="$2" learners="${3:-classic}"
  setting="$(twostagepc_normalize_comparison_setting "$setting")"
  twostagepc_validate_comparison_setting "$setting"
  twostagepc_validate_comparison_dgp "$dgp"

  case "$learners" in
    classic|dnn|all) ;;
    *)
      echo "Unknown learners group: ${learners} (use classic, dnn, or all)"
      exit 1
      ;;
  esac

  twostagepc_section_begin comparison
  log "Comparison cell: setting=${setting} dgp=${dgp} learners=${learners}"

  if [[ "$setting" == "fixed_p" ]]; then
    if [[ "$learners" == "classic" || "$learners" == "all" ]]; then
      twostagepc_run_comparison_classic_for_dgp "$dgp"
    fi
    if [[ "$learners" == "dnn" || "$learners" == "all" ]]; then
      if [[ "${SKIP_DNN:-0}" -eq 0 ]]; then
        twostagepc_run_comparison_dnn_for_dgp "$dgp"
      else
        log "Skipping DNN + ensemble (--no-dnn)"
      fi
    fi
  else
    local regime
    regime="$(twostagepc_setting_to_regime "$setting")"
    if [[ "$learners" == "classic" || "$learners" == "all" ]]; then
      twostagepc_run_growing_classic_for_dgp "$dgp" "$regime"
    fi
    if [[ "$learners" == "dnn" || "$learners" == "all" ]]; then
      if [[ "${SKIP_DNN:-0}" -eq 0 ]]; then
        twostagepc_run_growing_dnn_for_dgp "$dgp" "$regime"
      else
        log "Skipping DNN + ensemble (--no-dnn)"
      fi
    fi
  fi

  twostagepc_section_done comparison
}

twostagepc_run_sim_comparison() {
  twostagepc_section_begin comparison
  local dgp
  local -a dgps
  if [[ -n "${COMPARISON_DGPS:-}" ]]; then
    read -r -a dgps <<< "${COMPARISON_DGPS}"
  else
    dgps=("${SIM_DGPS[@]}")
  fi
  log "Comparison DGPs: ${dgps[*]}"
  for dgp in "${dgps[@]}"; do
    twostagepc_run_comparison_classic_for_dgp "$dgp"
  done
  if [[ "${SKIP_DNN:-0}" -eq 0 ]]; then
    for dgp in "${dgps[@]}"; do
      twostagepc_run_comparison_dnn_for_dgp "$dgp"
    done
  else
    log "Skipping DNN + ensemble for comparison (--no-dnn)"
  fi
  twostagepc_section_done comparison
}

twostagepc_run_realdata() {
  twostagepc_section_begin realdata
  export SKIP_DNN="${SKIP_DNN:-0}"
  export TWOSTAGEPC_SKIP_DNN="${SKIP_DNN}"
  run_one "real_data" MillionSongSubset/realData_revised.R
  twostagepc_section_done realdata
}

twostagepc_run_postprocess() {
  twostagepc_section_begin postprocess
  run_one "summarize_all" R/summarize_all.R
  if [[ -f R/generate_paper_tables.R ]]; then
    run_one "paper_tables" R/generate_paper_tables.R
    log "Paper tables written to results/tables/*.tex (mirrors paper/tables/*.tex in the manuscript repo)"
  else
    log "Skipping R/generate_paper_tables.R (not found)"
  fi
  run_one "plot_figures" R/plot_sim_figures.R
  if Rscript -e 'if (requireNamespace("rmarkdown", quietly=TRUE)) quit(status=0) else quit(status=1)' 2>/dev/null; then
    run_one "render_report" R/render_figures.R
  else
    log "Skipping R/render_figures.R report bundle (rmarkdown not installed; R/plot_sim_figures.R already ran)"
  fi
  local verify_log="${TWOSTAGEPC_LOG_DIR}/${STAMP}_verify_outputs.log"
  if bash scripts/verify_outputs.sh >> "$verify_log" 2>&1; then
    log "verify_outputs.sh: all expected artifacts present (see ${verify_log})"
  else
    log "verify_outputs.sh: MISSING files (see ${verify_log})"
    twostagepc_section_failed
    exit 1
  fi
  twostagepc_section_done postprocess
}
