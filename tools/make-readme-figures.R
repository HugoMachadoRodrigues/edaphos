# tools/make-readme-figures.R
#
# Regenerates every figure shown in README.md and captures the printed
# outputs of the minimal examples. Run from the package root:
#
#   Rscript tools/make-readme-figures.R
#
# Outputs:
#   man/figures/pillar1-causal.png
#   man/figures/pillar2-piml.png
#   man/figures/pillar3-4d.png
#   man/figures/pillar4-foundation.png
#   man/figures/pillar5-al-learning.png
#   man/figures/pillar5-al-map.png
#   tools/readme-outputs.txt  (captured text outputs, for reference)

suppressPackageStartupMessages({
  library(ggplot2)
})

pkgload::load_all(".", quiet = TRUE)

out_dir <- "man/figures"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Unified ggplot theme for README consistency.
theme_edaphos <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = base_size + 1),
      plot.subtitle = element_text(colour = "grey35"),
      panel.grid.minor = element_blank(),
      legend.position = "bottom"
    )
}

captured <- list()
cap <- function(label, expr) {
  txt <- capture.output(print(expr))
  captured[[label]] <<- txt
  cat("\n===== ", label, " =====\n", sep = "")
  cat(txt, sep = "\n"); cat("\n")
  invisible(expr)
}

# ---------------------------------------------------------------------------
# Pillar 1 -- Causal AI
# ---------------------------------------------------------------------------
cat("\n[Pillar 1] Causal AI -- building Cerrado DAG and backdoor estimator\n")

data(br_cerrado, package = "edaphos")
g <- causal_cerrado_dag()
adj <- causal_adjustment_set(g, exposure = "ndvi", outcome = "soc")
captured$pillar1_adjset <- paste(adj, collapse = ", ")

fit_causal <- causal_estimate_effect(
  br_cerrado, g,
  exposure = "ndvi", outcome = "soc",
  effect   = "direct"
)
cap("pillar1_fit", fit_causal)

df_bar <- data.frame(
  estimator = factor(
    c("Naive (lm(soc ~ ndvi))", "Backdoor-adjusted (Pillar 1)"),
    levels = c("Naive (lm(soc ~ ndvi))", "Backdoor-adjusted (Pillar 1)")
  ),
  coef = c(fit_causal$effect_naive, fit_causal$effect)
)
p1 <- ggplot(df_bar, aes(estimator, coef, fill = estimator)) +
  geom_col(width = 0.55) +
  geom_text(aes(label = signif(coef, 3)),
            vjust = -0.5, size = 5, fontface = "bold") +
  scale_fill_manual(values = c("#D55E00", "#009E73")) +
  labs(
    x = NULL,
    y = expression(paste("Estimated effect of NDVI on SOC (g ", kg^-1, ")")),
    title = "Pillar 1 — Causal AI",
    subtitle = "Naive OLS vs. DAG-guided backdoor adjustment on br_cerrado"
  ) +
  theme_edaphos() + theme(legend.position = "none")
ggsave(file.path(out_dir, "pillar1-causal.png"), p1,
       width = 7.5, height = 4.2, dpi = 160)

# ---------------------------------------------------------------------------
# Pillar 2 -- Physics-Informed ML
# ---------------------------------------------------------------------------
cat("\n[Pillar 2] PIML -- parametric ODE and Neural ODE on colusa pedon\n")

data(sp4, package = "aqp")
sp4$depth <- (sp4$top + sp4$bottom) / 2
colusa_df <- subset(sp4, id == "colusa")

fit_param <- piml_profile_fit(colusa_df$depth, colusa_df$clay)
cap("pillar2_param", fit_param)

grid_z <- seq(0, max(colusa_df$depth) + 10, by = 1)
pred_param <- data.frame(depth = grid_z,
                         clay  = predict(fit_param, grid_z),
                         model = "Parametric ODE")

torch_ok <- requireNamespace("torch", quietly = TRUE) &&
            isTRUE(tryCatch(torch::torch_is_installed(),
                            error = function(e) FALSE))
if (torch_ok) {
  fit_neural <- piml_neural_ode_fit(colusa_df$depth, colusa_df$clay,
                                    hidden = c(16L, 16L),
                                    epochs = 500L, seed = 1L,
                                    verbose = FALSE)
  cap("pillar2_neural", fit_neural)
  pred_neural <- data.frame(depth = grid_z,
                            clay  = predict(fit_neural, grid_z),
                            model = "Neural ODE")
  pred_all <- rbind(pred_param, pred_neural)
} else {
  pred_all <- pred_param
}

