#!/usr/bin/env Rscript
# generate_paper_tables.R -- Build LaTeX table fragments from simulation CSVs
#
# Reads summary CSVs produced by revised simulations and writes
# results/tables/table_sim_*.tex, mirroring paper/tables/table_sim_*.tex in the
# manuscript repository (for inclusion in main.tex / supplement.tex). Diff or
# copy these fragments back into the manuscript's paper/tables/ as needed.

source("R/sim_dgp_config.R")
source("R/export_metrics.R")
source("MillionSongSubset/real_data_report.R")

read_summary <- function(rel_pattern) {
  files <- Sys.glob(file.path(RESULTS_ROOT, rel_pattern))
  if (length(files) == 0) return(NULL)
  do.call(rbind, lapply(files, read.csv, stringsAsFactors = FALSE))
}

pick <- function(df, model, estimator, method, n) {
  row <- df[df$model == model & df$estimator == estimator &
              df$method == method & df$n == n, , drop = FALSE]
  if (nrow(row) == 0) return(NULL)
  row[1, ]
}

#' Adaptive rows at fixed p: prefer comparison/fixed_p; fall back to Section 3.2 ols_pp (OLS/SCAD).
pick_adaptive <- function(df, model, estimator, n) {
  row <- pick(df, model, estimator, "adaptive", n)
  if (!is.null(row)) return(row)
  if (!estimator %in% c("ols", "scad")) return(NULL)
  pp <- read_summary(sprintf("ols_pp/%s/sim_%s_pp_B*_summary.csv", model, estimator))
  if (is.null(pp)) return(NULL)
  row <- pp[pp$model == model & pp$estimator == estimator &
              pp$method == "adaptive" & pp$n == n, , drop = FALSE]
  if (nrow(row) == 0) return(NULL)
  row[1, ]
}

fmt_pct <- function(x) {
  if (is.na(x)) return("$\\cdot$")
  sprintf("%.0f\\%%", 100 * x)
}

fmt_num <- function(x, digits = 3) {
  if (is.na(x)) return("$\\cdot$")
  formatC(round(x, digits), format = "f", digits = digits)
}

fmt_cov <- function(x) {
  if (is.na(x)) return("$\\cdot$")
  sprintf("%.1f\\%%", 100 * x)
}

fmt_prop <- function(rate) {
  if (is.na(rate)) return("$\\cdot$")
  if (abs(rate - 1) < 1e-9) return("100\\%")
  sprintf("%.1f\\%%", 100 * rate)
}

fmt_rate <- function(x) {
  if (is.na(x)) return("$\\cdot$")
  formatC(round(x, 3), format = "f", digits = 3)
}

#' Stateful formatters for the P-P table upper block: three decimals; footnotes when
#' a nonzero value rounds to $0.000$ (same idea as \code{sim_motivating.R}).
make_pp_metric_fmt <- function() {
  env <- new.env(parent = emptyenv())
  env$counter <- 0L
  env$notes <- character()

  env$note_zero <- function(x) {
    env$counter <- env$counter + 1L
    letter <- letters[env$counter]
    exact <- if (abs(x) < 0.001) sprintf("%.4f", x) else sprintf("%.3f", x)
    env$notes <- c(
      env$notes,
      sprintf("\\item[%s] The true value is $%s$.", letter, exact)
    )
    sprintf("0.000\\tnote{%s}", letter)
  }

  env$num3 <- function(x) {
    if (is.na(x)) return("$\\cdot$")
    if (abs(x) > 0 && abs(x) < 0.0005) return(env$note_zero(x))
    sprintf("%.3f", x)
  }

  env
}

wrap_pp_threeparttable <- function(tabular_tex, notes) {
  lines <- c("\\begin{threeparttable}", tabular_tex)
  if (length(notes) > 0) {
    lines <- c(
      lines,
      "\\begin{tablenotes}\\footnotesize",
      notes,
      "\\end{tablenotes}"
    )
  }
  c(lines, "\\end{threeparttable}")
}

