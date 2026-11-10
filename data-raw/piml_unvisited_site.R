#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_unvisited_site.R
#
# How much can ANY model know about the depth profile at a site nobody dug?
#
# The manuscript shows that the two-stage workflow (fit the pedogenetic
# equation per profile, then krige its parameters) fails on these data: one of
# four parameters has an identified variogram range, and covariates explain
# 2-9% of the parameters' variance. It names a one-stage hierarchical model --
# parameters regressed on covariates plus a shared spatial random effect -- as
# the remedy. Before building that model, this script measures the ceiling it
# would be working under. A hierarchical model can borrow from two sources
# only: covariates, and neighbours. Each is tested here directly, at the
# prediction task the hierarchical model exists for.
#
# PRE-DECLARED, before the first run.
#
# Task. For every profile in a held-out spatial block, predict every one of
#   its measured horizons, using no measurement at that site. Five spatially
#   blocked folds with the 68 km buffer of the benchmark
#   (spatial_block_folds(k = 5, buffer_km = 68)).
#
# Methods. All predict the four identified log-coordinates of the equation
#   (log kappa, log mu, log y(Inf), log y0) and evaluate the closed-form
#   solution as a horizon average, exactly as the per-profile fit does.
#     population  the mean of the training profiles' coordinates: one curve
#     covariates  per-coordinate linear regression on mean annual
#                 precipitation and temperature, elevation, slope, clay, sand
#     nearest     the coordinates of the nearest training profile
#     knn10       the mean coordinates of the 10 nearest training profiles
#     cov+knn     covariates, plus the mean residual of the 10 nearest
#                 training profiles -- regression-kriging in spirit, and the
#                 most a covariate model with a spatial effect could borrow
#   and, as a reference that is NOT a competitor, the profile's own fit
#   (in-sample: what the site's own horizons buy).
#
# Score. Per held-out profile, the mean absolute error over its horizons of
#   log(SOC) (relative error, matching the lognormal observation model); also
#   reported in g/kg. Each method is compared with `population` by a paired
#   Wilcoxon test over profiles.
#
# Decision rule. If no method beats `population` at p < 0.05 on the primary
#   score, then neither covariates nor neighbours carry information about the
#   profile shape at an unvisited site on these data, and a one-stage
#   hierarchical model has nothing to borrow from: it would shrink to the
#   population curve. If one does, the size of its gain is the ceiling.
#
# Input:  record cache (piml_wosis_cerrado, causal_cerrado_real_v2)
# Output: inst/extdata/piml_unvisited_site.rds        (aggregates only)
#         data-raw/build/records/piml_unvisited_site_rows.rds (per profile)
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
source("data-raw/records.R")  # record-level inputs, not shipped
set.seed(20261110L)

K_NN   <- 10L
COORDS <- c("log_kappa", "log_mu", "log_A", "log_y0")
COVS   <- c("map", "mat", "elev", "slope", "clay", "sand")
FLOOR  <- 0.1   # g/kg, below the reporting resolution of the archive

D <- read_records("piml_wosis_cerrado")
H <- D$horizons
H <- H[is.finite(H$soc_g_kg) & is.finite(H$top) & is.finite(H$bottom), ]
H$soc_g_kg <- pmax(H$soc_g_kg, FLOOR)
profs <- split(H, H$profile_id)
profs <- lapply(profs, function(s) s[order(s$top), ])
message(sprintf("%d profiles, %d horizons", length(profs), nrow(H)))

# -- 1. the equation at every profile, in its identified coordinates ---------
message("fitting the equation at every profile ...")
FP <- do.call(rbind, lapply(profs, function(s) {
  f <- tryCatch(piml_profile_fit(s$depth_mid, s$soc_g_kg,
                                 top = s$top, bottom = s$bottom),
                error = function(e) NULL)
  p <- if (is.null(f)) NULL else f$params
  data.frame(profile_id = s$profile_id[1], x = s$x[1], y = s$y[1],
             log_kappa = if (is.null(p)) NA else log(p$kappa),
             log_mu    = if (is.null(p)) NA else log(p$mu),
             log_A     = if (is.null(p)) NA else log(p$y_asym),
             log_y0    = if (is.null(p)) NA else log(p$y0),
             stringsAsFactors = FALSE)
}))
FP$fit_ok <- apply(is.finite(as.matrix(FP[, COORDS])), 1, all)
message(sprintf("  %d of %d fitted with finite coordinates",
                sum(FP$fit_ok), nrow(FP)))

# -- 2. covariates: the nearest causal-extract profile, as the variograms do -
CAU <- read_records("causal_cerrado_real_v2")$profiles
dmat <- .gc_km(cbind(FP$x, FP$y), cbind(CAU$lon, CAU$lat))
j <- apply(dmat, 1L, which.min)
FP$cov_match_km <- dmat[cbind(seq_len(nrow(FP)), j)]
FP <- cbind(FP, CAU[j, COVS])
FP$cov_ok <- stats::complete.cases(FP[, COVS])
message(sprintf("  covariate match distance: median %.2f km, 95th pct %.1f km",
                stats::median(FP$cov_match_km),
                stats::quantile(FP$cov_match_km, 0.95)))

# -- 3. folds ---------------------------------------------------------------
SF <- spatial_block_folds(cbind(FP$x, FP$y), k = 5L, buffer_km = 68,
                          seed = 20261110L)

predict_profile <- function(theta, s) {
  # every theta is built in COORDS order, which is .piml_unpack()'s order
  stopifnot(length(theta) == 4L)
  pr <- .piml_unpack(as.numeric(theta))
  .piml_layer_mean(s$top, s$bottom, pr)
}
score <- function(hat, s) {
  hat <- pmax(hat, FLOOR)
  c(mae_log = mean(abs(log(hat) - log(s$soc_g_kg))),
    mae_gkg = mean(abs(hat - s$soc_g_kg)))
}

