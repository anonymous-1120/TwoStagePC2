# MillionSongSubset/real_data_report.R -- LaTeX table + seed metadata for Section 5 (real data)

fmt_dot <- function(x, digits = 3) {
  if (length(x) == 0 || is.na(x)) return("$\\cdot$")
  format(round(x, digits), nsmall = digits)
}

fmt_pval <- function(x) {
  if (is.na(x)) return("---")
  if (x < 0.001) return("$<0.001$")
  sprintf("%.3f", x)
}

fmt_pass <- function(passed, adaptive, skipped = FALSE) {
  if (isTRUE(skipped)) return("---")
  if (!isTRUE(adaptive) || is.na(passed)) return("---")
  if (passed == 1) return("Yes") else return("No")
}

fmt_kappa <- function(x) {
  if (is.na(x)) return("$\\cdot$")
  sprintf("%.2f", x)
}

# Training fraction n_1/n = (n - n_2)/n. Derived from the evaluation size n2
# (authoritative) rather than the stored n1_over_n2 column, whose meaning was
# inconsistent across adaptive vs. fixed rows.
fmt_frac <- function(x) {
  if (length(x) == 0 || is.na(x)) return("$\\cdot$")
  sprintf("%.2f", x)
}

fmt_ci <- function(lo, hi) {
  if (is.na(lo) || is.na(hi)) return("$\\cdot$")
  sprintf("(%s, %s)", fmt_dot(lo, 3), fmt_dot(hi, 3))
}

realdata_seed_base <- function() {
  raw <- Sys.getenv("TWOSTAGEPC_REALDATA_SEED", unset = "")
  if (nzchar(raw)) return(as.integer(raw))
  REALDATA_SEED_BASE
}

realdata_adaptive_seed <- function(est, base = realdata_seed_base()) {
  as.integer(base + REALDATA_ADAPTIVE_OFFSETS[[est]])
}

realdata_fixed_seed <- function(est, base = realdata_seed_base()) {
  as.integer(base + REALDATA_FIXED_OFFSETS[[est]])
}

realdata_results_csv_name <- function(seed_base = realdata_seed_base()) {
  sprintf("real_data_results_seed%d.csv", seed_base)
}

realdata_meta_json_name <- function(seed_base = realdata_seed_base()) {
  sprintf("real_data_run_meta_seed%d.json", seed_base)
}

realdata_seed_map <- function(seed_base = realdata_seed_base()) {
  adaptive <- setNames(
    as.integer(seed_base + REALDATA_ADAPTIVE_OFFSETS),
    names(REALDATA_ADAPTIVE_OFFSETS)
  )
  fixed <- setNames(
    as.integer(seed_base + REALDATA_FIXED_OFFSETS),
    names(REALDATA_FIXED_OFFSETS)
  )
  list(seed_base = as.integer(seed_base), adaptive = adaptive, fixed = fixed)
}

write_real_data_run_meta <- function(seed_base = realdata_seed_base(),
                                     n, p,
                                     out_dir = file.path(RESULTS_ROOT, RESULTS_REALDATA)) {
  seeds <- realdata_seed_map(seed_base)
  meta <- c(
    list(
      seed_base = seeds$seed_base,
      n = as.integer(n),
      p = as.integer(p),
      adaptive_split_method = ADAPTIVE_SPLIT_METHOD,
      adaptive_nsplits = as.integer(ADAPTIVE_NSPLITS),
      adaptive_rho_grid = adaptive_rho_grid(),
      adaptive_gof_alpha = ADAPTIVE_GOF_ALPHA,
      results_csv = realdata_results_csv_name(seed_base),
      r_version = paste(R.version$major, R.version$minor, sep = "."),
      timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    seeds
  )
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    path <- file.path(out_dir, sub("\\.json$", ".txt", realdata_meta_json_name(seed_base)))
    lines <- c(
      sprintf("seed_base: %d", seed_base),
      sprintf("results_csv: %s", realdata_results_csv_name(seed_base)),
      "adaptive_seeds:",
      sprintf("  %s: %d", names(seeds$adaptive), seeds$adaptive),
      "fixed_seeds:",
      sprintf("  %s: %d", names(seeds$fixed), seeds$fixed)
    )
    writeLines(lines, path)
    return(invisible(path))
  }
  path <- file.path(out_dir, realdata_meta_json_name(seed_base))
  jsonlite::write_json(meta, path, auto_unbox = TRUE, pretty = TRUE)
  invisible(path)
}

real_data_row_labels <- function(method, adaptive) {
  m <- method
  m <- gsub(" \\(adaptive\\)$", "", m, ignore.case = TRUE)
  m <- gsub(" \\(fixed 50/50\\)$", "", m, ignore.case = TRUE)
  m <- gsub(" \\(fixed even\\)$", "", m, ignore.case = TRUE)
  m <- gsub(" \\(SCAD\\+RF\\+NN\\)$", "", m, ignore.case = TRUE)
  splitting <- if (isTRUE(adaptive)) "Adaptive" else "Fixed"
  list(splitting = splitting, method = m)
}