gof_rate <- function(gof_sum, design, n) {
  row <- gof_sum[gof_sum$design == design & gof_sum$n == n, , drop = FALSE]
  if (nrow(row) == 0) return(NA_real_)
  row$rejection_rate[1]
}

build_gof_table <- function(gof_sum) {
  ns <- sort(unique(gof_sum$n))
  rate_row <- function(learner, kind) {
    design <- if (kind == "type1") {
      sprintf("sparse_linear_%s_type1", learner)
    } else {
      sprintf("nonlinear_%s_power", learner)
    }
  }
  learner_line <- function(learner) {
    vals <- vapply(ns, function(nv) fmt_rate(gof_rate(gof_sum, rate_row(learner, "type1"), nv)),
                   character(1))
    sprintf("%s  & %s \\\\", toupper(learner), paste(vals, collapse = " & "))
  }
  power_line <- function(learner) {
    vals <- vapply(ns, function(nv) fmt_rate(gof_rate(gof_sum, rate_row(learner, "power"), nv)),
                   character(1))
    sprintf("%s  & %s \\\\", toupper(learner), paste(vals, collapse = " & "))
  }
  lines <- c(
    "\\begin{table}[!htb]",
    "\\centering",
    paste0("\\caption{Empirical rejection rate of the goodness-of-fit test at $\\alpha=0.05$, ",
           "based on $B=500$ replications with $p=100$, evaluation-set size ",
           "$n_2=\\lceil 2\\sqrt{n_1}\\rceil$, and one random train--test split.",
           " Under the linear DGP, both learners are correctly specified and the entries estimate ",
           "the Type~I error. Under the nonlinear DGP, both learners are misspecified and the ",
           "entries estimate power.}"),
    "\\label{tab:sim_gof}",
    "\\small",
    "\\begin{tabular}{l r r r r}",
    "\\toprule",
    "& \\multicolumn{4}{c}{$n$} \\\\",
    "\\cmidrule(lr){2-5}",
    paste0("Learner / DGP & ", paste(ns, collapse = " & "), " \\\\"),
    "\\midrule",
    "\\multicolumn{5}{l}{\\textit{Type~I error, Model~\\ref{mod:linear_sparse}, $H_0$}} \\\\",
    learner_line("ols"),
    learner_line("scad"),
    "\\addlinespace",
    "\\multicolumn{5}{l}{\\textit{Power, Model~\\ref{mod:nonlinear}, $H_1$}} \\\\",
    power_line("ols"),
    power_line("scad"),
    "\\bottomrule",
    "\\end{tabular}",
    "\\end{table}"
  )
  paste(lines, collapse = "\n")
}

#' Standard learner rows for estimator-comparison tables (highdim layout).
sim_comparison_combos <- function() {
  list(
    c("scad", "fixed", "SCAD (fixed)"),
    c("scad", "adaptive", "SCAD (Ours)"),
    c("rf", "fixed", "RF (fixed)"),
    c("rf", "adaptive", "RF (Ours)"),
    c("dnn", "fixed", "DNN (fixed)"),
    c("dnn", "adaptive", "DNN (Ours)"),
    c("ensemble", "fixed", "Ensemble (fixed)")
  )
}

format_fixed_vals <- function(row) {
  sprintf("%s & %s & %s & %s & $\\cdot$ & $\\cdot$",
          fmt_num(row$bias), fmt_num(row$mse, 3),
          fmt_num(row$ci_coverage, 3), fmt_num(row$ci_length, 3))
}

format_adaptive_vals <- function(row) {
  if (is.na(row$bias)) {
    sprintf("$\\cdot$ & $\\cdot$ & $\\cdot$ & $\\cdot$ & %s & $\\cdot$",
            fmt_pct(row$gof_pass_rate))
  } else {
    sprintf("%s & %s & %s & %s & %s & %s",
            fmt_num(row$bias), fmt_num(row$mse, 3),
            fmt_num(row$ci_coverage, 3), fmt_num(row$ci_length, 3),
            fmt_pct(row$gof_pass_rate), fmt_num(row$avg_n1_over_n, 3))
  }
}

