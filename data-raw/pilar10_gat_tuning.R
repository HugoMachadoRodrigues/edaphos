## data-raw/pilar10_gat_tuning.R
##
## Nested cross-validation comparing the Pillar 10 GAT against a quantile
## regression forest on the WoSIS Cerrado benchmark.
##
## PROTOCOL.  The outer loop is the same 5 spatially blocked folds the main
## benchmark uses, and its test folds are never seen during tuning.  Inside
## each outer training set an inner blocked split selects hyperparameters; the
## chosen configuration is then refitted on the full outer training set and
## scored once on the untouched outer test fold.  Both methods get a tuning
## budget, because giving one method a grid search and the other its defaults
## measures the budget, not the method.
##
## This exists because the GAT's headline number has to survive the question
## "did you tune on the test set?".  Tuning on the blocked folds and reporting
## those folds is exactly the leak this package spent a release removing.
##
##   Rscript data-raw/pilar10_gat_tuning.R
##   -> inst/extdata/pilar10_gat_tuning.rds

suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages({ library(dplyr); library(ranger) })

OUT_PATH <- file.path("inst", "extdata", "pilar10_gat_tuning.rds")
# Members per GAT ensemble.  QRF gets 500-1000 trees; 10 GAT members is still
# a far smaller ensemble, and the residual asymmetry favours QRF -- recorded
# rather than quietly equalised in the GAT's favour.
N_ENSEMBLE <- 10L
set.seed(20260726L)

# ---------------------------------------------------------------------------
# Data + outer folds (identical to the 6-pillar benchmark)
# ---------------------------------------------------------------------------
bench <- readRDS("inst/extdata/benchmark_wosis_6pilar.rds")
prof  <- readRDS("inst/extdata/causal_cerrado_real.rds")$profiles |>
  filter(!is.na(soc_topsoil_gkg), !is.na(lon), !is.na(lat)) |>
  mutate(soc = log1p(soc_topsoil_gkg), map = wc_bio_12, mat = wc_bio_01 / 10,
         trees = wc_landcover_trees, cropland = wc_landcover_cropland,
         grass = wc_landcover_grassland, clay = soilgrids_clay,
         sand = soilgrids_sand, bd = soilgrids_bdod)
cov_cols <- bench$cov_cols
prof <- prof[stats::complete.cases(prof[, cov_cols]), ]
outer_folds <- bench$folds
stopifnot(length(outer_folds) == nrow(prof))
message(sprintf("n = %d, outer folds = %s", nrow(prof),
                paste(table(outer_folds), collapse = "/")))

# inner folds: k-means blocks inside each outer training set, so the inner
# split is spatially blocked too and the tuning sees the same kind of shift
# the outer evaluation will apply
inner_blocks <- function(idx, n_inner = 3L, seed = 1L) {
  set.seed(seed)
  km <- stats::kmeans(prof[idx, c("lon", "lat")], centers = n_inner,
                       nstart = 5L)
  km$cluster
}

nse <- function(truth, pred, null_pred)
  1 - sum((truth - pred)^2) / sum((truth - null_pred)^2)

# ---------------------------------------------------------------------------
# Search spaces
# ---------------------------------------------------------------------------
gat_grid <- expand.grid(
  k             = c(8L, 15L, 25L),
  hidden        = c(4L, 8L, 16L),
  n_heads       = c(1L, 2L, 4L),
  n_layers      = c(1L, 2L),
  lr            = c(0.01, 0.03),
  weight_decay  = c(1e-4, 1e-2, 0.1),
  edges         = c("feature", "spatial", "hybrid"),
  stringsAsFactors = FALSE
)
# keep the run tractable: a random subsample of the full factorial
set.seed(11L)
gat_grid <- gat_grid[sample(nrow(gat_grid), min(30L, nrow(gat_grid))), ]

qrf_grid <- expand.grid(
  num.trees      = c(500L, 1000L),
  mtry           = c(2L, 3L, 5L, 7L),
  min.node.size  = c(5L, 10L, 20L),
  stringsAsFactors = FALSE
)
message(sprintf("grids: GAT %d configs, QRF %d configs",
                nrow(gat_grid), nrow(qrf_grid)))

fit_gat <- function(train_df, test_df, cfg, seed = 1L) {
  all_df <- rbind(train_df[, c("lon", "lat", cov_cols)],
                   test_df[,  c("lon", "lat", cov_cols)])
  y <- c(train_df$soc, rep(NA_real_, nrow(test_df)))
  mask <- c(rep(TRUE, nrow(train_df)), rep(FALSE, nrow(test_df)))
  g <- gnn_build_graph(all_df, k = cfg$k, feature_cols = cov_cols,
                        edges = cfg$edges)
  # Seed ensemble, so the comparison is ensemble-vs-ensemble.  A single GAT
  # against a 500-tree forest measures the ensembling as much as the method.
  f <- gnn_fit_ensemble(g, y, train_mask = mask, n_ensemble = N_ENSEMBLE,
                         hidden = cfg$hidden, n_heads = cfg$n_heads,
                         n_layers = cfg$n_layers, epochs = 250L,
                         lr = cfg$lr, weight_decay = cfg$weight_decay,
                         seed = seed)
  stats::predict(f)[!mask]
}

fit_qrf <- function(train_df, test_df, cfg, seed = 1L) {
  fml <- stats::as.formula(paste("soc ~", paste(cov_cols, collapse = " + ")))
  m <- ranger::ranger(fml, data = train_df, num.trees = cfg$num.trees,
                       mtry = cfg$mtry, min.node.size = cfg$min.node.size,
                       quantreg = TRUE, seed = seed)
  stats::predict(m, data = test_df)$predictions
}

