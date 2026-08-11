#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_ptf_bulk_density.R
#
# A pedotransfer function for bulk density, and an honest account of its error.
#
# The manuscript owed one. Carbon STOCK is the quantity that is conserved and
# mapped; every Pillar-2 number is a concentration; and converting one to the
# other needs a density that WoSIS supplies for 3.9% of the Cerrado horizons
# this package ships. The paper's own sentence was that a stock validation at
# scale "would need a pedotransfer function we have not built".
#
# THE CALIBRATION SET is inst/extdata/soildata_uberaba_bd.rds -- 166 horizons
# over 83 profiles from SoilData's ctb0017, every one with MEASURED bulk
# density, carbon and particle size, and 144 of them Latossolos, the order the
# Cerrado is mostly made of.
#
# WHAT IS BEING BOUGHT AND WHAT IS BEING SPENT. A PTF turns 231 usable
# horizons into 5,853. It also inserts a model between the data and the
# answer, so the stock error it enables is the depth model's error CONVOLVED
# with the PTF's. This script therefore reports the PTF's own error first and
# at length; a stock number quoted without it would be the more confident and
# less correct kind this paper exists to argue against.
#
# VALIDATION IS SPATIALLY BLOCKED. The 83 profiles sit in one river basin, so
# a random split would put near-neighbours on both sides and report a skill
# that does not survive the move to the rest of the Cerrado. Blocked folds
# with a buffer are the same design the paper's cross-pillar benchmark uses.
#
# Output: inst/extdata/piml_ptf_bulk_density.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
set.seed(23L)

U <- readRDS("inst/extdata/soildata_uberaba_bd.rds")
H <- U$horizons
message(sprintf("calibration set: %d horizons, %d profiles",
                nrow(H), length(unique(H$profile_id))))

# --- candidate predictors ---------------------------------------------------
# Carbon is the classic and dominant term (organic matter is light and holds
# structure open); depth and texture are the usual companions. log-carbon
# because the relation is curved and carbon spans two orders of magnitude.
H$log_soc <- log1p(H$soc_g_kg)
PRED <- c("log_soc", "depth_mid", "clay", "sand")
H <- H[stats::complete.cases(H[, c("bd_g_cm3", PRED)]), ]
message(sprintf("  %d horizons with every predictor present", nrow(H)))

# --- spatially blocked folds over PROFILES ---------------------------------
# Blocking on profiles, not horizons: two horizons of one pedon are not two
# independent observations, and splitting them across folds would leak.
prof <- unique(H[, c("profile_id", "lon", "lat")])
SF <- spatial_block_folds(as.matrix(prof[, c("lon", "lat")]), k = 5L,
                          buffer_km = 5, seed = 23L)
message(sprintf("  %d spatially blocked folds over %d profiles; %d profiles buffered out",
                length(SF$test), nrow(prof), sum(SF$n_buffered)))

MODELS <- list(
  `constant (profile-set mean)` = function(tr, te) rep(mean(tr$bd_g_cm3), nrow(te)),
  `carbon only (log-linear)` = function(tr, te) {
    m <- stats::lm(bd_g_cm3 ~ log_soc, data = tr)
    as.numeric(stats::predict(m, te))
  },
  `carbon + depth + texture` = function(tr, te) {
    m <- stats::lm(stats::as.formula(paste("bd_g_cm3 ~", paste(PRED, collapse = " + "))),
                   data = tr)
    as.numeric(stats::predict(m, te))
  },
  `random forest` = function(tr, te) {
    m <- ranger::ranger(stats::as.formula(paste("bd_g_cm3 ~", paste(PRED, collapse = " + "))),
                        data = tr, num.trees = 500L, seed = 23L)
    as.numeric(stats::predict(m, data = te)$predictions)
  }
)

rows <- list()
for (fd in seq_along(SF$test)) {
  tr_p <- prof$profile_id[SF$train[[fd]]]
  te_p <- prof$profile_id[SF$test[[fd]]]
  tr <- H[H$profile_id %in% tr_p, ]
  te <- H[H$profile_id %in% te_p, ]
  if (nrow(tr) < 20L || nrow(te) < 3L) next
  for (nm in names(MODELS)) {
    p <- tryCatch(MODELS[[nm]](tr, te), error = function(e) NULL)
    if (is.null(p)) next
    rows[[length(rows) + 1L]] <- data.frame(
      fold = fd, model = nm, profile_id = te$profile_id,
      obs = te$bd_g_cm3, pred = p, depth = te$depth_mid,
      soc = te$soc_g_kg, stringsAsFactors = FALSE)
  }
}
R <- do.call(rbind, rows)

