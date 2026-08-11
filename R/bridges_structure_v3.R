# Structural bridges between pilares (edaphos v3.0.0).
#
#   gnn_causal_discovery()           (Pilar 10 x Pilar 1)
#   temporal_piml_loss()             (Pilar 2 x Pilar 3)
#   qf_krr_on_gat_embeddings()       (Pilar 6 x Pilar 10)

# ---------------------------------------------------------------------------
# P10 x P1 -- Graph-based causal discovery
# ---------------------------------------------------------------------------
#
# Hypothesis
# ----------
# Node-level embeddings learned by a GAT (Pilar 10) encode the
# conditional-correlation structure of each profile's covariates
# given its k-NN neighbourhood.  If we run `causal_structure_learn`
# (Pilar 1) on the *embedding-augmented* feature frame -- covariates
# + GAT embeddings -- bnlearn can recover a DAG that respects both
# the direct feature dependencies AND the spatial-neighbourhood
# conditioning the GAT has already absorbed.
#
# This produces a DAG that is richer than the pure-feature one AND
# (unlike a raw spatial DAG) has interpretable node identities
# because we restrict the whitelist to feature names.

#' Graph-based causal discovery (Pilar 10 x Pilar 1)
#'
#' Runs `causal_structure_learn()` on a feature frame augmented with
#' GAT node embeddings, which act as nuisance conditioners absorbing
#' spatial dependence the expert DAG does not name.
#'
#' The returned graph is the FULL augmented DAG: the `z_emb_*`
#' conditioners are vertices of `$graph` like any other.  The
#' restriction to the caller's variables is attached alongside it as
#' `$edges_feature_only`, and everything downstream that walks
#' `$graph` -- [`causal_kg_edges()`], backdoor adjustment -- still
#' sees the embedding nodes.
#'
#' @param gnn_fit An `edaphos_gnn_gat` from [`gnn_fit()`].
#' @param feature_frame Data frame of the actual variables to form
#'   the DAG over.  Must have the same number of rows as the graph
#'   on which `gnn_fit` was trained.
#' @param method Passed to [`causal_structure_learn()`]; default
#'   `"hc"`.
#' @param whitelist,blacklist Optional edge constraints (see
#'   [`causal_structure_learn()`]).
#' @param n_emb_cols Integer; how many GAT embedding dimensions to
#'   use as conditioners.  Default `min(8, emb_dim)` to keep the
#'   search space manageable.
#' @param bootstrap Logical; pass to `causal_structure_learn()`.
#' @param R_boot Integer; bootstrap resamples.
#' @param seed Optional RNG seed.
#' @return An `edaphos_causal_kg` from the underlying structure-learn
#'   call.  `$graph` is the DAG over `feature_frame` *and* the
#'   `z_emb_*` conditioners; `$edges_feature_only` is a two-column
#'   character matrix of the arcs whose endpoints are both in
#'   `feature_frame` (added only when `igraph` is installed).
#' @examples
#' # `causal_structure_learn()` needs bnlearn AND igraph, both
#' # Suggests, so the whole hand-off is guarded.
#' if (requireNamespace("bnlearn", quietly = TRUE) &&
#'     requireNamespace("igraph", quietly = TRUE)) {
#'
#'   set.seed(1)
#'   sub <- br_cerrado[sample(nrow(br_cerrado), 150L), ]
#'   names(sub)[names(sub) == "x"] <- "lon"
#'   names(sub)[names(sub) == "y"] <- "lat"
#'
#'   # Pillar 10 side: a k-NN co-location graph over the pixels, then
#'   # a GAT whose node embeddings have already absorbed each pixel's
#'   # spatial neighbourhood.
#'   g <- gnn_build_graph(sub, k = 6L,
#'                        feature_cols = c("elev", "slope", "twi",
#'                                         "map_mm", "ndvi"))
#'   gat <- gnn_fit(g, sub$soc, hidden = 8L, n_heads = 2L,
#'                  n_layers = 1L, epochs = 40L, seed = 1L)
#'
#'   # Pillar 1 side: hill-climbing over the six covariates PLUS four
#'   # embedding dimensions carried along as conditioners.
#'   feats <- sub[, c("elev", "slope", "twi", "map_mm", "ndvi", "soc")]
#'   kg <- gnn_causal_discovery(gat, feats, method = "hc",
#'                              n_emb_cols = 4L, seed = 1L)
#'
#'   # The restriction the name promises lives in one extra field.
#'   # `kg$graph` is still the augmented DAG -- 10 vertices, 25 arcs,
#'   # 17 of them touching a conditioner.  Anything that reads
#'   # `kg$graph` gets the nuisance nodes too.
#'   print(c(vertices     = igraph::vcount(kg$graph),
#'           arcs         = igraph::ecount(kg$graph),
#'           feature_only = nrow(kg$edges_feature_only)))
#'   e <- causal_kg_edges(kg)
#'   print(sum(grepl("^z_emb_", e$cause) | grepl("^z_emb_", e$effect)))
#'
#'   # What the conditioning bought, read against the same search with
#'   # no embeddings at all: eight arcs over the six covariates
#'   # against seven, four of them shared.
#'   plain <- causal_structure_learn(feats, variables = names(feats),
#'                                   method = "hc")
#'   p <- causal_kg_edges(plain)
#'   a_arcs <- paste(kg$edges_feature_only[, 1L], "->",
#'                   kg$edges_feature_only[, 2L])
#'   p_arcs <- paste(p$cause, "->", p$effect)
#'   print(setdiff(a_arcs, p_arcs))
#'   # "elev -> map_mm" "map_mm -> ndvi" "slope -> soc" "twi -> soc"
#'   print(setdiff(p_arcs, a_arcs))
#'   # "soc -> map_mm" "slope -> map_mm" "twi -> map_mm"
#'
#'   # Read those two lines together before believing either DAG.
#'   # Without the embeddings three arrows run INTO mean annual
#'   # rainfall, from carbon and from terrain; conditioning on four
#'   # GAT dimensions removes all three, puts elevation upstream of
#'   # rainfall instead, and sends slope and TWI straight to SOC.
#'   # Encouraging -- but a BIC score is identical across a Markov
#'   # equivalence class, so arc DIRECTION out of `hc` is a search
#'   # artefact and not evidence.  Pin the arrows you already know
#'   # with `whitelist` / `blacklist` before reading any of it
#'   # causally.
#' }
#' @export
gnn_causal_discovery <- function(gnn_fit, feature_frame,
                                    method = c("hc", "tabu", "pc-stable"),
                                    whitelist = NULL, blacklist = NULL,
                                    n_emb_cols = NULL,
                                    bootstrap = FALSE,
                                    R_boot = 100L,
                                    seed = NULL) {
  method <- match.arg(method)
  stopifnot(inherits(gnn_fit, "edaphos_gnn_gat"))
  if (!is.null(seed)) set.seed(seed)
  emb <- gnn_fit$emb
  if (nrow(emb) != nrow(feature_frame)) {
    stop("feature_frame must have the same number of rows as the ",
          "training graph (", nrow(emb), "); got ",
          nrow(feature_frame), ".", call. = FALSE)
  }
  n_emb_cols <- if (is.null(n_emb_cols))
                  min(8L, ncol(emb)) else
                  min(n_emb_cols, ncol(emb))
  emb_slice <- emb[, seq_len(n_emb_cols), drop = FALSE]
  colnames(emb_slice) <- paste0("z_emb_", seq_len(n_emb_cols))

  feat_cols <- names(feature_frame)
  augmented <- cbind(feature_frame, as.data.frame(emb_slice))
  # Blacklist any edge INTO an embedding dimension or FROM features
  # INTO other features that the user doesn't want
  kg <- causal_structure_learn(
    data       = augmented,
    variables  = names(augmented),
    method     = method,
    whitelist  = whitelist,
    blacklist  = blacklist,
    bootstrap  = bootstrap,
    R_boot     = R_boot,
    seed       = seed
  )
  # Restrict returned edges to those strictly between user features
  if (requireNamespace("igraph", quietly = TRUE)) {
    el <- igraph::as_edgelist(kg$graph)
    keep_rows <- el[, 1L] %in% feat_cols & el[, 2L] %in% feat_cols
    el_kept <- el[keep_rows, , drop = FALSE]
    kg$edges_feature_only <- el_kept
  }
  kg$n_emb_cols     <- n_emb_cols
  kg$feature_cols   <- feat_cols
  kg
}