sim_comparison_caption <- function(model_ref, p_clause) {
  paste0(
    "Simulation results under ", model_ref,
    if (nzchar(p_clause)) paste0(" (", p_clause, ")") else "",
    ", based on $B=500$ replications. ",
    "Bias and MSE refer to the partial correlation estimator; ",
    "CI cov.\\ is empirical 95\\% interval coverage; ",
    "CI len.\\ is average interval length; ",
    "Prop.\\ is the GoF pass rate; ",
    "$n_1/n$ is the average selected training fraction (adaptive only). ",
    "``Ours'' denotes the adaptive procedure; ",
    "Ensemble is included under fixed-ratio DML only."
  )
}

#' Unified estimator-comparison table: $n$ × Method rows (SCAD, RF, DNN, Ensemble).
build_comparison_table <- function(df, dgp, label, caption) {
  if (is.null(df)) return(NULL)
  combos <- sim_comparison_combos()
  ns <- sort(unique(df$n[df$model == dgp]))
  if (length(ns) == 0) return(NULL)

  lines <- c(
    "\\begin{table}[!htb]", "\\centering",
    sprintf("\\caption{%s}", caption),
    sprintf("\\label{%s}", label),
    "\\small",
    "\\begin{tabular}{l l c c c c c c}",
    "\\toprule",
    "$n$ & Method & Bias & MSE & CI cov. & CI len. & Prop. & $n_1/n$ \\\\",
    "\\midrule"
  )
  for (n_val in ns) {
    present <- Filter(function(cc) {
      if (cc[1] == "ensemble" && cc[2] == "adaptive") return(FALSE)
      !is.null(pick(df, dgp, cc[1], cc[2], n_val))
    }, combos)
    if (length(present) == 0) next
    k <- length(present)
    first <- TRUE
    for (cc in present) {
      row <- pick(df, dgp, cc[1], cc[2], n_val)
      ncell <- if (first) sprintf("\\multirow{%d}{*}{%d}", k, n_val) else ""
      vals <- if (cc[2] == "adaptive") format_adaptive_vals(row) else format_fixed_vals(row)
      lines <- c(lines, sprintf("%s & %s & %s \\\\", ncell, cc[3], vals))
      first <- FALSE
    }
    lines <- c(lines, "\\addlinespace")
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}", "\\end{table}")
  paste(lines, collapse = "\n")
}

build_highdim_table <- function(dgp, ptag, label, caption) {
  df <- read_summary(sprintf("comparison/growing_p/%s/sim_%s_*_B*_summary.csv", dgp, ptag))
  build_comparison_table(df, dgp, label, caption)
}

augment_fixed_p_df <- function(df, dgp) {
  pp_scad <- read_summary(sprintf("ols_pp/%s/sim_scad_pp_B*_summary.csv", dgp))
  if (!is.null(pp_scad)) {
    pp_scad <- pp_scad[pp_scad$model == dgp & pp_scad$estimator == "scad" &
                         pp_scad$method == "adaptive", , drop = FALSE]
    if (nrow(pp_scad) > 0) df <- rbind(df, pp_scad)
  }
  df
}

build_fixed_p_table <- function(df, dgp, label, caption) {
  build_comparison_table(augment_fixed_p_df(df, dgp), dgp, label, caption)
}