agg <- do.call(rbind, lapply(names(MODELS), function(nm) {
  x <- R[R$model == nm, ]
  if (!nrow(x)) return(NULL)
  # Skill against the training-fold mean, which is the achievable null -- the
  # same convention the paper's benchmark uses, and not the test-fold mean,
  # which no one can know in advance.
  data.frame(model = nm, n = nrow(x),
             RMSE = sqrt(mean((x$pred - x$obs)^2)),
             MAE  = mean(abs(x$pred - x$obs)),
             ME   = mean(x$pred - x$obs),
             rel_RMSE = sqrt(mean((x$pred - x$obs)^2)) / mean(x$obs),
             stringsAsFactors = FALSE)
}))
null_rmse <- agg$RMSE[agg$model == "constant (profile-set mean)"]
agg$skill_vs_constant <- 1 - (agg$RMSE / null_rmse)^2
agg <- agg[order(agg$RMSE), ]

cat("\n=== the PTF's own error, spatially blocked ===\n")
for (i in seq_len(nrow(agg)))
  cat(sprintf("  %-28s RMSE %.4f  MAE %.4f  ME %+.4f  rel %.1f%%  skill %+.3f\n",
              agg$model[i], agg$RMSE[i], agg$MAE[i], agg$ME[i],
              100 * agg$rel_RMSE[i], agg$skill_vs_constant[i]))

best <- agg$model[1]
cat(sprintf("\nbest: %s\n", best))
if (agg$skill_vs_constant[1] <= 0)
  cat("  NOTE: nothing beats a constant. On this basin a single mean density\n",
      "  is as good as any function of carbon and texture, and the stock\n",
      "  arithmetic below should say so.\n", sep = "")

# --- the fitted PTF, on everything -----------------------------------------
fit_full <- if (grepl("forest", best)) {
  ranger::ranger(stats::as.formula(paste("bd_g_cm3 ~", paste(PRED, collapse = " + "))),
                 data = H, num.trees = 500L, seed = 23L)
} else if (grepl("carbon only", best)) {
  stats::lm(bd_g_cm3 ~ log_soc, data = H)
} else if (grepl("constant", best)) {
  structure(list(mean = mean(H$bd_g_cm3)), class = "ptf_constant")
} else {
  stats::lm(stats::as.formula(paste("bd_g_cm3 ~", paste(PRED, collapse = " + "))),
            data = H)
}

# The predict wrapper the stock script will call.
#
# Built inside local() so its enclosing environment holds the fit. A closure
# defined at top level captures the script's global environment, which
# saveRDS() does not serialise -- the object round-trips and then fails with
# "object 'fit_full' not found" in the consumer, which is exactly what
# happened the first time.
ptf_predict <- local({
  .fit <- fit_full
  function(newdata) {
    nd <- newdata
    if (!"log_soc" %in% names(nd)) nd$log_soc <- log1p(nd$soc_g_kg)
    if (inherits(.fit, "ptf_constant")) return(rep(.fit$mean, nrow(nd)))
    if (inherits(.fit, "ranger"))
      return(as.numeric(stats::predict(.fit, data = nd)$predictions))
    as.numeric(stats::predict(.fit, nd))
  }
})
stopifnot(is.finite(ptf_predict(data.frame(soc_g_kg = c(1, 20), depth_mid = c(10, 100),
                                           clay = c(30, 30), sand = c(40, 40)))))

cat("\n=== where the PTF is being asked to work ===\n")
W <- readRDS("inst/extdata/piml_wosis_cerrado.rds")$horizons
cat(sprintf("calibration: carbon %.1f-%.1f g/kg, depth %g-%g cm, clay %.0f-%.0f%%\n",
            min(H$soc_g_kg), max(H$soc_g_kg), min(H$depth_mid), max(H$depth_mid),
            min(H$clay), max(H$clay)))
cat(sprintf("application: carbon %.1f-%.1f g/kg, depth %g-%g cm\n",
            min(W$soc_g_kg, na.rm = TRUE), max(W$soc_g_kg, na.rm = TRUE),
            min(W$depth_mid, na.rm = TRUE), max(W$depth_mid, na.rm = TRUE)))
out_c <- mean(W$soc_g_kg > max(H$soc_g_kg) | W$soc_g_kg < min(H$soc_g_kg), na.rm = TRUE)
out_d <- mean(W$depth_mid > max(H$depth_mid), na.rm = TRUE)
cat(sprintf("WoSIS horizons outside the calibrated carbon range: %.1f%%\n", 100 * out_c))
cat(sprintf("WoSIS horizons deeper than any calibration horizon: %.1f%%\n", 100 * out_d))

saveRDS(list(cv = R, aggregate = agg, best = best,
             blocked_rmse = agg$RMSE[1], blocked_rel_rmse = agg$rel_RMSE[1],
             fit = fit_full, predict = ptf_predict, predictors = PRED,
             calibration = list(n = nrow(H), n_profiles = length(unique(H$profile_id)),
                                soc = range(H$soc_g_kg), depth = range(H$depth_mid),
                                clay = range(H$clay), bd = range(H$bd_g_cm3)),
             extrapolation = list(frac_carbon_outside = out_c, frac_deeper = out_d),
             source = U$dataset, doi = U$doi,
             built_by = "data-raw/piml_ptf_bulk_density.R"),
        "inst/extdata/piml_ptf_bulk_density.rds")
message("\nwrote inst/extdata/piml_ptf_bulk_density.rds")