obs_pts <- data.frame(depth = colusa_df$depth, clay = colusa_df$clay)
p2 <- ggplot() +
  geom_line(data = pred_all, aes(clay, depth, colour = model),
            linewidth = 1.1) +
  geom_point(data = obs_pts, aes(clay, depth),
             size = 3.5, colour = "firebrick", shape = 21,
             fill = "firebrick", alpha = 0.85) +
  scale_y_reverse() +
  scale_colour_manual(values = c("Parametric ODE" = "#0072B2",
                                 "Neural ODE"    = "#009E73")) +
  labs(
    x = "Clay (%)", y = "Depth (cm)", colour = NULL,
    title = "Pillar 2 — Physics-Informed ML",
    subtitle = expression(
      paste("colusa pedon, aqp::sp4 (A / ABt / Bt1 / Bt2); dy/dz = -",
            lambda[0], e^{-mu~z}, "(y-", y[infinity], ")",
            " and its Neural-ODE generalisation")
    )
  ) +
  theme_edaphos()
ggsave(file.path(out_dir, "pillar2-piml.png"), p2,
       width = 7, height = 5, dpi = 160)

# ---------------------------------------------------------------------------
# Pillar 3 -- 4D Pedometry (requires torch runtime)
# ---------------------------------------------------------------------------
cat("\n[Pillar 3] 4D -- stacked ConvLSTM + rollout on synthetic SOC cube\n")

if (torch_ok) {
  cube <- temporal_synth_soc_cube(H = 12L, W = 12L, T_total = 18L, seed = 7L)
  past_tensor   <- temporal_cube_to_tensor(cube, t_slice = 1:12)
  future_tensor <- temporal_cube_to_tensor(cube, t_slice = 13:18)

  fit_temporal <- temporal_convlstm_fit(
    sequence        = past_tensor$sequence,
    target          = past_tensor$target,
    hidden_dims     = c(12L, 6L),
    kernel_size     = 3L,
    return_sequence = TRUE,
    epochs          = 120L, lr = 0.02,
    seed            = 1L, verbose = FALSE
  )
  cap("pillar3_fit", fit_temporal)

  forecast <- temporal_convlstm_rollout(
    fit_temporal,
    past_sequence  = past_tensor$sequence,
    future_drivers = future_tensor$sequence
  )

  sc <- past_tensor$scaling
  px <- c(6L, 6L)   # arbitrary pixel in the centre
  observed <- cube$soc[, px[1], px[2]]
  pred_abs <- as.numeric(forecast[1L, , px[1], px[2]]) * sc$soc_sd +
              sc$soc_mu

  ts_df <- rbind(
    data.frame(month = 1:18, soc = observed, series = "Observed (cube)"),
    data.frame(month = 13:18, soc = pred_abs, series = "ConvLSTM forecast")
  )
  p3 <- ggplot(ts_df, aes(month, soc, colour = series)) +
    geom_vline(xintercept = 12.5, linetype = 2, colour = "grey60") +
    annotate("text", x = 12.35, y = max(ts_df$soc) * 1.02,
             label = "train | forecast", hjust = 1, size = 3.2,
             colour = "grey40") +
    geom_line(linewidth = 1) +
    geom_point(size = 2.5) +
    scale_colour_manual(values = c("Observed (cube)"   = "#0072B2",
                                    "ConvLSTM forecast" = "#D55E00")) +
    scale_x_continuous(breaks = c(1, 6, 12, 18)) +
    labs(
      x = "Month", y = expression(paste("SOC (g ", kg^-1, ")")),
      colour = NULL,
      title = "Pillar 3 — 4D Pedometry",
      subtitle = "Stacked ConvLSTM trained on months 1-12, rollout on 13-18 (centre pixel)"
    ) +
    theme_edaphos()
  ggsave(file.path(out_dir, "pillar3-4d.png"), p3,
         width = 7.5, height = 4.2, dpi = 160)
}

# ---------------------------------------------------------------------------
# Pillar 4 -- Foundation Models (SimCLR)
# ---------------------------------------------------------------------------
cat("\n[Pillar 4] Foundation -- SimCLR pre-training on br_cerrado patches\n")

