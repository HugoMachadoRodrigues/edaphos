## data-raw/benchmark_wosis_p4_p5_p7.R  (v2.8.0)
##
## Head-to-head benchmark of three pillars on the 1 095 real WoSIS
## Cerrado topsoil profiles:
##
##   P4 Foundation (MoCo v1 embeddings + RBF-KRR head)
##   P5 Active-Learning backbone (QRF quantile-regression forest)
##   P7 Bayesian Hierarchical Spatial (Gibbs sampler, v2.3.0)
##
## Evaluation: 5-fold spatial CV (k-means on lon/lat).  For each fold
## each method produces either a quantile grid (P5, P4 RBF-KRR) or an
## MCMC posterior (P7 Gibbs); we unify them through the v1.6.0
## `edaphos_posterior` class and score with `uncertainty_calibrate()`.
##
## Output: inst/extdata/benchmark_wosis_p4_p5_p7.rds

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))
set.seed(20260424L)

OUT_PATH <- file.path("inst", "extdata", "benchmark_wosis_p4_p5_p7.rds")

# ─────────────────────────────────────────────────────────────────────────────
# 1. Load the 1 095 real WoSIS Cerrado profiles
# ─────────────────────────────────────────────────────────────────────────────
message("=== [1/7] Loading WoSIS profiles ===")
causal_rds <- readRDS("inst/extdata/causal_cerrado_real.rds")
profiles <- causal_rds$profiles |>
  filter(!is.na(soc_topsoil_gkg), !is.na(lon), !is.na(lat)) |>
  mutate(
    soc      = soc_topsoil_gkg,
    map      = wc_bio_12,
    mat      = wc_bio_01 / 10,
    trees    = wc_landcover_trees,
    cropland = wc_landcover_cropland,
    grass    = wc_landcover_grassland,
    clay     = soilgrids_clay,
    sand     = soilgrids_sand,
    bd       = soilgrids_bdod
  )
message(sprintf("  n = %d profiles", nrow(profiles)))
message(sprintf("  soc: mean=%.2f, sd=%.2f, range=[%.2f, %.2f]",
                mean(profiles$soc), stats::sd(profiles$soc),
                min(profiles$soc),  max(profiles$soc)))

cov_cols <- c("map", "mat", "slope", "elev", "clay", "sand", "bd",
               "trees", "cropland", "grass")
cov_cols <- intersect(cov_cols, names(profiles))
profiles <- profiles[stats::complete.cases(profiles[, cov_cols]), ]
message(sprintf("  After NA drop: %d profiles", nrow(profiles)))

# Response scale -- must match data-raw/benchmark_wosis_6pilar.R, which merges
# this bundle.  See the long note there: on raw g/kg, 1 % of profiles carry
# 48 % of the sum of squares and every method scores near zero; log1p is the
# conventional scale for soil organic carbon.
RESPONSE_SCALE <- if (identical(Sys.getenv("EDAPHOS_BENCH_SCALE"), "raw"))
  "raw" else "log1p"
if (RESPONSE_SCALE == "log1p") profiles$soc <- log1p(profiles$soc)
RESPONSE_UNITS <- if (RESPONSE_SCALE == "log1p") "log1p(g/kg)" else "g/kg"
message(sprintf("  response scale: %s (%s)", RESPONSE_SCALE, RESPONSE_UNITS))

PROFILE_YEARS <- suppressWarnings(as.numeric(profiles$year))
YEAR_SUMMARY <- list(
  min = suppressWarnings(min(PROFILE_YEARS, na.rm = TRUE)),
  median = stats::median(PROFILE_YEARS, na.rm = TRUE),
  max = suppressWarnings(max(PROFILE_YEARS, na.rm = TRUE)),
  n_missing = sum(is.na(PROFILE_YEARS)),
  covariate_epoch = "SoilGrids 2020 / WorldClim 2.1 (1970-2000) / SRTM 2000 / WorldCover 2020"
)

