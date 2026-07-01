#!/usr/bin/env Rscript
# plot_sim_figures.R -- ggplot figures from simulation CSV/Rdata
#   → results/figures/ and paper/figures/
#
# Usage (from pc2/):
#   Rscript R/plot_sim_figures.R
#
# Outputs individual PDFs; safe to run after partial simulations (skips missing inputs).

suppressPackageStartupMessages({
  library(ggplot2)
})

source("R/sim_dgp_config.R")

theme_set(theme_bw(base_size = 11))
fig_dir <- results_figures_dir()
paper_fig_dir <- paper_figures_dir()

save_fig <- function(p, filename, width = 7, height = 4) {
  save_figure_gg(p, filename, width = width, height = height)
}

z_t <- function(rho) log((1 + rho) / (1 - rho)) / 2

load_summary <- function() {
  path <- results_path(RESULTS_AGGREGATED, "all_simulations_summary.csv")
  if (!file.exists(path)) {
    message("Skip summary plots (missing ", path, ")")
    return(NULL)
  }
  read.csv(path, stringsAsFactors = FALSE)
}

load_gof_summary <- function() {
  gof_sum <- load_gof_calibration_summary()
  if (is.null(gof_sum)) {
    message("Skip GoF plot (missing ", gof_calibration_csv_path(), ")")
    return(NULL)
  }
  gof_sum
}

#' GoF size and power vs n, one panel per learner (SCAD | OLS). Each panel shows
#' the empirical Type I error (sparse linear, H0) and power (nonlinear, H1), with
#' a dotted reference line at the nominal level alpha = 0.05. Black-and-white safe:
#' the two quantities are distinguished by both marker shape and line type.
plot_gof_size_power <- function(gof_sum) {
  gof_sum$Learner <- ifelse(grepl("_scad_", gof_sum$design), "SCAD", "OLS")
  gof_sum$Learner <- factor(gof_sum$Learner, levels = c("SCAD", "OLS"))
  gof_sum$Quantity <- ifelse(gof_sum$kind == "type1",
                             "Type I error (H0, linear)",
                             "Power (H1, nonlinear)")
  gof_sum$Quantity <- factor(gof_sum$Quantity,
                             levels = c("Type I error (H0, linear)", "Power (H1, nonlinear)"))
  p <- ggplot(gof_sum, aes(x = n, y = rejection_rate, color = Quantity,
                           shape = Quantity, linetype = Quantity, group = Quantity)) +
    geom_hline(yintercept = 0.05, linetype = 3, color = "grey50") +
    geom_line(linewidth = 0.6) +
    geom_point(size = 2.4) +
    facet_wrap(~Learner) +
    scale_x_continuous(breaks = unique(gof_sum$n)) +
    scale_y_continuous(limits = c(0, 1)) +
    scale_shape_manual(values = c(16, 17)) +
    scale_linetype_manual(values = c("solid", "22")) +
    scale_color_manual(values = c("#0072B2", "#D55E00")) +
    labs(x = "Sample size n", y = "Rejection rate",
         color = NULL, shape = NULL, linetype = NULL) +
    theme(legend.position = "top",
          axis.text = element_text(size = 10),
          strip.text = element_text(size = 11))
  save_fig(p, "gof_size_power.pdf", width = 7.2, height = 3.0)
}

#' Read estimator-comparison summaries for the figure. Fixed-ratio (and adaptive
#' RF/DNN) summaries live under comparison/fixed_p/; adaptive OLS/SCAD live under
#' ols_pp/. We read both so every learner/method that has been run is picked up
#' automatically -- adding a new learner only requires re-running the simulations
#' and this script, with no manual edits here.
load_comparison_fixed <- function() {
  files <- unique(c(
    Sys.glob(file.path(RESULTS_ROOT, "comparison/fixed_p/sparse_linear/sim_*_B*_summary.csv")),
    Sys.glob(file.path(RESULTS_ROOT, "comparison/fixed_p/nonlinear/sim_*_B*_summary.csv")),
    Sys.glob(file.path(RESULTS_ROOT, "ols_pp/sparse_linear/sim_*_pp_B*_summary.csv")),
    Sys.glob(file.path(RESULTS_ROOT, "ols_pp/nonlinear/sim_*_pp_B*_summary.csv"))
  ))
  if (length(files) == 0) {
    message("Skip comparison plots (no estimator-comparison summaries)")
    return(NULL)
  }
  df <- do.call(rbind, lapply(files, read.csv, stringsAsFactors = FALSE))
  df[!duplicated(df[c("model", "estimator", "method", "n")]), ]
}

