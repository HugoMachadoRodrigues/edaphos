## data-raw/causal_iv_benchmark.R (v1.9.0)
##
## Benchmarks the new 2SLS IV estimator on the 1 095 real WoSIS
## Cerrado profiles, using both a **synthetic-DGP sanity check** and
## two production setups:
##
##   (A) Proxy-embedding IV: construct an engineered feature matrix
##       that plausibly approximates what a foundation-model encoder
##       would learn (interactions, ratios, nonlinear transforms,
##       spatial basis), reduce to top-5 principal components, use
##       those as instruments.  This is the PROVISIONAL analysis while
##       the MoCo v2 encoder (Zenodo, in training) is finalised.
##
##   (B) When EDAPHOS_USE_MOCO_V2=1 and the encoder is locally
##       cached, the script replaces the engineered features with
##       real MoCo v2 embeddings extracted at each WoSIS profile
##       location (requires SoilGrids/WorldClim/SRTM raster stacks
##       and the encoder weights).  Otherwise falls back to (A).
##
## The comparison table answers the central v1.9.0 question: do
## foundation-style embeddings carry signal about unobserved
## confounders that changes the causal effect recovered by the
## backdoor estimator of v1.4.0?  Output:
##   inst/extdata/causal_iv_cerrado.rds

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))
set.seed(20260425L)

OUT_PATH <- file.path("inst", "extdata", "causal_iv_cerrado.rds")
USE_MOCO <- identical(Sys.getenv("EDAPHOS_USE_MOCO_V2", ""), "1")

# ─────────────────────────────────────────────────────────────────────────────
# 0. Synthetic DGP sanity check (recovers true beta under known IV setup)
# ─────────────────────────────────────────────────────────────────────────────
message("=== [0/6] Synthetic DGP sanity check ===")

set.seed(42L)
n_syn <- 800L
Z_syn <- matrix(stats::rnorm(n_syn * 3L), ncol = 3L,
                 dimnames = list(NULL, c("Z1", "Z2", "Z3")))
U_syn <- stats::rnorm(n_syn)                             # unobserved
X_syn <- 0.7*Z_syn[,1] + 0.5*Z_syn[,2] + 0.4*Z_syn[,3] +
          0.6*U_syn + stats::rnorm(n_syn, sd = 0.5)
beta_true <- 1.5
Y_syn <- beta_true * X_syn + 0.8*U_syn + stats::rnorm(n_syn, sd = 0.5)
df_syn <- data.frame(Y = Y_syn, X = X_syn,
                      Z1 = Z_syn[,1], Z2 = Z_syn[,2], Z3 = Z_syn[,3])

ols_syn <- stats::lm(Y ~ X, data = df_syn)
iv_syn  <- causal_iv_fit_2sls(df_syn, "X", "Y", c("Z1", "Z2", "Z3"))
syn_post <- causal_iv_posterior(df_syn, "X", "Y",
                                  c("Z1", "Z2", "Z3"),
                                  B = 300L, seed = 1L,
                                  units = "y per x")

syn_summary <- data.frame(
  estimator = c("OLS (biased by U)", "2SLS with Z1,Z2,Z3", "True (DGP)"),
  beta      = c(unname(stats::coef(ols_syn)[2]), iv_syn$effect, beta_true),
  se        = c(sqrt(stats::vcov(ols_syn)[2,2]), iv_syn$se, NA_real_),
  ci_lo     = c(stats::confint(ols_syn)[2,1], iv_syn$ci_lo, NA_real_),
  ci_hi     = c(stats::confint(ols_syn)[2,2], iv_syn$ci_hi, NA_real_),
  stringsAsFactors = FALSE
)
print(syn_summary)
message(sprintf("  stage-1 F = %.1f,  Sargan p = %.3f",
                iv_syn$stage1_F, iv_syn$sargan_p))

