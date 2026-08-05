#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/interval_width_vs_extrapolation.R
#
# Does a predictive interval know when it is extrapolating?
#
# The six-method benchmark reports a PICP for every method, and the manuscript
# reads those numbers as calibration. But PICP is a single pooled rate: it
# says what fraction of test profiles fell inside their interval, not whether
# the interval was wide in the right PLACES. On spatially blocked folds that
# distinction is the whole question. A test profile can sit 68 km from the
# nearest training point or 870 km from it, and a method that emits the same
# width at both is not quantifying uncertainty -- it is quoting a constant
# that happens to average out.
#
# This script measures, per method, whether interval width tracks distance to
# the nearest training profile, and whether the method's ERROR does. The
# interesting failure is the pair: error grows, width does not.
#
# WHAT MAKES THIS A FAIR TEST. Distance to training data confounds with
# covariate extrapolation -- profiles far away in space also tend to be
# unusual in climate and texture, and a method can widen for the second reason
# while being blind to the first. Every relation below is therefore reported
# twice: raw, and after partialling out the Mahalanobis distance of the test
# profile's covariates from the training covariate centroid. Only the partial
# relation licenses a claim about SPATIAL extrapolation.
#
# Output: inst/extdata/interval_width_vs_extrapolation.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))
set.seed(20260501L)

B   <- readRDS("inst/extdata/benchmark_wosis_6pilar.rds")
v28 <- readRDS("inst/extdata/benchmark_wosis_p4_p5_p7.rds")

# Rebuild the benchmark's own profile table and folds so this diagnostic is
# scored on exactly the split the published numbers came from.
P <- readRDS("inst/extdata/causal_cerrado_real.rds")$profiles |>
  filter(!is.na(soc_topsoil_gkg), !is.na(lon), !is.na(lat)) |>
  mutate(soc = soc_topsoil_gkg, map = wc_bio_12, mat = wc_bio_01 / 10,
         trees = wc_landcover_trees, cropland = wc_landcover_cropland,
         grass = wc_landcover_grassland, clay = soilgrids_clay,
         sand = soilgrids_sand, bd = soilgrids_bdod)
cov_cols <- B$cov_cols
P <- P[stats::complete.cases(P[, cov_cols]), ]
if (identical(B$response_scale, "log1p")) P$soc <- log1p(P$soc)
prof <- P[, c("lon", "lat", "soc", cov_cols)]
SF <- v28$spatial_folds
stopifnot(!is.null(SF))
message(sprintf("%d profiles, %d buffered folds, %.0f km buffer",
                nrow(prof), length(SF$train), SF$buffer_km))

fml <- stats::as.formula(paste("soc ~", paste(cov_cols, collapse = " + ")))
rows <- vector("list", length(SF$train))

for (fd in seq_along(SF$train)) {
  message(sprintf("  fold %d ...", fd))
  train <- prof[SF$train[[fd]], ]; test <- prof[SF$test[[fd]], ]

  d_near <- apply(.gc_km(cbind(test$lon, test$lat),
                         cbind(train$lon, train$lat)), 1L, min)

  # covariate-space extrapolation, the control
  Xtr <- as.matrix(train[, cov_cols]); Xte <- as.matrix(test[, cov_cols])
  ctr <- colMeans(Xtr)
  S <- stats::cov(Xtr)
  Sinv <- tryCatch(solve(S), error = function(e) MASS::ginv(S))
  d_maha <- sqrt(pmax(0, rowSums((sweep(Xte, 2L, ctr) %*% Sinv) *
                                   sweep(Xte, 2L, ctr))))

  # --- P7 BHS: a geostatistical variance model -----------------------------
  # named explicitly: bhs_fit()'s first formal is `data`, not `formula`
  b7 <- bhs_fit(data = train, formula = fml, coords = c("lon", "lat"),
                nmcmc = 400L, burn = 200L, verbose = FALSE)
  pr7 <- stats::predict(b7, newdata = test, coords = c("lon", "lat"))

  # --- P10 GAT -------------------------------------------------------------
  p10 <- benchmark_fit_p10_gat(train, test, cov_cols, k = 8L, hidden = 12L,
                               n_heads = 2L, n_layers = 2L, epochs = 80L,
                               lr = 0.03, n_ensemble = 8L)
  S10 <- p10$samples

  # --- P5 QRF --------------------------------------------------------------
  rf <- ranger::ranger(fml, data = train, num.trees = 500L,
                       quantreg = TRUE, seed = 1L)
  q5 <- stats::predict(rf, data = test, type = "quantiles",
                       quantiles = c(0.05, 0.95))$predictions

  rows[[fd]] <- data.frame(
    fold = fd, d_km = d_near, d_maha = d_maha, truth = test$soc,
    w_p7  = 2 * 1.645 * pr7$sd,
    w_p10 = apply(S10, 2L, stats::quantile, 0.95) -
            apply(S10, 2L, stats::quantile, 0.05),
    w_p5  = q5[, 2] - q5[, 1],
    e_p7  = abs(pr7$mean - test$soc),
    e_p10 = abs(colMeans(S10) - test$soc),
    e_p5  = abs(stats::predict(rf, data = test)$predictions - test$soc),
    phi_hat = b7$phi_hat, phi_railed = isTRUE(b7$phi_railed),
    phi_rail_edge = b7$phi_rail_edge %||% NA_character_,
    stringsAsFactors = FALSE)
}
D <- do.call(rbind, rows)