#' Efficiency--validity trade-off: CI coverage and CI length vs n, comparing the
#' fixed even split ($n_1/n=0.5$) against the adaptive procedure, under the sparse linear DGP.
#' Black-and-white safe: marker shape encodes the regression learner and line type
#' encodes fixed vs adaptive. The coverage panel carries a dotted 0.95 line.
plot_coverage_cilength <- function(cmp) {
  meth_labels <- c(scad = "SCAD", rf = "RF", dnn = "DNN", ensemble = "Ensemble")
  d <- subset(cmp, model == "sparse_linear" &
                estimator %in% names(meth_labels) &
                method %in% c("fixed", "adaptive"))
  if (nrow(d) == 0) {
    message("Skip coverage/CI-length plot (no sparse_linear comparison rows)")
    return(invisible(NULL))
  }
  # Drop adaptive points the GoF step accepts only rarely (e.g. RF here, pass
  # rate ~1%): such coverage/length is estimated from a handful of replications
  # and would misleadingly suggest the procedure relies on that learner.
  keep <- !(d$method == "adaptive" & (is.na(d$gof_pass_rate) | d$gof_pass_rate < 0.1))
  d <- d[keep, , drop = FALSE]
  d$Method <- factor(ifelse(d$method == "adaptive", "Adaptive (Ours)", "Fixed even"),
                     levels = c("Adaptive (Ours)", "Fixed even"))
  d$Learner <- factor(meth_labels[d$estimator], levels = unname(meth_labels))
  metric_levels <- c("CI coverage", "CI length")
  long <- rbind(
    data.frame(n = d$n, Method = d$Method, Learner = d$Learner,
               metric = "CI coverage", value = d$ci_coverage),
    data.frame(n = d$n, Method = d$Method, Learner = d$Learner,
               metric = "CI length", value = d$ci_length)
  )
  long <- long[!is.na(long$value), ]
  long$metric <- factor(long$metric, levels = metric_levels)
  href <- data.frame(metric = factor("CI coverage", levels = metric_levels), yint = 0.95)
  shape_vals <- c(SCAD = 16, RF = 15, DNN = 17, Ensemble = 18)
  color_vals <- c(SCAD = "#D55E00", RF = "#0072B2", DNN = "#009E73", Ensemble = "#CC79A7")
  # Draw the fixed-ratio curves first and semi-transparent, then the adaptive
  # curves opaque on top, so a near-coincident adaptive line (e.g. SCAD, where the
  # selected split is essentially an even split) stays visible instead of being hidden.
  d_fixed <- long[long$Method == "Fixed even", , drop = FALSE]
  d_adapt <- long[long$Method == "Adaptive (Ours)", , drop = FALSE]
  p <- ggplot(long, aes(x = n, y = value, color = Learner, shape = Learner,
                        linetype = Method, group = interaction(Learner, Method))) +
    geom_hline(data = href, aes(yintercept = yint), linetype = 3, color = "grey50") +
    geom_line(data = d_fixed, linewidth = 0.5, alpha = 0.9) +
    geom_point(data = d_fixed, size = 2.0, alpha = 0.9) +
    geom_line(data = d_adapt, linewidth = 0.9, alpha = 0.9) +
    geom_point(data = d_adapt, size = 2.4, alpha = 0.9) +
    facet_wrap(~metric, scales = "free_y") +
    scale_x_continuous(breaks = unique(long$n)) +
    scale_shape_manual(values = shape_vals) +
    scale_color_manual(values = color_vals) +
    scale_linetype_manual(values = c("Adaptive (Ours)" = "solid", "Fixed even" = "22")) +
    labs(x = "Sample size n", y = NULL, color = "Learner", shape = "Learner", linetype = NULL) +
    theme(legend.position = "top",
          axis.text = element_text(size = 10),
          strip.text = element_text(size = 11))
  save_fig(p, "coverage_cilength_linear.pdf", width = 7.4, height = 3.4)
}