# ─────────────────────────────────────────────────────────────────────────────
# 1. Load Cerrado WoSIS profiles
# ─────────────────────────────────────────────────────────────────────────────
message("=== [1/6] Loading Cerrado WoSIS profiles ===")
causal_rds <- readRDS("inst/extdata/causal_cerrado_real.rds")
profiles <- causal_rds$profiles |>
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
  ) |>
  filter(!is.na(soc), !is.na(map), !is.na(mat), !is.na(clay))

profiles$kmeans_cluster <- stats::kmeans(
  profiles[, c("lon", "lat")], centers = 8L, nstart = 5L
)$cluster

message(sprintf("  n = %d profiles (after dropping NAs)", nrow(profiles)))

# ─────────────────────────────────────────────────────────────────────────────
# 2. Build proxy "foundation-like" embeddings from engineered features
# ─────────────────────────────────────────────────────────────────────────────
message("=== [2/6] Building proxy embeddings ===")

# Design note: a MoCo v2 encoder on 16x16 raster patches would learn
# a low-dim representation that captures interactions and nonlinear
# transforms of climate + topography + soil + land-cover. We
# approximate that with an engineered feature matrix of 27 columns;
# PCA to top-5 gives the 5 "instrument" dimensions. The PCs are
# orthogonal to each other AND to the OLS residuals of the
# backdoor-adjusted model only if the engineered features capture
# signal that the named covariates don't -- that's the empirical
# question this benchmark answers.

mk_proxy <- function(df) {
  cbind(
    # Squared + log terms
    map2       = df$map^2,
    mat2       = df$mat^2,
    log_map    = log(pmax(df$map, 1)),
    log_elev   = log(pmax(df$elev, 1)),
    sqrt_slope = sqrt(pmax(df$slope, 0)),
    # Ratios
    tc_cr      = df$trees / (df$cropland + 1),
    tc_gr      = df$trees / (df$grass + 1),
    sand_clay  = df$sand / (df$clay + 1),
    # Interactions
    map_tree   = df$map * df$trees / 100,
    map_slope  = df$map * pmax(df$slope, 0),
    mat_elev   = df$mat * df$elev / 1000,
    clay_map   = df$clay * df$map / 1000,
    sand_elev  = df$sand * df$elev / 1000,
    # Spatial basis (centred)
    lon_c      = df$lon - mean(df$lon, na.rm = TRUE),
    lat_c      = df$lat - mean(df$lat, na.rm = TRUE),
    lon2       = (df$lon - mean(df$lon, na.rm = TRUE))^2,
    lat2       = (df$lat - mean(df$lat, na.rm = TRUE))^2,
    lonlat     = (df$lon - mean(df$lon, na.rm = TRUE)) *
                  (df$lat - mean(df$lat, na.rm = TRUE)),
    # Composite landscape indices
    dryness    = df$mat / pmax(df$map / 100, 0.1),
    woody      = df$trees / (df$trees + df$grass + df$cropland + 1),
    cult_press = df$cropland / (df$cropland + df$grass + df$trees + 1),
    texture    = (df$clay - df$sand) / (df$clay + df$sand + 1),
    bd_clay    = df$bd / (df$clay + 1),
    # Quantile bins (as ordered factors via rank)
    rank_map   = rank(df$map)   / nrow(df),
    rank_mat   = rank(df$mat)   / nrow(df),
    rank_trees = rank(df$trees) / nrow(df),
    rank_clay  = rank(df$clay)  / nrow(df)
  )
}

emb_proxy <- mk_proxy(profiles)
message(sprintf("  embedding matrix: %d x %d",
                nrow(emb_proxy), ncol(emb_proxy)))

# Store description for the vignette
proxy_features <- colnames(emb_proxy)