rows <- list()
for (fd in seq_along(SF$test)) {
  tr <- FP[SF$train[[fd]], ]; tr <- tr[tr$fit_ok & tr$cov_ok, ]
  te <- FP[SF$test[[fd]], ];  te <- te[te$cov_ok, ]
  message(sprintf("fold %d: %d training profiles, %d held out",
                  fd, nrow(tr), nrow(te)))
  pop <- colMeans(tr[, COORDS])
  fml <- lapply(COORDS, function(v)
    stats::lm(stats::reformulate(COVS, v), data = tr))
  names(fml) <- COORDS
  res_tr <- sapply(COORDS, function(v) stats::residuals(fml[[v]]))
  dtt <- .gc_km(cbind(te$x, te$y), cbind(tr$x, tr$y))
  for (i in seq_len(nrow(te))) {
    s  <- profs[[te$profile_id[i]]]
    nn <- order(dtt[i, ])[seq_len(K_NN)]
    cv <- sapply(COORDS, function(v)
      stats::predict(fml[[v]], newdata = te[i, COVS, drop = FALSE]))
    th <- list(
      population = pop,
      covariates = cv,
      nearest    = unlist(tr[nn[1], COORDS]),
      knn10      = colMeans(tr[nn, COORDS]),
      `cov+knn`  = cv + colMeans(res_tr[nn, , drop = FALSE]))
    if (te$fit_ok[i]) th$own_fit <- unlist(te[i, COORDS])
    for (m in names(th)) {
      sc <- score(predict_profile(th[[m]], s), s)
      rows[[length(rows) + 1L]] <- data.frame(
        fold = fd, profile_id = te$profile_id[i], method = m,
        n_hor = nrow(s), d_nearest_km = dtt[i, nn[1]],
        mae_log = sc[["mae_log"]], mae_gkg = sc[["mae_gkg"]],
        stringsAsFactors = FALSE)
    }
  }
}
R <- do.call(rbind, rows)

# -- 4. aggregate ------------------------------------------------------------
METHODS <- c("population", "covariates", "nearest", "knn10", "cov+knn")
# compare on profiles every method scored
W <- stats::reshape(R[R$method %in% METHODS, c("profile_id", "method", "mae_log", "mae_gkg")],
                    idvar = "profile_id", timevar = "method", direction = "wide")
W <- W[stats::complete.cases(W), ]

tab <- do.call(rbind, lapply(METHODS, function(m) {
  dl <- W[[paste0("mae_log.", m)]] - W[["mae_log.population"]]
  dg <- W[[paste0("mae_gkg.", m)]] - W[["mae_gkg.population"]]
  wl <- if (m == "population") NA_real_ else
    suppressWarnings(stats::wilcox.test(W[[paste0("mae_log.", m)]],
                                        W[["mae_log.population"]], paired = TRUE)$p.value)
  data.frame(method = m, n = nrow(W),
             mae_log = mean(W[[paste0("mae_log.", m)]]),
             mae_log_median = stats::median(W[[paste0("mae_log.", m)]]),
             mae_gkg = mean(W[[paste0("mae_gkg.", m)]]),
             diff_vs_population_log = mean(dl),
             wins_vs_population = if (m == "population") NA_integer_ else sum(dl < 0),
             p_vs_population = wl,
             stringsAsFactors = FALSE)
}))
own <- R[R$method == "own_fit" & R$profile_id %in% W$profile_id, ]
reference <- data.frame(method = "own fit (in-sample reference)", n = nrow(own),
                        mae_log = mean(own$mae_log),
                        mae_log_median = stats::median(own$mae_log),
                        mae_gkg = mean(own$mae_gkg))

cat("\n=== predicting every horizon of a profile at an unvisited site ===\n")
print(tab, row.names = FALSE, digits = 3)
cat("\nreference, not a competitor:\n"); print(reference, row.names = FALSE, digits = 3)

beats <- tab$method[!is.na(tab$p_vs_population) & tab$p_vs_population < 0.05 &
                    tab$diff_vs_population_log < 0]
verdict <- if (!length(beats))
  "no method beats the population curve: nothing for a hierarchical model to borrow" else
  paste("beats the population curve:", paste(beats, collapse = ", "))
cat("\nverdict:", verdict, "\n")

cov_r2 <- vapply(COORDS, function(v) summary(stats::lm(stats::reformulate(COVS, v),
  data = FP[FP$fit_ok & FP$cov_ok, ]))$r.squared, numeric(1))

saveRDS(list(rows = R, coords = FP), records_path("piml_unvisited_site_rows"))
saveRDS(list(
  provenance = edaphos_provenance(),
  table = tab, reference = reference, verdict = verdict, beats = beats,
  n_profiles = length(profs), n_fitted = sum(FP$fit_ok),
  n_scored = nrow(W), k_nn = K_NN, covariates = COVS, buffer_km = SF$buffer_km,
  fold_sizes = vapply(SF$test, length, 0L),
  cov_r2 = cov_r2,
  cov_match_km = stats::quantile(FP$cov_match_km, c(0.5, 0.95)),
  d_nearest_km = stats::quantile(R$d_nearest_km[R$method == "population"],
                                 c(0, 0.5, 1)),
  built_by = "data-raw/piml_unvisited_site.R"),
  "inst/extdata/piml_unvisited_site.rds", version = 3, compress = "xz")
message("wrote inst/extdata/piml_unvisited_site.rds")