# ---------------------------------------------------------------------------
# P2 x P3 -- ODE-coupled ConvLSTM mass-balance regulariser
# ---------------------------------------------------------------------------
#
# Hypothesis
# ----------
# The v1.5.0 ConvLSTM (Pilar 3) optionally includes a mass-balance
# physics loss that penalises pixel-wise SOC dynamics inconsistent
# with a soil-carbon accounting.  But the accounting rate is a
# hard-coded scalar.  The Pilar 2 pedogenetic ODE gives us a
# principled site-specific rate: the `lambda0` parameter of the
# `piml_profile_fit()` result.
#
# `temporal_piml_loss()` produces a callable loss function for use
# in the ConvLSTM training loop that CONSUMES an ODE fit and
# computes the appropriate physics residual per pixel.

#' Physics-informed ConvLSTM mass-balance loss (Pilar 2 x Pilar 3)
#'
#' Factory that returns a `function(y_pred, y_true, driver)` closure
#' penalising SOC-dynamics predictions that violate the local-rate
#' kinetics inferred from the Pilar 2 ODE fit.
#'
#' [`temporal_convlstm_fit()`] has no argument that takes this
#' closure: its physics term is the built-in mass-balance
#' regulariser switched on by `physics_lambda` and parametrised by
#' `physics_k_in` / `physics_k_out`.  Use the closure inside a
#' training loop of your own, or as a post-hoc diagnostic on a
#' predicted cube.
#'
#' @param ode_fit An `edaphos_piml_profile` or
#'   `edaphos_piml_bayes` fit.
#' @param weight Numeric; loss weight relative to the MSE term.
#'   Default `0.1`.
#' @return A function `loss_fn(y_pred, y_true, driver)`.  Only
#'   `y_pred` is read -- `y_true` and `driver` are accepted for
#'   signature compatibility and ignored, as is the ODE's
#'   depth-modulation parameter `mu`.  It returns `weight` times the
#'   mean squared deviation of the predicted per-step change from
#'   `-lambda0 * (y - y(Inf))`, where `y(Inf)` is the value the profile
#'   ATTAINS -- not the ODE coordinate `y_inf`, which is negative on 55% of
#'   real fits and would make the penalty pull predictions towards
#'   impossible carbon.  A length-1 numeric for a `(time, row, col)` R
#'   array, a scalar `torch_tensor` for a `torch_tensor`.
#' @examples
#' # Pillar 2 first: fit the pedogenetic ODE to one Cerrado pedon.
#' depths <- c(5, 15, 30, 60, 100)             # horizon mid-depths, cm
#' soc_z  <- c(27.6, 21.2, 15.4, 10.1, 7.8)    # SOC, g/kg
#' ode <- piml_profile_fit(depths, soc_z)
#' # y_inf is the equation's coordinate; y(Inf) is what the profile reaches.
#' # The penalty targets the second, because the first is negative on most
#' # real fits and no soil decays towards negative carbon.
#' round(c(lambda0 = unname(ode$params$lambda0),
#'         y_inf   = unname(ode$params$y_inf),
#'         y_attained = unname(edaphos:::.piml_asymptote(ode$params)),
#'         rmse    = ode$rmse), 4)
#'
#' pl <- temporal_piml_loss(ode, weight = 0.1)
#'
#' # The closure scores a (time, row, col) cube.  A cube that obeys
#' # the kinetics exactly costs nothing; a random walk from the same
#' # starting map does not, and `weight` scales that linearly.
#' set.seed(2)
#' y0 <- matrix(runif(16, 15, 30), 4L, 4L)
#' obey <- walk <- array(0, c(6L, 4L, 4L))
#' obey[1L, , ] <- walk[1L, , ] <- y0
#' for (t in 2:6) {
#'   obey[t, , ] <- obey[t - 1L, , ] -
#'     ode$params$lambda0 *
#'       (obey[t - 1L, , ] - edaphos:::.piml_asymptote(ode$params))
#'   walk[t, , ] <- walk[t - 1L, , ] + rnorm(16)
#' }
#' c(kinetic = pl(obey, obey, NULL), random_walk = pl(walk, walk, NULL))
#' # 7.9e-32 and 0.1723
#' temporal_piml_loss(ode, weight = 0.2)(walk, walk, NULL)   # 0.3447
#'
#' # Three arguments, one of them read.  Neither the observations nor
#' # the driver enter the penalty, and neither does `mu`: this is a
#' # regulariser on the prediction alone.
#' o2 <- ode; o2$params$mu <- 5      # a wildly different depth decay
#' c(y_true_ignored = pl(walk, walk, NULL) == pl(walk, 0 * walk, NULL),
#'   mu_ignored     = pl(walk, walk, NULL) ==
#'     temporal_piml_loss(o2, weight = 0.1)(walk, walk, NULL))  # TRUE TRUE
#'
#' # The unit the bridge silently changes.  `lambda0` was estimated
#' # per CENTIMETRE down a profile and is applied here to a per-TIME-
#' # STEP difference, so the change the penalty calls "expected" at a
#' # 25 g/kg pixel is
#' round(-ode$params$lambda0 *
#'         (25 - edaphos:::.piml_asymptote(ode$params)) * c(1, 12), 3)
#' # -0.698 per step and -8.37 over twelve of them: on monthly frames
#' # that asserts the topsoil loses a third of its carbon every year.
#' # Rescale lambda0 to the cube's time step before the term is
#' # anything but a smoothness penalty.
#'
#' # There is also nowhere to hand it: the ConvLSTM takes rate
#' # constants, never a loss function.
#' "physics_loss_fn" %in% names(formals(temporal_convlstm_fit))  # FALSE
#'
#' # And used post hoc it needs the batch dimension dropped first --
#' # a (batch, time, row, col) prediction is an error, not a silently
#' # averaged one.
#' cube4 <- array(0, c(2L, 6L, 4L, 4L))
#' try(pl(cube4, cube4, NULL))
#' @export
temporal_piml_loss <- function(ode_fit, weight = 0.1) {
  # Parameters are stored differently across the two ODE-fit classes:
  # `edaphos_piml_profile`  -> `ode_fit$params$lambda0` etc.
  # `edaphos_piml_bayes`    -> `ode_fit$map$lambda0` etc.
  pars <- .piml_extract_params(ode_fit)
  lambda0 <- pars$lambda0
  mu      <- pars$mu
  # THE TARGET IS THE ATTAINED VALUE, NOT THE ODE COORDINATE.
  #
  # This used to read `pars$y_inf`, and y_inf is the equilibrium coordinate of
  # the differential equation -- a value the profile only approaches by a
  # fraction 1 - e^{-kappa} and, on real fits, routinely never reaches. Over
  # 200 monotone WoSIS profiles its median is -0.37 g/kg, 55% are negative and
  # the minimum is -1956 g/kg. Using it as the target of a temporal penalty
  # tells the network that a pixel should decay towards negative carbon.
  #
  # The attained value y(Inf) = y_inf + (y0 - y_inf) e^{-kappa} is what the
  # solution actually settles on: over the same 200 profiles its median is
  # 1.5 g/kg and it is never negative. The difference is not cosmetic -- at a
  # 25 g/kg pixel the rate the penalty calls "expected" is 1.10x too large at
  # the median, 10.0x at the 90th percentile and 68.9x at the 99th.
  #
  # This is the same correction al_physics_gate_piml() already carries, and
  # for the same reason; it was never propagated here.
  yi      <- .piml_asymptote(pars)
  force(lambda0); force(mu); force(yi); force(weight)

  # Returns a function compatible with either R-matrix or torch-
  # tensor inputs via a cheap duck-type dispatch.
  function(y_pred, y_true, driver) {
    # Expected local rate under the ODE at each pixel
    #   dy/dz | site-level = -lambda0 * (y - yi)
    # We approximate temporal mass balance as dy/dt ~ -lambda0 * (y - yi)
    # and penalise deviation of predicted (y_{t+1} - y_t) from that.
    is_torch <- inherits(y_pred, "torch_tensor")
    if (is_torch) {
      n_t <- y_pred$size(1L)
      if (n_t < 2L) return(torch::torch_zeros(1L, device = y_pred$device))
      dy_pred <- y_pred[2:n_t, .., drop = FALSE] -
                  y_pred[1:(n_t-1L), .., drop = FALSE]
      expected <- -lambda0 * (y_pred[1:(n_t-1L), .., drop = FALSE] - yi)
      mb_loss <- torch::nnf_mse_loss(dy_pred, expected)
      return(weight * mb_loss)
    }
    # R-matrix branch
    y_pred <- as.array(y_pred); y_true <- as.array(y_true)
    n_t <- dim(y_pred)[1L]
    if (n_t < 2L) return(0)
    dy_pred  <- y_pred[-1L, , , drop = FALSE] -
                 y_pred[-n_t, , , drop = FALSE]
    expected <- -lambda0 * (y_pred[-n_t, , , drop = FALSE] - yi)
    mb_loss <- mean((dy_pred - expected)^2, na.rm = TRUE)
    weight * mb_loss
  }
}