# ─────────────────────────────────────────────────────────────────────────────
# 2b. OPTIONAL: load MoCo v2 real embeddings if available
# ─────────────────────────────────────────────────────────────────────────────
moco_embeddings <- NULL
if (USE_MOCO) {
  message("  [EDAPHOS_USE_MOCO_V2=1] Attempting to load MoCo v2 ...")
  moco_embeddings <- tryCatch({
    moco <- foundation_weights_load("edaphos-cerrado-moco-v1",
                                      verbose = FALSE)
    # Extract embedding at each profile location — would require
    # raster stacks; deferred to v1.9.1 when the v2 encoder is published.
    stop("MoCo v2 patch extraction not yet implemented; see v1.9.1 roadmap.")
  }, error = function(e) {
    message(sprintf("  [warn] MoCo fallback: %s", conditionMessage(e)))
    NULL
  })
}
if (is.null(moco_embeddings)) {
  message("  Using PROXY embeddings (engineered features + PCA).")
} else {
  message("  Using MoCo v2 REAL embeddings.")
}

emb_used <- if (!is.null(moco_embeddings)) moco_embeddings else emb_proxy

# ─────────────────────────────────────────────────────────────────────────────
# 3. Per-exposure benchmark: OLS vs backdoor vs 2SLS(IV)
# ─────────────────────────────────────────────────────────────────────────────
message("=== [3/6] Per-exposure benchmarks ===")

exposures <- list(
  list(col = "map",   label = "MAP (mm/a)",     units = "g/kg per mm"),
  list(col = "trees", label = "Tree cover (%)", units = "g/kg per %"),
  list(col = "clay",  label = "Clay (%)",       units = "g/kg per %")
)

benchmark_rows <- list()
fit_list <- list()
posterior_list <- list()

for (ex in exposures) {
  ec   <- ex$col
  ecov <- setdiff(c("mat", "slope", "elev", "sand", "bd", "trees",
                     "cropland", "grass", "map", "clay"),
                   ec)   # all the other covariates become exogenous controls
  message(sprintf("  [%s -> soc]", ec))

  # (a) Naive OLS
  fml_ols <- stats::as.formula(sprintf("soc ~ %s", ec))
  ols <- stats::lm(fml_ols, data = profiles)
  benchmark_rows[[paste0(ec, "_ols")]] <- data.frame(
    exposure  = ex$label,
    estimator = "OLS (naive)",
    beta      = unname(stats::coef(ols)[2]),
    se        = sqrt(stats::vcov(ols)[2, 2]),
    ci_lo     = stats::confint(ols)[2, 1],
    ci_hi     = stats::confint(ols)[2, 2],
    stage1_F  = NA_real_, sargan_p = NA_real_, n = length(stats::resid(ols)),
    stringsAsFactors = FALSE
  )

  # (b) Backdoor adjustment (all observed exogenous controls)
  fml_bd <- stats::as.formula(sprintf("soc ~ %s + %s", ec,
                                        paste(ecov, collapse = " + ")))
  bd <- stats::lm(fml_bd, data = profiles)
  benchmark_rows[[paste0(ec, "_bd")]] <- data.frame(
    exposure  = ex$label,
    estimator = "Backdoor OLS (adjusted)",
    beta      = unname(stats::coef(bd)[ec]),
    se        = sqrt(stats::vcov(bd)[ec, ec]),
    ci_lo     = stats::confint(bd)[ec, 1],
    ci_hi     = stats::confint(bd)[ec, 2],
    stage1_F  = NA_real_, sargan_p = NA_real_, n = length(stats::resid(bd)),
    stringsAsFactors = FALSE
  )

  # (c) 2SLS with top-5 PCs of proxy embeddings as instruments
  iv_fit <- tryCatch(
    causal_iv_from_embeddings(
      data       = profiles,
      embeddings = emb_used,
      exposure   = ec,
      outcome    = "soc",
      covariates = ecov,
      n_pcs      = 5L
    ),
    error = function(e) { message("    [warn] ", conditionMessage(e)); NULL }
  )
  if (!is.null(iv_fit)) {
    benchmark_rows[[paste0(ec, "_iv")]] <- data.frame(
      exposure  = ex$label,
      estimator = "2SLS (proxy embeddings)",
      beta      = iv_fit$effect,
      se        = iv_fit$se,
      ci_lo     = iv_fit$ci_lo,
      ci_hi     = iv_fit$ci_hi,
      stage1_F  = iv_fit$stage1_F,
      sargan_p  = iv_fit$sargan_p,
      n         = iv_fit$n,
      stringsAsFactors = FALSE
    )
    fit_list[[ec]] <- iv_fit

    # Bootstrap posterior for uncertainty API parity
    # Attach PCs to the profiles so bootstrapping sees them
    pr <- stats::prcomp(emb_used[, apply(emb_used, 2, stats::var,
                                           na.rm = TRUE) > 1e-12,
                                   drop = FALSE],
                          center = TRUE, scale. = TRUE, rank. = 5L)
    pc_df <- as.data.frame(pr$x[, seq_len(5L), drop = FALSE])
    colnames(pc_df) <- paste0("PC_", 1:5)
    profiles_pc <- cbind(profiles, pc_df)

    posterior_list[[ec]] <- causal_iv_posterior(
      data = profiles_pc,
      exposure = ec, outcome = "soc",
      instruments = colnames(pc_df),
      covariates  = ecov,
      B           = 200L,
      cluster     = "kmeans_cluster",
      seed        = 1L, units = ex$units
    )
  }
}

