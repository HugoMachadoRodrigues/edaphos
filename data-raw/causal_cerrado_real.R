# Pillar 1 on real data: backdoor-adjusted causal effects on 1095
# real WoSIS 0-10 cm topsoil profiles of the Cerrado.
#
# v1.4.0 is the "application-grade" answer to the v1.2 / v1.3 README
# claim that Pillar 1 does causal inference on pedometric data: here
# the dataset is REAL (not the bundled br_cerrado synthetic cube),
# the DAG encodes published Cerrado pedogenesis (elev -> climate ->
# land cover -> SOC plus texture / density), and the estimates
# contrast the naive OLS association against the identified direct
# effect for three exposures of practical interest.
#
# Output is a self-contained RDS that the `pilar1-causal` vignette
# consumes so the vignette builds on any installation.

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(dagitty)
})

# Bundle from v1.3.1 runner.
b <- readRDS("tools/case_cerrado/case_cerrado_bundle.rds")
profiles <- b$profiles
message(sprintf("[causal] %d profiles x %d columns",
                 nrow(profiles), ncol(profiles)))

dag <- causal_cerrado_real_dag()

# --- Three exposures of practical interest ---------------------------------
#
# (1) bio12 (mean annual precipitation, mm) -> SOC concentration.
#     Canonical climate control on SOC (Jenny 1941; Cerrado-specific
#     gradient documented by Bernoux et al. 2002).
# (2) wc_landcover_trees (fractional tree cover, %) -> SOC. Direct
#     test of the land-use -> SOC pathway that dominates Cerrado
#     topsoil (native savanna ~ 3-4x SOC of planted pasture;
#     Oliveira et al. 2017).
# (3) soilgrids_clay (% clay, 0-5 cm) -> SOC. Mineral-protection
#     mechanism (Parfitt, Theng, Whitton 1997).
exposures <- c("wc_bio_12", "wc_landcover_trees", "soilgrids_clay")
outcome   <- "soc_topsoil_gkg"

# --- Fit both LM and BART for every exposure -------------------------------

fit_rows <- list()
for (x in exposures) {
  message(sprintf("[causal] exposure %s", x))

  # Identify adjustment set from the DAG.
  adj <- causal_adjustment_set(dag, exposure = x, outcome = outcome,
                                 type = "minimal", effect = "direct")
  message(sprintf("  adjust = {%s}", paste(adj, collapse = ", ")))

  # Linear backdoor estimator.
  fit_lm <- causal_estimate_effect(profiles, dag,
                                     exposure = x, outcome = outcome,
                                     estimator = "lm", effect = "direct")
  message(sprintf("  LM naive = %+.4f   direct = %+.4f  [%.4f, %.4f]",
                   fit_lm$effect_naive, fit_lm$effect,
                   fit_lm$effect_ci[1L], fit_lm$effect_ci[2L]))

  # Nonlinear BART estimator (contrasts SOC at exposure mean +/- 0.5 IQR).
  fit_bart <- tryCatch(
    causal_estimate_effect(profiles, dag,
                             exposure = x, outcome = outcome,
                             estimator = "bart", effect = "direct"),
    error = function(e) {
      message("  BART failed: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(fit_bart)) {
    message(sprintf("  BART naive = %+.4f   direct = %+.4f  [%.4f, %.4f]",
                     fit_bart$effect_naive, fit_bart$effect,
                     fit_bart$effect_ci[1L], fit_bart$effect_ci[2L]))
  }

  fit_rows[[x]] <- list(
    exposure  = x,
    outcome   = outcome,
    adjustment = adj,
    lm   = fit_lm,
    bart = fit_bart
  )
}

# --- Bootstrap CI for every LM direct effect (the `confint(lm)`
# asymptotic interval ignores spatial clustering; block-bootstrap by
# k-means cluster is the honest alternative). ------------------------------

set.seed(2026L)
B <- 200L
bootstrap_effects <- function(df, dag, exposure, outcome, adj, B) {
  clusters <- df$kmeans_cluster
  out <- numeric(B)
  for (b in seq_len(B)) {
    resampled_clusters <- sample(unique(clusters), replace = TRUE)
    ix <- unlist(lapply(resampled_clusters,
                          function(k) which(clusters == k)))
    d <- df[ix, , drop = FALSE]
    terms <- unique(c(exposure, adj))
    form <- stats::reformulate(terms, response = outcome)
    fit <- stats::lm(form, data = d)
    out[b] <- unname(stats::coef(fit)[exposure])
  }
  out
}

for (x in names(fit_rows)) {
  boot <- bootstrap_effects(profiles, dag, x, outcome,
                              fit_rows[[x]]$adjustment, B)
  fit_rows[[x]]$lm$effect_boot    <- boot
  fit_rows[[x]]$lm$effect_boot_ci <- stats::quantile(boot,
                                                       probs = c(0.025, 0.975))
  message(sprintf(
    "[causal] %s bootstrap-CI (block-by-cluster, B=%d): [%+.4f, %+.4f]",
    x, B, fit_rows[[x]]$lm$effect_boot_ci[1L],
    fit_rows[[x]]$lm$effect_boot_ci[2L]
  ))
}

# --- Persist ----------------------------------------------------------------

# Strip the fitted models (the BART posterior sample matrix is ~20 MB
# per exposure); keep the scalar effect summaries so the vignette can
# build without carrying the full posterior.
.slim_fit <- function(f) {
  list(
    exposure        = f$exposure,
    outcome         = f$outcome,
    adjustment      = f$adjustment,
    estimator       = f$estimator,
    effect          = f$effect,
    effect_ci       = f$effect_ci,
    effect_naive    = f$effect_naive,
    effect_boot     = f$effect_boot,
    effect_boot_ci  = f$effect_boot_ci
  )
}
effects_slim <- lapply(fit_rows, function(row) {
  list(
    exposure   = row$exposure,
    outcome    = row$outcome,
    adjustment = row$adjustment,
    lm         = .slim_fit(row$lm),
    bart       = if (!is.null(row$bart)) .slim_fit(row$bart) else NULL
  )
})

out_path <- "inst/extdata/causal_cerrado_real.rds"
saveRDS(
  list(
    profiles      = profiles[, c("profile_id", "dataset_id", "year",
                                    "lon", "lat",
                                    c(exposures, outcome),
                                    "wc_bio_01", "slope", "elev",
                                    "soilgrids_bdod", "soilgrids_sand",
                                    "wc_landcover_grassland",
                                    "wc_landcover_cropland"), drop = FALSE],
    dag           = dag,
    exposures     = exposures,
    outcome       = outcome,
    effects       = effects_slim,
    sources       = b$sources,
    created_at    = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    edaphos_ver   = as.character(packageVersion("edaphos"))
  ),
  out_path
)
message(sprintf("[causal] wrote %s (%.1f KB)",
                 out_path, file.info(out_path)$size / 1024))