if (torch_ok) {
  covs_base <- c("elev", "slope", "twi", "map_mm", "ndvi")
  H <- length(unique(br_cerrado$y))
  W <- length(unique(br_cerrado$x))
  grid <- br_cerrado[order(br_cerrado$y, br_cerrado$x), ]
  mat_of <- function(col) {
    matrix(grid[[col]], nrow = H, ncol = W, byrow = TRUE)
  }
  z_mat <- function(m) (m - mean(m)) / max(stats::sd(m), 1e-6)
  channels <- lapply(covs_base, function(c) z_mat(mat_of(c)))
  cube4 <- aperm(array(unlist(channels),
                       dim = c(H, W, length(covs_base))),
                 c(3L, 1L, 2L))

  mirror_pad <- function(m, p) {
    top <- m[p:1, , drop = FALSE]
    bot <- m[nrow(m):(nrow(m) - p + 1L), , drop = FALSE]
    tall <- rbind(top, m, bot)
    left  <- tall[, p:1, drop = FALSE]
    right <- tall[, ncol(tall):(ncol(tall) - p + 1L), drop = FALSE]
    cbind(left, tall, right)
  }
  pad <- 3L
  padded4 <- array(0, dim = c(length(covs_base),
                              H + 2L * pad, W + 2L * pad))
  for (c in seq_along(covs_base)) {
    padded4[c, , ] <- mirror_pad(cube4[c, , ], pad)
  }
  patches <- array(0, dim = c(H * W, length(covs_base), 7L, 7L))
  k <- 1L
  for (i in seq_len(H)) for (j in seq_len(W)) {
    patches[k, , , ] <- padded4[, i:(i + 2L * pad), j:(j + 2L * pad)]
    k <- k + 1L
  }
  set.seed(1L)
  pretrain_idx <- sample(nrow(patches), 300L)

  sim_fit <- foundation_simclr_pretrain(
    patches[pretrain_idx, , , , drop = FALSE],
    feature_dim = 16L, proj_dim = 8L,
    batch_size  = 32L, epochs = 40L, lr = 0.005,
    seed        = 1L, verbose = FALSE
  )
  cap("pillar4_fit", sim_fit)

  loss_df <- data.frame(
    epoch = seq_along(sim_fit$loss_history),
    loss  = sim_fit$loss_history
  )
  p4 <- ggplot(loss_df, aes(epoch, loss)) +
    geom_line(linewidth = 1, colour = "#7E1E9C") +
    geom_point(size = 1.6, colour = "#7E1E9C") +
    scale_y_continuous(limits = c(NA, max(loss_df$loss) * 1.02)) +
    labs(
      x = "Epoch", y = "NT-Xent contrastive loss",
      title = "Pillar 4 — Foundation Models",
      subtitle = expression(
        paste("SimCLR on ", 7 %*% 7, " raster patches from br_cerrado ",
              "(300 anchors, 40 epochs)")
      )
    ) +
    theme_edaphos()
  ggsave(file.path(out_dir, "pillar4-foundation.png"), p4,
         width = 7, height = 4.2, dpi = 160)
}

# ---------------------------------------------------------------------------
# Pillar 5 -- Autonomous Active Learning
# ---------------------------------------------------------------------------
cat("\n[Pillar 5] AL -- closed-loop sampling on br_cerrado\n")

covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
set.seed(42)
seed_idx <- al_initial_design(br_cerrado, covariates = covs,
                              n = 25L, iter = 1500L)
set.seed(42)
al_model <- al_loop(
  labeled    = br_cerrado[ seed_idx, ],
  candidates = br_cerrado[-seed_idx, ],
  target     = "soc", covariates = covs,
  coords     = c("x", "y"),
  budget     = 45L, batch = 5L,
  strategy   = "hybrid", alpha = 0.7,
  num.trees  = 500L, verbose = FALSE
)
cap("pillar5_model", al_model)
cap("pillar5_history_tail", tail(al_history(al_model), 5))

hist_df <- al_history(al_model)
p5a <- ggplot(hist_df, aes(n_labeled, rmse_oob)) +
  geom_line(linewidth = 1, colour = "#0072B2") +
  geom_point(size = 2.8, colour = "#0072B2") +
  labs(
    x = "n labeled", y = expression(paste("OOB RMSE (g ", kg^-1, " SOC)")),
    title = "Pillar 5 — Learning curve",
    subtitle = "Hybrid uncertainty × diversity policy, budget = 45"
  ) +
  theme_edaphos()
ggsave(file.path(out_dir, "pillar5-al-learning.png"), p5a,
       width = 6.5, height = 4.2, dpi = 160)

seed_xy <- br_cerrado[seed_idx, c("x", "y")]
seed_xy$type <- "Seed (cLHS)"
queried_xy <- al_model$labeled[-seq_len(length(seed_idx)), c("x", "y")]
queried_xy$type <- "AL-queried"
samp <- rbind(seed_xy, queried_xy)