benchmark_table <- bind_rows(benchmark_rows)
print(benchmark_table)

# ─────────────────────────────────────────────────────────────────────────────
# 4. Sensitivity analysis: vary n_pcs in {3, 5, 7, 10}
# ─────────────────────────────────────────────────────────────────────────────
message("=== [4/6] Sensitivity: vary n_pcs for MAP -> SOC ===")

sens_rows <- list()
for (k in c(3L, 5L, 7L, 10L)) {
  if (k > ncol(emb_used)) next
  f <- tryCatch(
    causal_iv_from_embeddings(
      data = profiles, embeddings = emb_used,
      exposure = "map", outcome = "soc",
      covariates = c("mat", "slope", "elev", "sand", "bd", "trees",
                      "cropland", "grass", "clay"),
      n_pcs = k
    ),
    error = function(e) NULL
  )
  if (is.null(f)) next
  sens_rows[[as.character(k)]] <- data.frame(
    n_pcs     = k,
    beta_iv   = f$effect,
    se        = f$se,
    ci_lo     = f$ci_lo,
    ci_hi     = f$ci_hi,
    stage1_F  = f$stage1_F,
    sargan_p  = f$sargan_p,
    stringsAsFactors = FALSE
  )
}
sensitivity_table <- bind_rows(sens_rows)
print(sensitivity_table)

# ─────────────────────────────────────────────────────────────────────────────
# 5. DAG context: record the DAG used and the backdoor adjustment set
# ─────────────────────────────────────────────────────────────────────────────
message("=== [5/6] DAG adjustment-set provenance ===")

dag <- causal_rds$dag
adj_sets <- list()
for (ex in exposures) {
  ec <- switch(ex$col,
    map   = "wc_bio_12",
    trees = "wc_landcover_trees",
    clay  = "soilgrids_clay"
  )
  adj_sets[[ex$col]] <- tryCatch(
    causal_adjustment_set(dag, exposure = ec,
                            outcome   = "soc_topsoil_gkg",
                            effect    = "direct"),
    error = function(e) NULL
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Save bundle
# ─────────────────────────────────────────────────────────────────────────────
message("=== [6/6] Saving bundle ===")

R_out <- list(
  version            = packageVersion("edaphos"),
  date_computed      = Sys.time(),
  n_profiles         = nrow(profiles),
  proxy_features     = proxy_features,
  n_pcs_default      = 5L,
  syn_summary        = syn_summary,
  syn_posterior      = syn_post,
  syn_diagnostics    = list(stage1_F = iv_syn$stage1_F,
                              sargan_p = iv_syn$sargan_p),
  benchmark_table    = benchmark_table,
  sensitivity_table  = sensitivity_table,
  iv_fits            = fit_list,
  iv_posteriors      = posterior_list,
  dag_adjustment_sets = adj_sets,
  used_moco          = !is.null(moco_embeddings)
)

saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