#' Section 3.2 (adaptive P--P) table: tabular body with estimator metrics and split-ratio
#' distribution (columns = sample sizes). Reads the OLS adaptive run under \code{ols_pp/<dgp>/}.
#' Output filenames (table_sim_pp*.tex) and \\label{tab:sim_pp*} -- update the manuscript's
#' \\input{tables/table_sim_pp*.tex} / \\ref{tab:sim_pp*} in main.tex / supplement.tex to match.
pp_table_data <- function(dgp, grid = seq(0.5, 0.95, 0.05)) {
  sum_files <- Sys.glob(file.path(RESULTS_ROOT,
                  sprintf("ols_pp/%s/sim_ols_pp_B*_summary.csv", dgp)))
  sr_files <- Sys.glob(file.path(RESULTS_ROOT,
                  sprintf("ols_pp/%s/sim_ols_pp_B*_split_ratio.csv", dgp)))
  if (length(sum_files) == 0 || length(sr_files) == 0) return(NULL)
  B <- as.integer(sub(".*_B(\\d+)_.*", "\\1", basename(sum_files[1])))
  smry <- read.csv(sum_files[1], stringsAsFactors = FALSE)
  smry <- smry[smry$estimator == "ols" & smry$method == "adaptive", , drop = FALSE]
  sr <- read.csv(sr_files[1], stringsAsFactors = FALSE)
  sr$bin <- round(as.numeric(sr$n1_over_n) / 0.05) * 0.05
  list(smry = smry, sr = sr, ns = sort(unique(smry$n)), B = B, grid = grid)
}

build_pp_tabular <- function(dgp, grid = seq(0.5, 0.95, 0.05),
                             block = c("perf", "split")) {
  block <- match.arg(block)
  data <- pp_table_data(dgp, grid)
  if (is.null(data)) return(NULL)
  smry <- data$smry
  sr <- data$sr
  ns <- data$ns
  B <- data$B
  ncols <- length(ns)
  fmt <- make_pp_metric_fmt()

  metric_row <- function(name, col, fmt_fun) {
    vals <- vapply(ns, function(nv) {
      r <- smry[smry$n == nv, , drop = FALSE]
      if (nrow(r) == 0) "$\\cdot$" else fmt_fun(r[[col]][1])
    }, character(1))
    sprintf("%s & %s \\\\", name, paste(vals, collapse = " & "))
  }

  header <- c(
    "{\\setlength{\\tabcolsep}{3.5pt}",
    sprintf("\\begin{tabular}{@{}l@{\\hspace{5pt}}%s@{}}",
            paste(rep("r", ncols), collapse = "@{\\hspace{5pt}}")),
    "\\toprule",
    sprintf("& \\multicolumn{%d}{c}{$n$} \\\\", ncols),
    sprintf("\\cmidrule(lr){2-%d}", ncols + 1),
    paste0("", paste(sprintf("& %d", ns), collapse = " "), " \\\\"),
    "\\midrule"
  )

  if (block == "perf") {
    body <- c(
      sprintf("\\multicolumn{%d}{@{}l@{}}{\\textit{Passing replications}} \\\\", ncols + 1),
      metric_row("Prop.", "gof_pass_rate", fmt_prop),
      metric_row("Bias", "bias", fmt$num3),
      metric_row("MSE", "mse", fmt$num3),
      metric_row("CI cov.", "ci_coverage", fmt_cov),
      metric_row("CI len.", "ci_length", fmt$num3)
    )
    tabular <- c(header, body, "\\bottomrule", "\\end{tabular}}")
    return(paste(wrap_pp_threeparttable(tabular, fmt$notes), collapse = "\n"))
  }

  # block == "split": distribution of the selected training fraction n1/n
  body <- sprintf("\\multicolumn{%d}{@{}l@{}}{\\textit{Selected $n_1/n$ (\\%%)}} \\\\", ncols + 1)
  for (g in grid) {
    vals <- vapply(ns, function(nv) {
      cnt <- sum(sr$count[abs(sr$bin - g) < 1e-9 & sr$n == nv])
      sprintf("%.1f", 100 * cnt / B)
    }, character(1))
    body <- c(body, sprintf("%.2f & %s \\\\", g, paste(vals, collapse = " & ")))
  }
  rej <- vapply(ns, function(nv) {
    tot <- sum(sr$count[sr$n == nv])
    sprintf("%.1f", 100 * (B - tot) / B)
  }, character(1))
  body <- c(body, "\\addlinespace",
            sprintf("Rejected & %s \\\\", paste(rej, collapse = " & ")))
  tabular <- c(header, body, "\\bottomrule", "\\end{tabular}}")
  paste(tabular, collapse = "\n")
}

