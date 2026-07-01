#' Export simulation metrics from a result matrix to a data frame row.
export_sim_metrics <- function(result, rho_true, meta) {
  m <- compute_metrics(result, rho_true, meta$method_label)
  data.frame(
    model = meta$model,
    estimator = meta$estimator,
    method = meta$method,
    rho_true = meta$rho_true,
    n = meta$n,
    bias = m$bias,
    sd_rho = m$sd,
    mse = m$mse,
    ci_coverage = m$ci_coverage,
    ci_length = m$ci_length,
    gof_pass_rate = m$proportion,
    avg_n1_over_n = m$avg_n1_over_n,
    avg_n1 = m$avg_n1,
    avg_n2 = m$avg_n2,
    avg_K = m$avg_K,
    avg_K0 = m$avg_K0,
    stringsAsFactors = FALSE
  )
}

#' Distribution of selected training fraction n1/n across replications (adaptive runs).
write_split_ratio_csv <- function(result, rdata_path) {
  if (!all(c("n1", "n2") %in% colnames(result))) return(invisible(NULL))
  valid <- !is.na(result[, "n1"]) & !is.na(result[, "n2"]) &
    (result[, "n1"] + result[, "n2"]) > 0
  if (!any(valid)) return(invisible(NULL))
  ns <- unique(result[, "n"])
  rows <- list()
  for (n_val in ns) {
    sub <- result[result[, "n"] == n_val & valid, , drop = FALSE]
    if (nrow(sub) == 0) next
    r <- round(train_frac(sub[, "n1"], sub[, "n2"]), 3)
    tab <- as.data.frame(table(n1_over_n = r), stringsAsFactors = FALSE)
    tab$n <- n_val
    tab$count <- as.integer(tab$Freq)
    tab$proportion <- round(tab$count / sum(tab$count), 3)
    tab$Freq <- NULL
    rows[[length(rows) + 1]] <- tab
  }
  if (length(rows) == 0) return(invisible(NULL))
  df <- do.call(rbind, rows)
  csv_path <- sub("\\.Rdata$", "_split_ratio.csv", rdata_path)
  write.csv(df, csv_path, row.names = FALSE)
  invisible(df)
}

#' Write per-simulation summary CSV next to an .Rdata file.
write_sim_summary_csv <- function(rdata_path, rho_true, meta) {
  e <- new.env()
  load(rdata_path, envir = e)
  if (!exists("result", envir = e)) {
    warning("No 'result' in ", rdata_path)
    return(invisible(NULL))
  }
  result <- e$result
  ns <- if (exists("ns", envir = e)) e$ns else unique(result[, "n"])
  rows <- list()
  for (n_val in ns) {
    sub <- result[result[, "n"] == n_val, , drop = FALSE]
    meta_n <- meta
    meta_n$n <- n_val
    meta_n$method_label <- sprintf("%s_n%d", meta$method_label, n_val)
    rows[[length(rows) + 1]] <- export_sim_metrics(sub, rho_true, meta_n)
  }
  df <- do.call(rbind, rows)
  csv_path <- sub("\\.Rdata$", "_summary.csv", rdata_path)
  write.csv(df, csv_path, row.names = FALSE)
  if (meta$method == "adaptive") {
    write_split_ratio_csv(result, rdata_path)
  }
  invisible(df)
}