p5b <- ggplot() +
  geom_raster(data = br_cerrado, aes(x, y, fill = soc)) +
  scale_fill_viridis_c(option = "D",
                       name = expression(paste("SOC (g ", kg^-1, ")"))) +
  geom_point(data = samp,
             aes(x, y, shape = type, colour = type),
             size = 2.4, stroke = 1.1) +
  scale_colour_manual(values = c("Seed (cLHS)" = "white",
                                  "AL-queried"  = "firebrick")) +
  scale_shape_manual(values = c("Seed (cLHS)" = 1, "AL-queried" = 4)) +
  coord_equal() +
  labs(
    x = "Longitude (°)", y = "Latitude (°)",
    shape = NULL, colour = NULL,
    title = "Pillar 5 — Adaptive sampling map",
    subtitle = "25 cLHS seeds + 45 AL-queried points on Cerrado surrogate"
  ) +
  theme_edaphos() +
  theme(legend.position = "bottom", legend.box = "horizontal")
ggsave(file.path(out_dir, "pillar5-al-map.png"), p5b,
       width = 7, height = 5.5, dpi = 160)

# ---------------------------------------------------------------------------
# Pillar 6 -- Quantum ML (pure-R ZZFeatureMap kernel)
# ---------------------------------------------------------------------------
cat("\n[Pillar 6] Quantum -- ZZFeatureMap kernel + KRR on br_cerrado\n")

# Pillar 6 demo: predict NDVI median-class from 3 covariates that drive
# it in the br_cerrado data-generating process. Three qubits give a
# Hilbert space of dimension 2^3 = 8 and the signal is strong enough
# that the quantum kernel clearly separates classes in the Gram matrix.
set.seed(1L)
q_covs <- c("slope", "twi", "map_mm")   # true NDVI predictors in the DGP
n_q <- 200L
q_idx <- sample(nrow(br_cerrado), n_q)
Xq_raw <- br_cerrado[q_idx, q_covs, drop = FALSE]
Xq <- quantum_scale(as.matrix(Xq_raw))
yq <- sign(br_cerrado$ndvi[q_idx] -
             stats::median(br_cerrado$ndvi[q_idx]))
yq[yq == 0] <- 1L

# 140 / 60 split
set.seed(1L)
tr <- sort(sample(n_q, 140L)); te <- setdiff(seq_len(n_q), tr)

K_train <- quantum_kernel(Xq[tr, ], reps = 2L)
fit_q <- quantum_krr_fit(Xq[tr, ], yq[tr], reps = 2L, lambda = 0.1)
cap("pillar6_fit", fit_q)

acc_test <- mean(predict(fit_q, Xq[te, ], type = "class") == yq[te])
captured$pillar6_acc <- sprintf("test accuracy: %.2f  (%d test samples)",
                                 acc_test, length(te))

# Kernel heatmap sorted by predicted score for interpretability
order_by_score <- order(fit_q$fitted)
K_sorted <- K_train[order_by_score, order_by_score]
kdf <- expand.grid(i = seq_len(nrow(K_sorted)),
                   j = seq_len(ncol(K_sorted)))
kdf$K <- as.vector(K_sorted)

p6 <- ggplot(kdf, aes(i, j, fill = K)) +
  geom_raster() +
  scale_fill_viridis_c(option = "magma",
                       name = expression(K[ij]),
                       limits = c(0, 1)) +
  coord_equal() +
  labs(
    x = "training sample index (ordered by predicted SOC score)",
    y = "training sample index",
    title = "Pillar 6 — Quantum kernel Gram matrix",
    subtitle = "ZZFeatureMap on 4 covariates of br_cerrado (reps = 2); entry K_ij = |<\u03c6(x_j)|\u03c6(x_i)>|\u00b2"
  ) +
  theme_edaphos() +
  theme(axis.text = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank())
ggsave(file.path(out_dir, "pillar6-quantum.png"), p6,
       width = 6.5, height = 6, dpi = 160)

# ---------------------------------------------------------------------------
# Dump the captured text outputs
# ---------------------------------------------------------------------------
out_file <- file.path("tools", "readme-outputs.txt")
dir.create("tools", showWarnings = FALSE, recursive = TRUE)
con <- file(out_file, "w")
for (nm in names(captured)) {
  writeLines(paste0("===== ", nm, " ====="), con)
  writeLines(captured[[nm]], con)
  writeLines("", con)
}
close(con)
cat("\nAll README figures written to ", out_dir,
    "\nCaptured outputs in ", out_file, "\n", sep = "")