# ---------------------------------------------------------------------------
# Nested CV
# ---------------------------------------------------------------------------
rows <- list(); chosen <- list()
pred_gat <- pred_qrf <- null_v <- rep(NA_real_, nrow(prof))

for (of in sort(unique(outer_folds))) {
  te_i <- which(outer_folds == of)
  tr_i <- which(outer_folds != of)
  message(sprintf("\n=== outer fold %d  (train %d / test %d) ===",
                  of, length(tr_i), length(te_i)))
  inner <- inner_blocks(tr_i, seed = of)

  score_grid <- function(grid, fitter, label) {
    sc <- vapply(seq_len(nrow(grid)), function(g_i) {
      cfg <- grid[g_i, , drop = FALSE]
      v <- vapply(sort(unique(inner)), function(inf) {
        i_te <- tr_i[inner == inf]; i_tr <- tr_i[inner != inf]
        p <- tryCatch(fitter(prof[i_tr, ], prof[i_te, ], cfg, seed = of * 10L + inf),
                      error = function(e) rep(NA_real_, length(i_te)))
        nse(prof$soc[i_te], p, rep(mean(prof$soc[i_tr]), length(i_te)))
      }, numeric(1))
      mean(v, na.rm = TRUE)
    }, numeric(1))
    best <- which.max(sc)
    message(sprintf("  %s: best inner NSE = %+.4f", label, sc[best]))
    list(cfg = grid[best, , drop = FALSE], inner_nse = sc[best], all = sc)
  }

  g_sel <- score_grid(gat_grid, fit_gat, "GAT")
  q_sel <- score_grid(qrf_grid, fit_qrf, "QRF")

  pred_gat[te_i] <- fit_gat(prof[tr_i, ], prof[te_i, ], g_sel$cfg, seed = of)
  pred_qrf[te_i] <- fit_qrf(prof[tr_i, ], prof[te_i, ], q_sel$cfg, seed = of)
  null_v[te_i]   <- mean(prof$soc[tr_i])

  chosen[[as.character(of)]] <- list(gat = g_sel$cfg, qrf = q_sel$cfg,
                                      gat_inner = g_sel$inner_nse,
                                      qrf_inner = q_sel$inner_nse)
  rows[[length(rows) + 1L]] <- data.frame(
    fold = of, n_test = length(te_i),
    gat_nse = nse(prof$soc[te_i], pred_gat[te_i], null_v[te_i]),
    qrf_nse = nse(prof$soc[te_i], pred_qrf[te_i], null_v[te_i]),
    stringsAsFactors = FALSE)
  message(sprintf("  OUTER fold %d: GAT %+.4f | QRF %+.4f", of,
                  rows[[length(rows)]]$gat_nse, rows[[length(rows)]]$qrf_nse))
}

fold_tbl <- bind_rows(rows)
pooled <- data.frame(
  method = c(sprintf("P10 GAT (tuned, %d-member ensemble)", N_ENSEMBLE),
             "QRF (tuned)"),
  pooled_rmse = c(edaphos_rmse(prof$soc, pred_gat),
                  edaphos_rmse(prof$soc, pred_qrf)),
  pooled_r2   = c(edaphos_r2(prof$soc, pred_gat),
                  edaphos_r2(prof$soc, pred_qrf)),
  nse_vs_training_fold_mean = c(nse(prof$soc, pred_gat, null_v),
                                nse(prof$soc, pred_qrf, null_v)),
  stringsAsFactors = FALSE)

cat("\n=== per outer fold ===\n"); print(fold_tbl, row.names = FALSE)
cat("\n=== pooled (nested CV, no tuning on the evaluated folds) ===\n")
print(pooled, row.names = FALSE)

# paired block bootstrap over the 5 spatial folds
set.seed(99L)
B <- 4000L
d_boot <- replicate(B, {
  s <- sample(sort(unique(outer_folds)), replace = TRUE)
  i <- unlist(lapply(s, function(f) which(outer_folds == f)))
  nse(prof$soc[i], pred_gat[i], null_v[i]) -
    nse(prof$soc[i], pred_qrf[i], null_v[i])
})
ci <- stats::quantile(d_boot, c(0.025, 0.975), na.rm = TRUE)
cat(sprintf("\nGAT - QRF pooled NSE difference: %+.4f  [95%% block-bootstrap CI %+.4f, %+.4f]\n",
            pooled$nse_vs_training_fold_mean[1] - pooled$nse_vs_training_fold_mean[2],
            ci[1], ci[2]))
cat(sprintf("P(GAT beats QRF) = %.3f\n", mean(d_boot > 0, na.rm = TRUE)))

saveRDS(list(
  protocol = "nested CV: outer = 5 spatially blocked folds (never tuned on), inner = 3 k-means blocks within each outer training set",
  response_scale = "log1p(g/kg)",
  n_profiles = nrow(prof), cov_cols = cov_cols,
  gat_grid = gat_grid, qrf_grid = qrf_grid, gat_n_ensemble = N_ENSEMBLE,
  chosen_per_fold = chosen, fold_table = fold_tbl, pooled = pooled,
  boot_diff_ci = ci, p_gat_beats_qrf = mean(d_boot > 0, na.rm = TRUE),
  date_computed = Sys.time()
), OUT_PATH, compress = "xz")
message(sprintf("\n=== DONE | %s ===", OUT_PATH))
