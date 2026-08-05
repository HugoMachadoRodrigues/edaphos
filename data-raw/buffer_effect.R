#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/buffer_effect.R
#
# What does the 68 km CV buffer cost each method?
#
# The manuscript claims the buffer changes the ranking -- that the graph
# attention network scores half a rank better without it, and that no other
# method moves by more than 0.01 RMSE. Both halves were measured once, by
# hand, and hard-coded into a sentence. Neither could be reproduced from the
# repository, and the GAT number in particular was taken before the Pillar-10
# graph was corrected to great-circle distance, so it described a different
# model from the one the buffered figure describes.
#
# This script runs the identical six-method harness on UNBUFFERED folds --
# same k-means blocks, same seeds, same budgets, buffer_km = 0 -- and compares
# against the buffered bundle. Every number in that sentence then comes from a
# file.
#
# Output: inst/extdata/buffer_effect.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))
set.seed(20260501L)

BUF <- readRDS("inst/extdata/benchmark_wosis_6pilar.rds")
v28 <- readRDS("inst/extdata/benchmark_wosis_p4_p5_p7.rds")

P <- readRDS("inst/extdata/causal_cerrado_real.rds")$profiles |>
  filter(!is.na(soc_topsoil_gkg), !is.na(lon), !is.na(lat)) |>
  mutate(soc = soc_topsoil_gkg, map = wc_bio_12, mat = wc_bio_01 / 10,
         trees = wc_landcover_trees, cropland = wc_landcover_cropland,
         grass = wc_landcover_grassland, clay = soilgrids_clay,
         sand = soilgrids_sand, bd = soilgrids_bdod)
cov_cols <- BUF$cov_cols
P <- P[stats::complete.cases(P[, cov_cols]), ]
if (identical(BUF$response_scale, "log1p")) P$soc <- log1p(P$soc)
prof <- P[, c("lon", "lat", "soc", cov_cols)]

# The SAME blocks, with the buffer switched off. Reusing the fold labels
# rather than re-clustering keeps the test partitions identical, so the only
# difference between the two runs is which training rows are discarded.
fold <- v28$spatial_folds$fold
stopifnot(length(fold) == nrow(prof))
K <- length(unique(fold))
message(sprintf("%d profiles, %d blocks; buffered run discarded %d training rows",
                nrow(prof), K, sum(v28$spatial_folds$n_buffered)))

fml <- stats::as.formula(paste("soc ~", paste(cov_cols, collapse = " + ")))
rows <- list()

for (fd in seq_len(K)) {
  message(sprintf("  fold %d/%d ...", fd, K))
  test  <- prof[fold == fd, ]
  train <- prof[fold != fd, ]          # NO buffer: the exact complement
  truth <- test$soc
  train_mean <- mean(train$soc)

  # `uncertainty_calibrate()` returns picp/mpiw as NAMED VECTORS over the
  # requested levels, not scalar fields -- the same lookup the main harness
  # uses, kept identical so the two runs are comparable rather than merely
  # similar.
  pick <- function(v, keys) {
    for (k in keys) if (k %in% names(v)) return(as.numeric(v[[k]]))
    NA_real_
  }
  add <- function(label, post, secs) {
    if (is.null(post)) return(invisible(NULL))
    cal <- tryCatch(uncertainty_calibrate(post, truth = truth),
                    error = function(e) NULL)
    pt <- colMeans(post$samples)
    rows[[length(rows) + 1L]] <<- data.frame(
      fold = fd, method = label,
      rmse = sqrt(mean((pt - truth)^2)),
      nse  = edaphos_nse(truth, pt, null_prediction = train_mean),
      picp90 = if (is.null(cal)) NA_real_ else pick(cal$picp, c("0.90", "0.9")),
      elapsed = unname(secs), stringsAsFactors = FALSE)
  }

  t1 <- system.time(p1 <- tryCatch(
    benchmark_fit_p1_causal(train, test, cov_cols, n_boot = 300L),
    error = function(e) NULL))["elapsed"]
  add("P1 OLS (DAG-selected covariates)", p1, t1)

  t5 <- system.time({
    rf <- ranger::ranger(fml, data = train, num.trees = 500L,
                         quantreg = TRUE, seed = 1L)
    qs <- seq(0.025, 0.975, length.out = 40L)
    p5 <- edaphos_posterior(
      samples = t(stats::predict(rf, data = test, type = "quantiles",
                                 quantiles = qs)$predictions),
      method = "loo_cv", query_type = "map", units = BUF$response_units)
  })["elapsed"]
  add("P5 QRF", p5, t5)

  t7 <- system.time({
    b7 <- bhs_fit(data = train, formula = fml, coords = c("lon", "lat"),
                  nmcmc = 400L, burn = 200L, verbose = FALSE)
    pr <- stats::predict(b7, newdata = test, coords = c("lon", "lat"))
    sm <- vapply(seq_len(nrow(test)), function(j)
      stats::rnorm(200L, pr$mean[j], pr$sd[j]), numeric(200L))
    p7 <- edaphos_posterior(samples = sm, method = "bayesian",
                            query_type = "map", units = BUF$response_units)
  })["elapsed"]
  add("P7 BHS", p7, t7)

  t6 <- system.time(p6 <- tryCatch(
    benchmark_fit_p6_quantum(train, test, cov_cols, n_pcs = 6L, reps = 2L,
                             lambda = 0.5, n_boot = 100L),
    error = function(e) NULL))["elapsed"]
  add("P6 Quantum KRR", p6, t6)

  t10 <- system.time(p10 <- tryCatch(
    benchmark_fit_p10_gat(train, test, cov_cols, k = 8L, hidden = 12L,
                          n_heads = 2L, n_layers = 2L, epochs = 80L,
                          lr = 0.03, n_ensemble = 8L),
    error = function(e) NULL))["elapsed"]
  add("P10 GAT (trained attention)", p10, t10)
}

