## data-raw/causal_sensitivity_run.R  (v1.9.2)
##
## Applies the Cinelli & Hazlett (2020) sensitivity framework to the
## full Cerrado causal chain: Naive OLS, Backdoor OLS, Proxy IV
## (v1.9.0), and Real-MoCo IV (v1.9.1).  Reports the robustness
## value (RV) and RV_alpha for each estimator and exposure, and
## produces a bias-contour grid for a representative case.
##
## Output: inst/extdata/causal_sensitivity_cerrado.rds

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages({
  library(dplyr)
})
set.seed(20260425L)

OUT_PATH <- file.path("inst", "extdata", "causal_sensitivity_cerrado.rds")

# ─────────────────────────────────────────────────────────────────────────────
# 1. Load the WoSIS profiles and refit every estimator
# ─────────────────────────────────────────────────────────────────────────────
message("=== [1/4] Loading data + refitting estimators ===")

causal_rds <- readRDS("inst/extdata/causal_cerrado_real.rds")
profiles <- causal_rds$profiles |>
  filter(!is.na(soc_topsoil_gkg)) |>
  mutate(
    soc = soc_topsoil_gkg, map = wc_bio_12, mat = wc_bio_01 / 10,
    trees = wc_landcover_trees, cropland = wc_landcover_cropland,
    grass = wc_landcover_grassland,
    clay  = soilgrids_clay, sand = soilgrids_sand,
    bd    = soilgrids_bdod
  )

exposures <- list(
  list(col = "map",   label = "MAP (mm/a)"),
  list(col = "trees", label = "Tree cover (%)"),
  list(col = "clay",  label = "Clay (%)")
)

iv_proxy_bundle <- readRDS("inst/extdata/causal_iv_cerrado.rds")
iv_real_bundle  <- tryCatch(
  readRDS("inst/extdata/causal_iv_cerrado_real.rds"),
  error = function(e) NULL
)

# Per-exposure table of (estimator, effect, se, df)
rows <- list()

for (ex in exposures) {
  ec <- ex$col
  ecov <- setdiff(c("mat", "slope", "elev", "sand", "bd", "trees",
                     "cropland", "grass", "map", "clay"), ec)

  # Naive OLS
  f_naive <- stats::lm(stats::as.formula(sprintf("soc ~ %s", ec)),
                         data = profiles)
  co <- summary(f_naive)$coefficients[ec, ]
  rows[[paste0(ec, "_naive")]] <- data.frame(
    exposure = ex$label, estimator = "Naive OLS",
    effect = unname(co["Estimate"]),
    se     = unname(co["Std. Error"]),
    df     = stats::df.residual(f_naive),
    stringsAsFactors = FALSE
  )

  # Backdoor OLS
  f_bd <- stats::lm(
    stats::as.formula(sprintf("soc ~ %s + %s", ec,
                                paste(ecov, collapse = " + "))),
    data = profiles
  )
  co_bd <- summary(f_bd)$coefficients[ec, ]
  rows[[paste0(ec, "_bd")]] <- data.frame(
    exposure = ex$label, estimator = "Backdoor OLS",
    effect = unname(co_bd["Estimate"]),
    se     = unname(co_bd["Std. Error"]),
    df     = stats::df.residual(f_bd),
    stringsAsFactors = FALSE
  )

  # Proxy IV (v1.9.0)
  px <- iv_proxy_bundle$benchmark_table |>
    dplyr::filter(exposure == ex$label,
                    estimator == "2SLS (proxy embeddings)")
  if (nrow(px) > 0L) {
    rows[[paste0(ec, "_iv_proxy")]] <- data.frame(
      exposure = ex$label, estimator = "Proxy IV (v1.9.0)",
      effect = px$beta, se = px$se,
      df     = px$n - (1L + length(ecov) + 1L),
      stringsAsFactors = FALSE
    )
  }

  # Real MoCo IV (v1.9.1)
  if (!is.null(iv_real_bundle)) {
    rx <- iv_real_bundle$benchmark_table |>
      dplyr::filter(exposure == ex$label,
                      estimator == "2SLS (real MoCo v1)")
    if (nrow(rx) > 0L) {
      rows[[paste0(ec, "_iv_real")]] <- data.frame(
        exposure = ex$label, estimator = "Real MoCo IV (v1.9.1)",
        effect = rx$beta, se = rx$se,
        df     = iv_real_bundle$n_profiles_extracted -
                   (1L + length(ecov) + 1L),
        stringsAsFactors = FALSE
      )
    }
  }
}
tbl <- bind_rows(rows)
print(tbl)