build_pp_combined_table <- function() {
  tab_h0 <- build_pp_tabular("sparse_linear", block = "perf")
  tab_h1 <- build_pp_tabular("nonlinear", block = "perf")
  if (is.null(tab_h0) || is.null(tab_h1)) return(NULL)
  main_caption <- paste0(
    "Adaptive estimation under the adaptive linear nuisance model ($p=100$, $B=500$). ",
    "Each panel reports finite-sample performance over replications that pass the GoF test ",
    "at $\\alpha=0.05$: Prop.\\ is the pass rate, and Bias, MSE, CI cov.\\ (empirical 95\\% ",
    "coverage), and CI len.\\ are computed over passing replications only."
  )
  sub_h0 <- "Linear DGP ($H_0$; Model~\\ref{mod:linear_sparse})"
  sub_h1 <- "Nonlinear DGP ($H_1$; Model~\\ref{mod:nonlinear})"
  paste(c(
    "\\begin{table}[!htb]",
    "\\centering",
    sprintf("\\caption{%s}", main_caption),
    "\\label{tab:sim_pp}",
    "\\small",
    "\\begin{subtable}[t]{0.48\\linewidth}",
    "\\centering",
    sprintf("\\caption{%s}", sub_h0),
    "\\label{tab:sim_pp_linear}",
    tab_h0,
    "\\end{subtable}",
    "\\hfill",
    "\\begin{subtable}[t]{0.48\\linewidth}",
    "\\centering",
    sprintf("\\caption{%s}", sub_h1),
    "\\label{tab:sim_pp_nonlinear}",
    tab_h1,
    "\\end{subtable}",
    "\\end{table}"
  ), collapse = "\n")
}

build_pp_split_table <- function() {
  tab_h0 <- build_pp_tabular("sparse_linear", block = "split")
  tab_h1 <- build_pp_tabular("nonlinear", block = "split")
  if (is.null(tab_h0) || is.null(tab_h1)) return(NULL)
  main_caption <- paste0(
    "Distribution of the selected training fraction $n_1/n$ on the grid ",
    "$\\{0.50,\\ldots,0.95\\}$, as a percentage of all $B=500$ replications, under the adaptive ",
    "linear nuisance model ($p=100$); \\emph{Rejected} is the percentage of replications failing ",
    "the GoF test at every split ratio. This is the split-ratio block accompanying the ",
    "finite-sample performance in Table~\\ref{tab:sim_pp} of the main text."
  )
  sub_h0 <- "Linear DGP ($H_0$; Model~\\ref{mod:linear_sparse})"
  sub_h1 <- "Nonlinear DGP ($H_1$; Model~\\ref{mod:nonlinear})"
  paste(c(
    "\\begin{table}[!htb]",
    "\\centering",
    sprintf("\\caption{%s}", main_caption),
    "\\label{tab:sim_pp_split}",
    "\\small",
    "\\begin{subtable}[t]{0.48\\linewidth}",
    "\\centering",
    sprintf("\\caption{%s}", sub_h0),
    "\\label{tab:sim_pp_split_linear}",
    tab_h0,
    "\\end{subtable}",
    "\\hfill",
    "\\begin{subtable}[t]{0.48\\linewidth}",
    "\\centering",
    sprintf("\\caption{%s}", sub_h1),
    "\\label{tab:sim_pp_split_nonlinear}",
    tab_h1,
    "\\end{subtable}",
    "\\end{table}"
  ), collapse = "\n")
}

df_sparse <- read_summary("comparison/fixed_p/sparse_linear/sim_sparse_linear_*_B*_summary.csv")
df_nonlin <- read_summary("comparison/fixed_p/nonlinear/sim_nonlinear_*_B*_summary.csv")

TABLES_DIR <- "results/tables"
dir.create(TABLES_DIR, showWarnings = FALSE, recursive = TRUE)

gof_sum <- load_gof_calibration_summary()
if (is.null(gof_sum)) {
  warning("Missing ", gof_calibration_csv_path(), "; skipping table_sim_gof.tex")
} else {
  writeLines(build_gof_table(gof_sum), file.path(TABLES_DIR, "table_sim_gof.tex"))
  cat("Wrote ", TABLES_DIR, "/table_sim_gof.tex\n", sep = "")
}