# P4 needs the MoCo encoder and the covariate stack; it is scored in the
# v2.8.0 harness rather than here. Reported as absent rather than omitted.
UNB <- do.call(rbind, rows)
agg <- UNB |>
  group_by(method) |>
  summarise(rmse_mean = mean(rmse), nse_mean = mean(nse),
            picp90_mean = mean(picp90, na.rm = TRUE), .groups = "drop") |>
  as.data.frame()

cmp <- merge(agg, BUF$cv_aggregate[, c("method", "rmse_mean", "nse_mean",
                                       "picp90_mean")],
             by = "method", suffixes = c("_unbuf", "_buf"))
cmp$d_rmse <- cmp$rmse_mean_buf - cmp$rmse_mean_unbuf
cmp <- cmp[order(cmp$rmse_mean_buf), ]
cmp$rank_buf   <- rank(cmp$rmse_mean_buf)
cmp$rank_unbuf <- rank(cmp$rmse_mean_unbuf)

cat("\n=== what the 68 km buffer costs each method (RMSE, log1p g/kg) ===\n")
cat(sprintf("%-34s %9s %9s %8s %6s %6s\n", "method", "unbuffered", "buffered",
            "delta", "rk_un", "rk_bu"))
for (i in seq_len(nrow(cmp)))
  cat(sprintf("%-34s %9.3f %9.3f %+8.3f %6.0f %6.0f\n", cmp$method[i],
              cmp$rmse_mean_unbuf[i], cmp$rmse_mean_buf[i], cmp$d_rmse[i],
              cmp$rank_unbuf[i], cmp$rank_buf[i]))
cat(sprintf("\nlargest movement: %s (%+.3f)\n",
            cmp$method[which.max(abs(cmp$d_rmse))], max(abs(cmp$d_rmse))))
others <- cmp$d_rmse[-which.max(abs(cmp$d_rmse))]
cat(sprintf("every other method moved by at most %.3f\n", max(abs(others))))
cat("\nNOTE: P4 (foundation embeddings) is scored in the v2.8.0 harness and is\n")
cat("      not re-run here, so it is absent from this comparison.\n")

saveRDS(list(fold_table = UNB, aggregate = agg, comparison = cmp,
             buffer_km = v28$spatial_folds$buffer_km,
             n_buffered = v28$spatial_folds$n_buffered,
             built_by = "data-raw/buffer_effect.R"),
        "inst/extdata/buffer_effect.rds")
message("\nwrote inst/extdata/buffer_effect.rds")