#' Distribution of the adaptively selected training fraction n1/n, one panel per
#' DGP, using the OLS/linear nuisance runs from Section ols_pp. Drawn as a
#' grayscale heatmap (tile) so it remains distinguishable in black-and-white
#' printing: categories are separated by position on the y axis (the n1/n grid
#' plus a "Rejected" row) and the proportion over all B replications is encoded by
#' a single white-to-black gradient, with the value (in %) printed in larger cells.
#' The "Rejected" row is the share that fails the GoF test at every split ratio
#' (visible under H1 as n grows).
plot_split_ratio_bars <- function() {
  grid <- seq(0.5, 0.95, 0.05)
  ratio_levels <- sprintf("%.2f", grid)
  all_levels <- c(ratio_levels, "Rejected")
  dgp_titles <- c(sparse_linear = "Sparse linear (H0)",
                  nonlinear = "Sparse nonlinear (H1)")
  parts <- list()
  for (dgp in SIM_DGPS) {
    f <- Sys.glob(file.path(RESULTS_ROOT,
                            sprintf("ols_pp/%s/sim_ols_pp_B*_split_ratio.csv", dgp)))
    if (length(f) == 0) next
    B <- as.integer(sub(".*_B(\\d+)_.*", "\\1", basename(f[1])))
    sr <- read.csv(f[1], stringsAsFactors = FALSE)
    sr$bin <- round(as.numeric(sr$n1_over_n) / 0.05) * 0.05
    for (nv in SIM_NS) {
      sub <- sr[sr$n == nv, , drop = FALSE]
      for (g in grid) {
        cnt <- sum(sub$count[abs(sub$bin - g) < 1e-9])
        parts[[length(parts) + 1]] <- data.frame(
          dgp = dgp, n = nv, level = sprintf("%.2f", g), prop = cnt / B)
      }
      rej <- max(0, (B - sum(sub$count)) / B)
      parts[[length(parts) + 1]] <- data.frame(
        dgp = dgp, n = nv, level = "Rejected", prop = rej)
    }
  }
  if (length(parts) == 0) {
    message("Skip split-ratio bars (no ols_pp split_ratio CSVs)")
    return(invisible(NULL))
  }
  df <- do.call(rbind, parts)
  df$level <- factor(df$level, levels = all_levels)
  df$dgp_lab <- factor(dgp_titles[df$dgp], levels = dgp_titles)
  df$lab <- ifelse(df$prop >= 0.05, sprintf("%.0f", 100 * df$prop), "")
  df$txtcol <- ifelse(df$prop >= 0.55, "white", "black")
  p <- ggplot(df, aes(x = factor(n), y = level, fill = prop)) +
    geom_tile(color = "grey60", linewidth = 0.2) +
    geom_text(aes(label = lab, color = txtcol), size = 2.5) +
    facet_wrap(~dgp_lab) +
    scale_fill_gradient(low = "white", high = "black", name = "Proportion (%)",
                        labels = function(x) sprintf("%.0f", 100 * x)) +
    scale_color_identity() +
    scale_y_discrete(limits = all_levels) +
    labs(x = "Sample size n", y = expression(n[1] / n)) +
    theme(axis.text = element_text(size = 10), strip.text = element_text(size = 11),
          panel.grid = element_blank())
  save_fig(p, "split_ratio_distribution.pdf", width = 7.6, height = 3.8)
}

plot_mse_sparse_linear <- function(all_sum) {
  m2 <- subset(all_sum, model == "sparse_linear" & estimator %in% c("scad", "dnn"))
  if (nrow(m2) == 0) {
    message("Skip MSE plot (no sparse_linear scad/dnn rows)")
    return(invisible(NULL))
  }
  p <- ggplot(m2, aes(x = n, y = mse, color = method, linetype = estimator)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 2) +
    labs(x = "n", y = "MSE", color = "Method", linetype = "Estimator",
         title = "MSE under sparse linear DGP") +
    scale_x_continuous(breaks = unique(m2$n))
  save_fig(p, "mse_sparse_linear.pdf")
}