# ---------------------------------------------------------------------------
# P6 x P10 -- Quantum kernel over GAT node embeddings
# ---------------------------------------------------------------------------
#
# Hypothesis
# ----------
# GAT node embeddings (Pilar 10) summarise each profile's local
# neighbourhood in a compact low-dim space.  The Pilar 6 ZZFeatureMap
# lifts that space into a 2^n-dim Hilbert.  Composing them yields a
# quantum kernel over graph-aware representations -- a strict
# generalisation of the v2.0.0 quantum-foundation fusion, now with
# network structure baked into the node representation.

#' Quantum KRR over GAT node embeddings (Pilar 6 x Pilar 10)
#'
#' Thin composition: take the GAT embedding matrix, PCA-reduce to
#' `n_pcs`, feed to [`quantum_krr_fit()`].  Returns a combined fit
#' object that `predict()` unwraps by projecting new embeddings
#' through the stored rotation.
#'
#' @param gnn_fit An `edaphos_gnn_gat` fit.
#' @param y Numeric response (one per training node).
#' @param n_pcs Integer; number of PCs (= qubits).  Default `6L`.
#' @param reps ZZFeatureMap repetitions.  Default `2L`.
#' @param lambda Ridge regulariser.  Default `0.5`.
#' @return An `edaphos_qf_krr_gat` fit.
#' @examples
#' set.seed(1)
#' sub <- br_cerrado[sample(nrow(br_cerrado), 150L), ]
#' names(sub)[names(sub) == "x"] <- "lon"
#' names(sub)[names(sub) == "y"] <- "lat"
#' g <- gnn_build_graph(sub, k = 6L,
#'                      feature_cols = c("elev", "slope", "twi",
#'                                       "map_mm", "ndvi"))
#'
#' # Pillar 10 transductively: the graph spans all 150 pixels, the
#' # regression head sees only the first 100 SOC labels.
#' tr <- 1:100; te <- 101:150
#' y_obs <- sub$soc; y_obs[te] <- NA
#' gat <- gnn_fit(g, y_obs, hidden = 8L, n_heads = 2L, n_layers = 1L,
#'                epochs = 40L, seed = 1L)
#' c(gat        = edaphos_rmse(sub$soc[te], predict(gat)[te]),
#'   train_mean = edaphos_rmse(sub$soc[te], rep(mean(sub$soc[tr]), 50)))
#' # 4.77 vs 6.27 g/kg -- the GAT is ahead of the null it must beat
#'
#' # Now the hand-off, and the first thing it demands: one y per NODE.
#' # There is no train_mask here, so the quantum KRR is fitted on all
#' # 150 labels, including the 50 the GAT was never shown.
#' qk <- qf_krr_on_gat_embeddings(gat, sub$soc, n_pcs = 5L, reps = 1L,
#'                                lambda = 0.5)
#' qk
#' c(nodes = nrow(gat$emb), gat_trained_on = gat$n_train,
#'   krr_trained_on = qk$n_train)                    # 150, 100, 150
#'
#' # Which makes every number the returned object can produce an
#' # in-sample one.  This looks held out and is not:
#' edaphos_rmse(sub$soc[te], predict(qk, newdata = gat$emb[te, ]))  # 2.93
#' edaphos_rmse(sub$soc, predict(qk))   # 2.73, predict() with no
#'                                      # newdata scores the training
#'                                      # embeddings
#'
#' # The honest version: same embedding, KRR refitted on the 100 rows
#' # the GAT actually trained on, read against the training mean.
#' qk_tr <- qf_krr_fit(gat$emb[tr, ], sub$soc[tr], n_pcs = 5L,
#'                     reps = 1L, lambda = 0.5)
#' p <- predict(qk_tr, gat$emb[te, ])
#' c(qf_krr     = edaphos_rmse(sub$soc[te], p),
#'   train_mean = edaphos_rmse(sub$soc[te], rep(mean(sub$soc[tr]), 50)),
#'   r2         = edaphos_r2(sub$soc[te], p))
#' # 6.32, 6.27, -0.049: worse than predicting the mean everywhere.
#' # The GAT embedding the bridge feeds the ZZFeatureMap is 8-dim and
#' # nearly rank-2 -- the first two PCs hold 94 % of its variance --
#' # so five qubits are encoding almost no independent directions.
#' round(qk$reduction$variance_explained, 3)
#' @export
qf_krr_on_gat_embeddings <- function(gnn_fit, y,
                                         n_pcs = 6L, reps = 2L,
                                         lambda = 0.5) {
  stopifnot(inherits(gnn_fit, "edaphos_gnn_gat"),
             length(y) == nrow(gnn_fit$emb))
  fit <- qf_krr_fit(gnn_fit$emb, as.numeric(y),
                      n_pcs = n_pcs, reps = reps, lambda = lambda)
  structure(c(fit, list(gnn_fit = gnn_fit, query_type = "graph_node")),
             class = c("edaphos_qf_krr_gat", class(fit)))
}