# ─────────────────────────────────────────────────────────────────────────────
# 2. 5-fold spatial CV (k-means cluster)
# ─────────────────────────────────────────────────────────────────────────────
message("=== [2/7] Building 5 buffered spatial folds ===")
# BUFFERED blocking. The training set used to be the exact complement of the
# test block, with no dead zone: the measured minimum training-to-test
# great-circle distance was 12.3 km, well inside the 55-68 km range at which
# the fitted depth-function parameters are still correlated
# (data-raw/piml_parameter_variograms.R). Blocking without a buffer
# under-states generalisation error (Roberts et al. 2017).
SF <- spatial_block_folds(profiles[, c("lon", "lat")], k = 5L,
                          buffer_km = 68, seed = 1L)
folds <- SF$fold
profiles$fold5 <- folds
message(sprintf("  buffer %.0f km: %d training rows discarded, realised ",
                SF$buffer_km, sum(SF$n_buffered)),
        sprintf("min train-test distance %.1f km", min(SF$min_dist_km)))
tab <- table(folds)
message(sprintf("  fold sizes: %s",
                 paste(sprintf("%d=%d", as.integer(names(tab)),
                                 as.integer(tab)),
                        collapse = ", ")))

# ─────────────────────────────────────────────────────────────────────────────
# 3. Method wrappers  -- each returns a posterior of (n_test) preds
# ─────────────────────────────────────────────────────────────────────────────

# P5: QRF quantile regression forest -> quantile grid
fit_p5_qrf <- function(train, test, cov_cols) {
  df_tr <- train[, c("soc", cov_cols), drop = FALSE]
  rf <- ranger::ranger(soc ~ ., data = df_tr,
                         num.trees = 500L, quantreg = TRUE,
                         verbose = FALSE)
  qs <- seq(0.01, 0.99, length.out = 99L)
  pr <- predict(rf, data = test[, cov_cols, drop = FALSE],
                 type = "quantiles", quantiles = qs)$predictions
  edaphos_posterior(samples = t(pr), method = "loo_cv",
                      query_type = "map", units = "g/kg")
}

# P4 Foundation: MoCo v1 encoder + ranger head on embeddings
fit_p4_foundation <- function(train, test, cov_cols, moco, dataset_meta,
                                synth_stack) {
  emb_all <- foundation_embed_at_coords(
    moco        = moco,
    coords      = rbind(train[, c("lon", "lat")],
                           test[, c("lon", "lat")]),
    stack       = synth_stack,
    dataset     = dataset_meta,
    patch_size  = 16L, batch_size = 64L
  )
  n_tr <- nrow(train)
  emb_tr <- emb_all[seq_len(n_tr), , drop = FALSE]
  emb_te <- emb_all[seq(n_tr + 1L, nrow(emb_all)), , drop = FALSE]
  # Impute column-mean for any NA rows at the edge -- ranger cannot
  # accept NA; training points with NA get their embedding row
  # replaced by the training-pool mean, same for test.
  col_mean_tr <- colMeans(emb_tr, na.rm = TRUE)
  fill_na <- function(M, means) {
    for (j in seq_len(ncol(M))) {
      na_ij <- is.na(M[, j])
      if (any(na_ij)) M[na_ij, j] <- means[j]
    }
    M
  }
  emb_tr <- fill_na(emb_tr, col_mean_tr)
  emb_te <- fill_na(emb_te, col_mean_tr)
  df_tr <- cbind(train[, c("soc", cov_cols), drop = FALSE],
                   as.data.frame(emb_tr))
  df_te <- cbind(test[, cov_cols, drop = FALSE],
                   as.data.frame(emb_te))
  rf <- ranger::ranger(soc ~ ., data = df_tr,
                         num.trees = 500L, quantreg = TRUE,
                         verbose = FALSE)
  qs <- seq(0.01, 0.99, length.out = 99L)
  pr <- predict(rf, data = df_te,
                 type = "quantiles", quantiles = qs)$predictions
  edaphos_posterior(samples = t(pr), method = "ensemble",
                      query_type = "map", units = "g/kg")
}