# --- the relations ---------------------------------------------------------
# Partial Spearman: rank-residualise both variables on d_maha, then correlate.
partial_rho <- function(a, b, ctrl) {
  ra <- stats::residuals(stats::lm(rank(a) ~ rank(ctrl)))
  rb <- stats::residuals(stats::lm(rank(b) ~ rank(ctrl)))
  stats::cor(ra, rb)
}

methods <- c(P7 = "p7", P5 = "p5", P10 = "p10")
tab <- do.call(rbind, lapply(names(methods), function(lab) {
  m <- methods[[lab]]
  w <- D[[paste0("w_", m)]]; e <- D[[paste0("e_", m)]]
  ct <- stats::cor.test(D$d_km, w, method = "spearman")
  data.frame(
    method       = lab,
    width_rho    = unname(ct$estimate),
    width_p      = ct$p.value,
    width_rho_pc = partial_rho(D$d_km, w, D$d_maha),
    width_slope  = stats::coef(stats::lm(w ~ D$d_km))[2],
    error_rho    = suppressWarnings(stats::cor(D$d_km, e, method = "spearman")),
    error_p      = suppressWarnings(
                     stats::cor.test(D$d_km, e, method = "spearman"))$p.value,
    mean_width   = mean(w),
    stringsAsFactors = FALSE)
}))

cat("\n=== does the interval widen where the method is extrapolating? ===\n")
cat(sprintf("%d test profiles; distance to nearest training profile %.0f-%.0f km (median %.0f)\n",
            nrow(D), min(D$d_km), max(D$d_km), stats::median(D$d_km)))
cat(sprintf("%-5s %10s %10s %12s %11s %10s\n", "", "width rho", "p",
            "partial rho", "error rho", "p"))
for (i in seq_len(nrow(tab))) {
  cat(sprintf("%-5s %+10.3f %10.2g %+12.3f %+11.3f %10.2g\n",
              tab$method[i], tab$width_rho[i], tab$width_p[i],
              tab$width_rho_pc[i], tab$error_rho[i], tab$error_p[i]))
}

if (any(D$phi_railed)) {
  cat("\n  CAVEAT: the P7 profile-MLE of phi railed at its bracket in",
      sum(tapply(D$phi_railed, D$fold, any)), "of",
      length(unique(D$fold)), "folds.\n",
      "  The bracket, not the data, is then setting the correlation rate, so\n",
      "  the P7 slope reports the magnitude of a bracket-determined field.\n",
      "  Its SIGN is structural to kriging and survives; its size is not\n",
      "  interpretable until phi is identified.\n")
}

saveRDS(list(per_profile = D, summary = tab,
             n_folds = length(SF$train), buffer_km = SF$buffer_km,
             built_by = "data-raw/interval_width_vs_extrapolation.R"),
        "inst/extdata/interval_width_vs_extrapolation.rds")
message("\nwrote inst/extdata/interval_width_vs_extrapolation.rds")