#' Build LaTeX fragment for tab:realData from results CSV.
write_real_data_latex_table <- function(rows, n, p,
                                        seed_base = realdata_seed_base(),
                                        out_path = file.path("results", "tables", "table_real_data.tex")) {
  if ("seed_base" %in% names(rows) && !all(is.na(rows$seed_base))) {
    seed_base <- as.integer(rows$seed_base[1L])
  }
  csv_name <- basename(realdata_results_csv_name(seed_base))
  tex_lines <- c(
    sprintf("%% Generated from %s", csv_name),
    "\\begin{table}[!htb]",
    "\\centering",
    paste0(
      "\\caption{Partial correlation between tempo and loudness in the Million Song subset. ",
      "Adaptive rows use Algorithm~\\ref{alg:pcConsistent} with GoF level ",
      "$\\alpha=0.05$. Fixed-ratio rows use an even split ($n_1/n=0.5$) without the GoF ",
      "step (OLS, SCAD, DNN, random forest, and an ensemble averaging SCAD, RF, and the DNN). ",
      "Entries marked $\\cdot$ indicate that the GoF test did not pass and no partial-correlation ",
      "estimate is reported.}"
    ),
    "\\label{tab:realData}",
    "\\small",
    "\\begin{tabular}{c l r c r r r r}",
    "\\toprule",
    "Sample splitting & Method & GoF $p$ & Pass & $n_1/n$ & $\\hat\\rho$ & 95\\% C.I. & CI len. \\\\",
    "\\midrule"
  )

  adaptive_idx <- which(rows$adaptive)
  fixed_idx <- which(!rows$adaptive)
  n_adaptive <- length(adaptive_idx)
  n_fixed <- length(fixed_idx)

  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    if (i > 1L && isTRUE(rows$adaptive[i - 1L]) && !isTRUE(r$adaptive)) {
      tex_lines <- c(tex_lines, "\\midrule")
    }
    skipped <- isTRUE(r$skipped)
    est_col <- if (is.na(r$estimate) || skipped) "$\\cdot$" else fmt_dot(r$estimate, 3)
    labels <- real_data_row_labels(r$method, r$adaptive)
    method_tex <- gsub("_", "\\_", labels$method, fixed = TRUE)
    split_col <- ""
    if (isTRUE(r$adaptive) && i == adaptive_idx[1L]) {
      split_col <- sprintf("\\multirow{%d}{*}{Adaptive}", n_adaptive)
    } else if (!isTRUE(r$adaptive) && i == fixed_idx[1L]) {
      split_col <- sprintf("\\multirow{%d}{*}{Fixed}", n_fixed)
    }
    tex_lines <- c(tex_lines, sprintf(
      "%s & %s & %s & %s & %s & %s & %s & %s \\\\",
      split_col,
      method_tex,
      if (skipped) "---" else fmt_pval(r$gof_pvalue),
      fmt_pass(r$passed, r$adaptive, skipped),
      if (skipped) "$\\cdot$" else fmt_frac((n - r$n2) / n),
      est_col,
      if (skipped) "$\\cdot$" else fmt_ci(r$ci_low, r$ci_high),
      if (is.na(r$ci_length) || skipped) "$\\cdot$" else fmt_dot(r$ci_length, 3)
    ))
  }

  tex_lines <- c(tex_lines, "\\bottomrule", "\\end{tabular}", "\\end{table}")
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  writeLines(tex_lines, out_path)
  invisible(out_path)
}

read_real_data_results <- function(csv_path) {
  if (!file.exists(csv_path)) return(NULL)
  read.csv(csv_path, stringsAsFactors = FALSE)
}

real_data_dimensions <- function(csv_data_path = "MillionSongSubset/realData_song.csv") {
  d <- read.csv(csv_data_path)
  list(n = nrow(d), p = ncol(d) - 2L)
}

generate_real_data_table_from_csv <- function(csv_path,
                                              out_path = file.path("results", "tables", "table_real_data.tex"),
                                              song_csv = "MillionSongSubset/realData_song.csv") {
  rows <- read_real_data_results(csv_path)
  if (is.null(rows)) {
    message("No real-data CSV at ", csv_path, "; skipping table_real_data.tex")
    return(invisible(NULL))
  }
  dims <- real_data_dimensions(song_csv)
  seed_base <- if ("seed_base" %in% names(rows)) as.integer(rows$seed_base[1L]) else realdata_seed_base()
  write_real_data_latex_table(rows, dims$n, dims$p, seed_base = seed_base, out_path = out_path)
  message("Wrote ", out_path)
  invisible(out_path)
}