if (is.null(df_sparse) || is.null(df_nonlin)) {
  warning("Missing summaries under results/comparison/fixed_p/<dgp>/; skipping table_sim_B/C.tex")
} else {
  cap_B <- sim_comparison_caption(
    "the sparse linear DGP, Model~\\ref{mod:linear_sparse}",
    "$p=100$"
  )
  cap_C <- sim_comparison_caption(
    "the sparse nonlinear DGP, Model~\\ref{mod:nonlinear}",
    "$p=100$"
  )
  writeLines(build_fixed_p_table(df_sparse, "sparse_linear", "tab:sim_B", cap_B),
             file.path(TABLES_DIR, "table_sim_B.tex"))
  writeLines(build_fixed_p_table(df_nonlin, "nonlinear", "tab:sim_C", cap_C),
             file.path(TABLES_DIR, "table_sim_C.tex"))
  cat("Wrote ", TABLES_DIR, "/table_sim_B.tex and table_sim_C.tex\n", sep = "")
}

hd_specs <- list(
  list(dgp = "sparse_linear", ptag = "p09", label = "tab:sim_highdim_linear_p09",
       model = "the sparse linear DGP, Model~\\ref{mod:linear_sparse}",
       p_clause = "$p=\\lfloor 0.9 n\\rfloor$ ($p\\approx n$); OLS omitted"),
  list(dgp = "sparse_linear", ptag = "p15", label = "tab:sim_highdim_linear_p15",
       model = "the sparse linear DGP, Model~\\ref{mod:linear_sparse}",
       p_clause = "$p=\\lfloor 1.5 n\\rfloor$ ($p>n$); OLS omitted"),
  list(dgp = "nonlinear", ptag = "p09", label = "tab:sim_highdim_nonlinear_p09",
       model = "the sparse nonlinear DGP, Model~\\ref{mod:nonlinear}",
       p_clause = "$p=\\lfloor 0.9 n\\rfloor$ ($p\\approx n$); OLS omitted"),
  list(dgp = "nonlinear", ptag = "p15", label = "tab:sim_highdim_nonlinear_p15",
       model = "the sparse nonlinear DGP, Model~\\ref{mod:nonlinear}",
       p_clause = "$p=\\lfloor 1.5 n\\rfloor$ ($p>n$); OLS omitted")
)
for (spec in hd_specs) {
  out <- build_highdim_table(
    spec$dgp, spec$ptag, spec$label,
    sim_comparison_caption(spec$model, spec$p_clause)
  )
  fname <- file.path(TABLES_DIR, sprintf("table_sim_highdim_%s_%s.tex",
                   ifelse(spec$dgp == "sparse_linear", "linear", "nonlinear"),
                   spec$ptag))
  if (is.null(out)) {
    warning("Missing growing-p summaries for ", spec$dgp, " ", spec$ptag)
  } else {
    writeLines(out, fname)
    cat("Wrote ", fname, "\n", sep = "")
  }
}

pp_combined <- build_pp_combined_table()
if (is.null(pp_combined)) {
  warning("Missing ols_pp summaries; skipping table_sim_pp.tex")
} else {
  writeLines(pp_combined, file.path(TABLES_DIR, "table_sim_pp.tex"))
  cat("Wrote ", TABLES_DIR, "/table_sim_pp.tex\n", sep = "")
}

pp_split <- build_pp_split_table()
if (is.null(pp_split)) {
  warning("Missing ols_pp split-ratio summaries; skipping table_sim_pp_split.tex")
} else {
  writeLines(pp_split, file.path(TABLES_DIR, "table_sim_pp_split.tex"))
  cat("Wrote ", TABLES_DIR, "/table_sim_pp_split.tex\n", sep = "")
}

real_csv <- results_path(RESULTS_REALDATA, "real_data_results.csv")
generate_real_data_table_from_csv(real_csv)