#' @export
predict.edaphos_qf_krr_gat <- function(object, ...) {
  # When no newdata is supplied, predict at training embeddings
  dots <- list(...)
  if (length(dots) == 0L) {
    return(stats::predict(unclass_to_qf(object),
                             newdata = object$gnn_fit$emb))
  }
  stats::predict(unclass_to_qf(object), ...)
}

unclass_to_qf <- function(x) {
  class(x) <- setdiff(class(x), "edaphos_qf_krr_gat")
  x
}

#' @export
print.edaphos_qf_krr_gat <- function(x, ...) {
  cat("<edaphos_qf_krr_gat>  (Pilar 6 x Pilar 10)\n")
  cat(sprintf("  GAT emb_dim   : %d\n", ncol(x$gnn_fit$emb)))
  cat(sprintf("  qubits (PCs)  : %d\n", x$n_pcs))
  cat(sprintf("  reps          : %d   lambda = %.3g\n",
               x$reps, x$lambda))
  cat(sprintf("  n_train       : %d\n", x$n_train))
  invisible(x)
}

# ---- helpers --------------------------------------------------------------

# Extract (lambda0, mu, y_inf, y0) from either class of ODE fit, falling
# back to mild defaults when a field is missing.
.piml_extract_params <- function(ode_fit) {
  if (inherits(ode_fit, "edaphos_piml_profile") &&
      is.list(ode_fit$params)) {
    return(list(
      lambda0 = ode_fit$params$lambda0 %||% 0.01,
      mu      = ode_fit$params$mu      %||% 0,
      y_inf   = ode_fit$params$y_inf   %||% 0,
      y0      = ode_fit$params$y0      %||% 0
    ))
  }
  if (inherits(ode_fit, "edaphos_piml_bayes") &&
      is.list(ode_fit$map)) {
    return(list(
      lambda0 = ode_fit$map$lambda0 %||% 0.01,
      mu      = ode_fit$map$mu      %||% 0,
      y_inf   = ode_fit$map$y_inf   %||% 0,
      y0      = ode_fit$map$y0      %||% 0
    ))
  }
  # Fallback: allow a plain mock list with flat fields (useful in tests).
  list(
    lambda0 = ode_fit$lambda0 %||% 0.01,
    mu      = ode_fit$mu      %||% 0,
    y_inf   = ode_fit$y_inf   %||% 0,
    y0      = ode_fit$y0      %||% 0
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a
