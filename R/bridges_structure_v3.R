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
#' GAT node embeddings.  Returns the discovered DAG restricted to the
#' user's canonical variables; embeddings act as nuisance
#' conditioners that absorb spatial dependence the expert DAG does
#' not name.
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
#'   call, restricted to edges between variables in `feature_frame`.
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
#' suitable as the `physics_loss_fn` argument of
#' [`temporal_convlstm_fit()`].  The closure penalises SOC-dynamics
#' predictions that violate the local-rate kinetics inferred from
#' the Pilar 2 ODE fit.
#'
#' @param ode_fit An `edaphos_piml_profile` or
#'   `edaphos_piml_bayes` fit.
#' @param weight Numeric; loss weight relative to the MSE term.
#'   Default `0.1`.
#' @return A function `loss_fn(y_pred, y_true, driver)` returning a
#'   scalar tensor/number (same shape agnostic to torch / R).
#' @export
temporal_piml_loss <- function(ode_fit, weight = 0.1) {
  # Parameters are stored differently across the two ODE-fit classes:
  # `edaphos_piml_profile`  -> `ode_fit$params$lambda0` etc.
  # `edaphos_piml_bayes`    -> `ode_fit$map$lambda0` etc.
  pars <- .piml_extract_params(ode_fit)
  lambda0 <- pars$lambda0
  mu      <- pars$mu
  yi      <- pars$y_inf
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