# ─────────────────────────────────────────────────────────────────────────────
# 2. Cinelli-Hazlett sensitivity per row
# ─────────────────────────────────────────────────────────────────────────────
message("=== [2/4] Computing RV and RV_alpha per estimator ===")

sens_rows <- lapply(seq_len(nrow(tbl)), function(i) {
  r <- tbl[i, ]
  s <- causal_sensitivity_summary(r$effect, r$se, r$df,
                                     q = 1, alpha = 0.05)
  data.frame(
    exposure  = r$exposure, estimator = r$estimator,
    effect    = r$effect, se = r$se, df = r$df,
    t_stat    = s$t_stat,
    rv        = s$rv,
    rv_alpha  = s$rv_alpha,
    stringsAsFactors = FALSE
  )
})
sens_tbl <- bind_rows(sens_rows)
print(sens_tbl)

# ─────────────────────────────────────────────────────────────────────────────
# 3. Bias-contour grid for the Backdoor MAP -> SOC (headline case)
# ─────────────────────────────────────────────────────────────────────────────
message("=== [3/4] Building bias-contour grid ===")

headline <- tbl |>
  dplyr::filter(exposure == "MAP (mm/a)",
                  estimator == "Backdoor OLS") |>
  dplyr::slice(1)
grid_bd <- causal_sensitivity_grid(
  effect = headline$effect, se = headline$se, df = headline$df,
  grid_size = 61L, r2_max = 0.30
)
headline_proxy <- tbl |>
  dplyr::filter(exposure == "MAP (mm/a)",
                  estimator == "Proxy IV (v1.9.0)") |>
  dplyr::slice(1)
grid_proxy <- if (nrow(headline_proxy) > 0L) {
  causal_sensitivity_grid(
    effect = headline_proxy$effect, se = headline_proxy$se,
    df = headline_proxy$df, grid_size = 61L, r2_max = 0.30
  )
} else NULL

headline_real <- tbl |>
  dplyr::filter(exposure == "MAP (mm/a)",
                  estimator == "Real MoCo IV (v1.9.1)") |>
  dplyr::slice(1)
grid_real <- if (nrow(headline_real) > 0L) {
  causal_sensitivity_grid(
    effect = headline_real$effect, se = headline_real$se,
    df = headline_real$df, grid_size = 61L, r2_max = 0.30
  )
} else NULL

message(sprintf("  Headline backdoor: effect = %.4f, RV = %.3f",
                headline$effect,
                .subset2(sens_tbl,  "rv")[
                  sens_tbl$exposure == headline$exposure &
                  sens_tbl$estimator == headline$estimator]))

# ─────────────────────────────────────────────────────────────────────────────
# 4. Save bundle
# ─────────────────────────────────────────────────────────────────────────────
message("=== [4/4] Saving bundle ===")

R_out <- list(
  version          = packageVersion("edaphos"),
  date_computed    = Sys.time(),
  fit_table        = tbl,
  sensitivity_table = sens_tbl,
  grid_backdoor    = grid_bd,
  grid_proxy_iv    = grid_proxy,
  grid_real_iv     = grid_real,
  headline_backdoor = headline,
  headline_proxy    = headline_proxy,
  headline_real     = headline_real
)
saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