# P7 BHS: Bayesian hierarchical spatial (Gibbs v2.3.0)
fit_p7_bhs <- function(train, test, cov_cols,
                         nmcmc = 400L, burn = 200L) {
  # Simple additive model with a spatial random effect
  fml <- stats::as.formula(paste("soc ~", paste(cov_cols, collapse = " + ")))
  fit <- bhs_fit(data = train, formula = fml,
                   coords = c("lon", "lat"),
                   backend = if (requireNamespace("edaphos", quietly = TRUE))
                                "rcpp" else "gibbs",
                   nmcmc = nmcmc, burn = burn,
                   # NO PINNED BRACKET. This read `phi_range = c(0.05, 5)`, a
                   # hand-picked constant that appears nowhere else and was
                   # never justified -- and whose lower end corresponds to a
                   # correlation range of 60 degrees, nearly three times the
                   # width of the domain. The profile-MLE railed against it,
                   # so that constant, not the data, set the correlation rate.
                   #
                   # bhs_fit() now derives the bracket from the data geometry,
                   # bounded by the closest pair and the domain diameter. It
                   # still rails, at the lower end: these data want a range
                   # longer than the region they cover, which is the same as
                   # saying the latent field is not distinguishable from the
                   # intercept. That is the honest reading and it COSTS us --
                   # fold-mean RMSE goes from 0.605 under the pin to 0.615 --
                   # which is exactly why the pin had to go rather than stay.
                   seed = 1L, verbose = FALSE)
  pr <- predict(fit, newdata = test,
                 quantiles = seq(0.025, 0.975, length.out = 20L),
                 n_draws = 200L, draws = TRUE)
  # THE SAMPLER'S OWN DRAWS, not a Gaussian fitted to their summary.
  #
  # This used to be `samps[, j] <- rnorm(200, pr$mean[j], pr$sd[j])`: the
  # Gibbs posterior was computed, reduced to a mean and an sd, and then a
  # fresh Gaussian was simulated from those two numbers. Every uncertainty
  # figure P7 published -- CRPS, PICP -- was therefore scoring that Gaussian,
  # not the sampler, and nothing said so.
  #
  # HOW MUCH IT MATTERS IS AN EMPIRICAL QUESTION, and the honest answer on
  # this model is: less than the principle suggests. The predictive is a scale
  # mixture of normals -- one component per posterior draw of
  # (beta, sigma^2, tau^2) -- so it is leptokurtic, heavier-tailed than the
  # moment-matched Gaussian. But the mixture only separates from that Gaussian
  # when the component variances differ appreciably across draws, and here
  # they barely do: phi rails, the latent field is not distinguishable from a
  # nugget, and tau^2 is tightly identified. Measured on a 21x21 br_cerrado
  # block with 60 held-out sites, mixture against moment-matched Gaussian:
  # CRPS 3.159 vs 3.172, PICP at 50/80/90/95% identical to three decimals,
  # mean kurtosis 3.04 vs 2.95.
  #
  # The substitution is still wrong to ship. A published CRPS and PICP that
  # were computed from a distribution the sampler did not produce, with
  # nothing saying so, is a defect whether or not it moves the third decimal
  # -- and its size on THIS archive is measured below, not assumed.
  #
  # predict.edaphos_bhs() had these draws all along and discarded them; it now
  # returns them under `draws = TRUE`.
  samps <- attr(pr, "draws")
  stopifnot(is.matrix(samps), ncol(samps) == nrow(test))
  edaphos_posterior(samples = samps, method = "bayesian",
                      query_type = "map", units = "g/kg")
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Set up MoCo v1 encoder + synthetic stack (shared across folds)
# ─────────────────────────────────────────────────────────────────────────────
message("=== [3/7] Loading MoCo v1 encoder + building the real covariate stack ===")
moco <- foundation_weights_load("edaphos-cerrado-moco-v1", verbose = FALSE)
bbox <- c(min(profiles$lon) - 0.2, min(profiles$lat) - 0.2,
           max(profiles$lon) + 0.2, max(profiles$lat) + 0.2)
library(terra)

# Through v3.10.0 this benchmark ran the encoder over a raster of pure
# stats::rnorm() noise and published the resulting row as part of the
# "first honest cross-pillar comparison".  An encoder applied to noise
# measures nothing about the encoder.  Build the real 31-channel
# SoilGrids + WorldClim + SRTM stack at the grid the encoder was trained
# on, exactly as data-raw/causal_iv_benchmark_real.R does.
GEOCACHE <- if (nzchar(Sys.getenv("EDAPHOS_GEOCACHE")))
  Sys.getenv("EDAPHOS_GEOCACHE") else
  tools::R_user_dir("edaphos", which = "cache")
stk <- foundation_build_cerrado_stack(bbox = bbox, target_res = 0.01,
                                       cache_dir = GEOCACHE,
                                       schema = "v1_encoder")
stopifnot(terra::nlyr(stk) == moco$n_channels)

# The v1 encoder's training means / sds were never persisted (the weights
# registry records norm_stats_status = "unrecoverable"), so standardise
# per channel over this AoI and record that this is an approximation of
# the training normalisation, not a reconstruction of it.
ch_stats <- terra::global(stk, fun = c("mean", "sd"), na.rm = TRUE)
dataset_meta <- list(
  patch_size = 16L, n_channels = moco$n_channels,
  means = as.numeric(ch_stats[, "mean"]),
  sds   = pmax(as.numeric(ch_stats[, "sd"]), .Machine$double.eps),
  normalisation_source = "aoi"
)
message(sprintf("  real stack: %d x %d x %d at %.3f deg",
                terra::nrow(stk), terra::ncol(stk), terra::nlyr(stk),
                terra::xres(stk)))

# ─────────────────────────────────────────────────────────────────────────────
# 5. Run 5-fold CV
# ─────────────────────────────────────────────────────────────────────────────
message("=== [4/7] Running 5-fold spatial CV ===")

fold_rows <- list()
posterior_bank <- list()
# Paired mixture-vs-Gaussian diagnostic for P7; see the block that fills it.
gauss_rows <- list()

for (fd in 1:5) {
  message(sprintf("  fold %d/5", fd))
  # SF$train already has the buffered rows removed; the complement would not.
  train_ix <- SF$train[[fd]]
  test_ix  <- SF$test[[fd]]
  train    <- profiles[train_ix, , drop = FALSE]
  test     <- profiles[test_ix,  , drop = FALSE]
  n_tr <- nrow(train); n_te <- nrow(test)
  message(sprintf("    train=%d, test=%d", n_tr, n_te))

  # P5 QRF
  t5 <- system.time({
    post5 <- tryCatch(fit_p5_qrf(train, test, cov_cols),
                        error = function(e) {
                          message("    [P5 warn] ", conditionMessage(e))
                          NULL
                        })
  })["elapsed"]
  # P4 Foundation
  t4 <- system.time({
    post4 <- tryCatch(fit_p4_foundation(train, test, cov_cols,
                                           moco, dataset_meta, stk),
                        error = function(e) {
                          message("    [P4 warn] ", conditionMessage(e))
                          NULL
                        })
  })["elapsed"]
  # P7 BHS used to train on a 300-row subsample while P4 and P5 saw the full
  # fold -- a comparison of budgets, not of methods.  The RcppArmadillo Gibbs
  # backend makes the full fold affordable, so the cap is gone; set
  # EDAPHOS_BENCH_P7_CAP to restore a subsample if the run is too slow.  The
  # size actually used still travels with every row.
  P7_TRAIN_CAP <- suppressWarnings(as.integer(Sys.getenv("EDAPHOS_BENCH_P7_CAP", "")))
  train_bhs <- if (!is.na(P7_TRAIN_CAP) && n_tr > P7_TRAIN_CAP)
                 train[sample(n_tr, P7_TRAIN_CAP), ] else train
  p7_n_train <- nrow(train_bhs)
  t7 <- system.time({
    post7 <- tryCatch(fit_p7_bhs(train_bhs, test, cov_cols,
                                    nmcmc = 300L, burn = 150L),
                        error = function(e) {
                          message("    [P7 warn] ", conditionMessage(e))
                          NULL
                        })
  })["elapsed"]

  # Evaluate each posterior
  truth <- test$soc
  eval_post <- function(post) {
    if (is.null(post)) return(NULL)
    tryCatch(uncertainty_calibrate(post, truth = truth),
              error = function(e) NULL)
  }
  c5 <- eval_post(post5); c4 <- eval_post(post4); c7 <- eval_post(post7)

  # WHAT THE GAUSSIAN SUBSTITUTION COST, measured rather than argued.
  #
  # Through v3.10.0 this benchmark scored P7 on rnorm(200, mean, sd) rebuilt
  # from the predictive summary instead of on the sampler's own draws. Simply
  # comparing this run's numbers against the committed ones cannot isolate
  # that: removing those rnorm() calls also shifts the RNG stream, so P4 and
  # P5 move too, and every delta becomes unattributable.
  #
  # The clean measurement is paired -- both distributions over the SAME
  # predictions, the same held-out truth, the same fold -- so the difference
  # is the substitution and nothing else. It is recorded in the bundle so the
  # claim about it is a number a reader can check.
  #
  # The draw of G runs on a private RNG stream: .Random.seed is saved and
  # restored around it, so adding this diagnostic does not perturb the run it
  # is diagnosing.
  gauss_gap <- NULL
  if (!is.null(post7) && !is.null(c7) && !is.null(post7$samples)) {
    S <- post7$samples
    old_seed <- if (exists(".Random.seed", .GlobalEnv))
      get(".Random.seed", .GlobalEnv) else NULL
    set.seed(4242L + fd)
    G <- vapply(seq_len(ncol(S)),
                function(j) stats::rnorm(nrow(S), mean(S[, j]), stats::sd(S[, j])),
                numeric(nrow(S)))
    if (!is.null(old_seed)) assign(".Random.seed", old_seed, .GlobalEnv)
    cg <- eval_post(edaphos_posterior(samples = G, method = "bayesian",
                                       query_type = "map", units = "g/kg"))
    # uncertainty_calibrate() returns picp/mpiw as NAMED VECTORS over nominal
    # levels, not as scalar `picp90` fields; reading them the wrong way yields
    # a zero-length value and data.frame() then fails with "differing number
    # of rows". Same extraction as grab() uses above.
    at90 <- function(v) if ("0.90" %in% names(v)) v[["0.90"]] else
                        if ("0.9"  %in% names(v)) v[["0.9"]]  else NA_real_
    if (!is.null(cg))
      gauss_gap <- data.frame(
        fold = fd,
        crps_mixture = c7$crps,             crps_gaussian = cg$crps,
        picp90_mixture = at90(c7$picp),     picp90_gaussian = at90(cg$picp),
        mpiw90_mixture = at90(c7$mpiw),     mpiw90_gaussian = at90(cg$mpiw),
        kurtosis_mixture = mean(apply(S, 2L, function(s)
          mean(((s - mean(s)) / stats::sd(s))^4))),
        stringsAsFactors = FALSE)
  }
  gauss_rows[[length(gauss_rows) + 1L]] <- gauss_gap

  grab <- function(name, post, cal, elapsed) {
    if (is.null(cal)) {
      # keep the column set identical to the success path, or bind_rows in
      # benchmark_wosis_6pilar.R backfills NA and the disclosure columns go
      # missing for whole methods
      return(data.frame(method = name, fold = fd, n_test = n_te,
                          n_train = if (grepl("^P7", name)) p7_n_train else n_tr,
                          train_capped = grepl("^P7", name) && p7_n_train < n_tr,
                          n_ensemble = NA_integer_,
                          rmse = NA, mae = NA, r2 = NA, nse = NA,
                          crps = NA, picp90 = NA, mpiw90 = NA,
                          elapsed_s = elapsed, stringsAsFactors = FALSE))
    }
    picp90 <- if ("0.90" %in% names(cal$picp)) cal$picp[["0.90"]] else
              if ("0.9"  %in% names(cal$picp)) cal$picp[["0.9"]]  else NA_real_
    mpiw90 <- if ("0.90" %in% names(cal$mpiw)) cal$mpiw[["0.90"]] else
              if ("0.9"  %in% names(cal$mpiw)) cal$mpiw[["0.9"]]  else NA_real_
    # Point predictions = posterior mean along axis 2
    point_pred <- if (!is.null(post$samples))
      colMeans(post$samples) else post$mean
    abs_err    <- abs(point_pred - truth)
    mae_val    <- mean(abs_err, na.rm = TRUE)
    rmse_val   <- sqrt(mean((point_pred - truth)^2, na.rm = TRUE))
    # Unclamped on purpose: a negative R2 means the model does worse than
    # predicting the mean, which is the informative result.  Clamping it at
    # zero used to report that as "explains none of the variance".
    r2_val     <- edaphos_r2(truth, point_pred)
    # Skill against the ACHIEVABLE null -- the mean of this fold's training
    # rows, which a deployed map knows. edaphos_r2() uses mean(truth), the
    # test fold's own mean, which is an oracle and a strictly harder bar; the
    # two were conflated and the manuscript reported the oracle result under
    # the achievable one's name.
    nse_val    <- edaphos_nse(truth, point_pred,
                              null_prediction = mean(train$soc, na.rm = TRUE))
    data.frame(
      method    = name, fold = fd, n_test = n_te,
      # training rows this method actually saw -- P7 was capped through
      # v3.10.0, P4/P5 never were
      n_train   = if (grepl("^P7", name)) p7_n_train else n_tr,
      train_capped = grepl("^P7", name) && p7_n_train < n_tr,
      # posterior draws behind the point prediction.  Read off the posterior
      # rather than hard-coded, so it cannot drift from what was actually
      # stored.  Without this column the 6-pillar table shows n_ensemble for
      # P1/P6/P10 and NA for P4/P5/P7, and the budget disparity the disclosure
      # exists to expose stays invisible for half the rows.
      n_ensemble = if (!is.null(post$samples)) nrow(post$samples) else NA_integer_,
      rmse      = rmse_val, mae = mae_val, r2 = r2_val, nse = nse_val,
      crps      = cal$crps,
      picp90    = picp90,
      mpiw90    = mpiw90,
      elapsed_s = elapsed,
      stringsAsFactors = FALSE
    )
  }
  fold_rows[[length(fold_rows) + 1L]] <- grab("P5 QRF",           post5, c5, t5)
  fold_rows[[length(fold_rows) + 1L]] <- grab("P4 Foundation embeddings + QRF", post4, c4, t4)
  fold_rows[[length(fold_rows) + 1L]] <- grab("P7 BHS",            post7, c7, t7)
  # Store POINT predictions, not the full posterior sample matrices.
  #
  # The matrices dominated this bundle -- 98.8 % of the six-pillar file that
  # merges it -- and nothing downstream reads them: the calibration metrics
  # (PICP, MPIW, CRPS) are computed here and stored in cv_fold_table, and the
  # pooled metrics need only a point prediction per row.  Keeping megabytes of
  # draws that no consumer opens is the largest avoidable item in the CRAN
  # install size.
  .point_of <- function(p) if (is.null(p)) NULL
                           else if (!is.null(p$samples)) colMeans(p$samples)
                           else as.numeric(p$mean)
  posterior_bank[[fd]] <- list(
    p5 = .point_of(post5), p4 = .point_of(post4), p7 = .point_of(post7),
    # achievable null for this fold
    train_mean = mean(train$soc, na.rm = TRUE),
    truth = truth)
}

cv_tbl <- bind_rows(fold_rows)

# The paired diagnostic, aggregated. Every column is a difference between two
# scorings of the SAME predictions, so it isolates the Gaussian substitution
# from everything else that moves between runs.
gauss_tbl <- if (length(Filter(Negate(is.null), gauss_rows)))
  bind_rows(Filter(Negate(is.null), gauss_rows)) else NULL
if (!is.null(gauss_tbl)) {
  message("=== P7: the sampler's draws vs the Gaussian that was published ===")
  print(as.data.frame(gauss_tbl), row.names = FALSE, digits = 4)
  cat(sprintf(
    "  mean over folds: CRPS %.4f (mixture) vs %.4f (Gaussian), delta %+.4f\n",
    mean(gauss_tbl$crps_mixture), mean(gauss_tbl$crps_gaussian),
    mean(gauss_tbl$crps_gaussian - gauss_tbl$crps_mixture)))
  cat(sprintf(
    "  PICP90 %.4f vs %.4f, delta %+.4f | mean kurtosis %.3f (3 = Gaussian)\n",
    mean(gauss_tbl$picp90_mixture), mean(gauss_tbl$picp90_gaussian),
    mean(gauss_tbl$picp90_gaussian - gauss_tbl$picp90_mixture),
    mean(gauss_tbl$kurtosis_mixture)))
}

message("=== [5/7] Fold-level table ===")
print(cv_tbl)

# ─────────────────────────────────────────────────────────────────────────────
# 6. Aggregate
# ─────────────────────────────────────────────────────────────────────────────
message("=== [6/7] Cross-fold aggregate ===")

agg <- cv_tbl |>
  group_by(method) |>
  summarise(
    n_folds     = dplyr::n(),
    rmse_mean   = mean(rmse,   na.rm = TRUE),
    rmse_sd     = stats::sd(rmse, na.rm = TRUE),
    r2_mean     = mean(r2,     na.rm = TRUE),
    # skill against the achievable (training-fold mean) null; r2_mean
    # above is against the oracle (test-fold mean) null
    nse_mean    = mean(nse,    na.rm = TRUE),
    nse_sd      = stats::sd(nse, na.rm = TRUE),
    picp90_mean = mean(picp90, na.rm = TRUE),
    mpiw90_mean = mean(mpiw90, na.rm = TRUE),
    crps_mean   = mean(crps,   na.rm = TRUE),
    elapsed_sum = sum(elapsed_s, na.rm = TRUE),
    .groups = "drop"
  )
print(agg)

# ─────────────────────────────────────────────────────────────────────────────
# 7. Save bundle
# ─────────────────────────────────────────────────────────────────────────────
message("=== [7/7] Saving bundle ===")
R_out <- list(
  # Binds this bundle to the script that made it: see R/provenance.R.
  provenance = edaphos_provenance(
                 script = "data-raw/benchmark_wosis_p4_p5_p7.R",
                 p7_posterior = "sampler draws (not a Gaussian refit)"),
  response_scale = RESPONSE_SCALE,
  response_units = RESPONSE_UNITS,
  profile_years  = YEAR_SUMMARY,
  version        = packageVersion("edaphos"),
  date_computed  = Sys.time(),
  n_profiles     = nrow(profiles),
  cov_cols       = cov_cols,
  folds          = folds,
  spatial_folds = SF,
  cv_fold_table  = cv_tbl,
  cv_aggregate   = agg,
  posterior_bank = posterior_bank,
  # What the pre-fix Gaussian substitution was worth, per fold.
  p7_gaussian_gap = gauss_tbl
)
saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