plot_ci_length_scad <- function(all_sum) {
  m2 <- subset(all_sum, model == "sparse_linear" & estimator == "scad")
  if (nrow(m2) == 0) {
    message("Skip CI length plot (no sparse_linear scad rows)")
    return(invisible(NULL))
  }
  p <- ggplot(m2, aes(x = n, y = ci_length, color = method)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 2) +
    labs(x = "n", y = "Mean CI length", color = "Method",
         title = "95% CI length (SCAD, sparse linear DGP)") +
    scale_x_continuous(breaks = unique(m2$n))
  save_fig(p, "ci_length_scad.pdf")
}

plot_selected_split <- function(all_sum) {
  ratio_col <- if ("avg_n1_over_n" %in% names(all_sum)) "avg_n1_over_n" else "avg_ratio"
  adap <- subset(all_sum, method == "adaptive" & !is.na(all_sum[[ratio_col]]))
  if (nrow(adap) == 0) {
    message("Skip split-ratio plot (no adaptive rows)")
    return(invisible(NULL))
  }
  p <- ggplot(adap, aes(x = n, y = .data[[ratio_col]], color = paste(model, estimator))) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 2) +
    labs(x = "n", y = expression(avg~n[1]/n), color = "Setting",
         title = "Adaptive training fraction n1/n") +
    scale_x_continuous(breaks = unique(adap$n))
  save_fig(p, "selected_split_ratio.pdf")
}

#' P-P of sqrt(n2) * {z(rho_hat) - z(rho)} vs N(0,1) for replications passing GoF (Section ols_pp).
plot_adaptive_pp <- function(dgp, est = "ols") {
  rdata <- results_path_sim(dgp, SECTION_OLS_PP, sprintf("sim_%s_pp_B500.Rdata", est))
  if (!file.exists(rdata)) {
    message("Skip ", est, " P-P for ", dgp, " (missing ", rdata, ")")
    return(invisible(NULL))
  }
  e <- new.env()
  load(rdata, envir = e)
  result <- e$result
  rho <- if (exists("rho_true", envir = e)) e$rho_true else sim_rho_true()
  z0 <- z_t(rho)
  ns <- sort(unique(result[, "n"]))
  rows <- list()
  for (n_val in ns) {
    sub <- result[result[, "n"] == n_val & result[, "passed"] == 1, , drop = FALSE]
    if (nrow(sub) == 0) next
    stat <- sort(sqrt(sub[, "n2"]) * (sub[, "zrho"] - z0))
    m <- length(stat)
    rows[[length(rows) + 1]] <- data.frame(
      n = n_val,
      theoretical = pnorm(stat),
      empirical = ppoints(m)
    )
  }
  if (length(rows) == 0) {
    message("Skip ", est, " P-P for ", dgp, " (no passed replications)")
    return(invisible(NULL))
  }
  df <- do.call(rbind, rows)
  p <- ggplot(df, aes(x = theoretical, y = empirical)) +
    geom_point(size = 1.2, alpha = 0.6) +
    geom_abline(slope = 1, intercept = 0, linetype = 2) +
    facet_wrap(~n, nrow = 1, labeller = label_both) +
    scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, by = 0.5)) +
    scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, by = 0.5)) +
    coord_fixed() +
    labs(x = NULL, y = NULL, title = NULL, subtitle = NULL, caption = NULL) +
    theme(
      axis.text = element_text(size = 11),
      strip.text = element_text(size = 11),
      panel.spacing.x = grid::unit(1.4, "lines")
    )
  save_fig(p, sprintf("%s_pp_%s.pdf", est, dgp), width = 7.2, height = 2.1)
}

# --- main ---
message("Writing figures to ", fig_dir, "/ and ", paper_fig_dir, "/")

gof_sum <- load_gof_summary()
if (!is.null(gof_sum)) plot_gof_size_power(gof_sum)

cmp_fixed <- load_comparison_fixed()
if (!is.null(cmp_fixed)) plot_coverage_cilength(cmp_fixed)

plot_split_ratio_bars()

all_sum <- load_summary()
if (!is.null(all_sum)) {
  plot_mse_sparse_linear(all_sum)
  plot_ci_length_scad(all_sum)
  plot_selected_split(all_sum)
}

for (est in OLS_PP_ESTIMATORS) {
  for (dgp in SIM_DGPS) {
    plot_adaptive_pp(dgp, est)
  }
}

message("Done.")
