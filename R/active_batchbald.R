# Pillar 5 -- BatchBALD acquisition for regression.
#
# The hybrid `al_query(strategy = "hybrid")` scoring weighs QRF
# prediction-interval width against standardised feature-space
# distance -- a well-tuned heuristic but a heuristic. BatchBALD
# (Kirsch, van Amersfoort and Gal 2019) formalises "pick the batch
# that maximises mutual information with the model parameters" as a
# principled information-theoretic objective:
#
#     BatchBALD(B) = I(y_{B} ; theta | x_{B}, D)
#                  = H[y_{B} | x_{B}, D] - E_theta[ H[y_{B} | x_{B}, theta] ].
#
# For a regression model whose aleatoric noise is Gaussian with
# variance sigma_a^2, independent of theta, and whose epistemic
# posterior over the mean function is characterised by T sampled
# parameter draws f_theta^{(1)}, ..., f_theta^{(T)}, the conditional
# entropy term is a constant and the objective reduces to a log-det:
#
#     BatchBALD(B) propto 1/2 * log det( Cov_theta( f_theta(B) )
#                                       + sigma_a^2 I_{|B|} ).
#
# Cov_theta( f_theta(B) ) is the T-sample empirical covariance across
# the T parameter draws. For a Quantile Regression Forest (Meinshausen
# 2006) the trees *are* the T draws: `ranger::predict(...,
# predict.all = TRUE)$predictions` returns an n_pool-by-T matrix whose
# row-wise empirical covariance is exactly the quantity we need.
#
# Because the log-det is monotone submodular in B, greedy selection
# achieves a (1 - 1/e) approximation of the optimum (Nemhauser, Wolsey
# and Fisher 1978), which is the same guarantee enjoyed by the wider
# active-learning literature on diverse batch selection.
#
# ----- incremental Cholesky log-det update -----------------------------
#
# Re-factorising an m-by-m PSD matrix at every candidate inside a
# greedy loop is O(m^3 * n_pool) per step. We avoid that with the
# standard Schur-complement / Cholesky-update trick: if L is the
# Cholesky of the current Sigma_B, adding a candidate x* with
# cross-covariance column c and self-variance v produces
#
#     Sigma_{B ∪ x*} = [ [Sigma_B,  c],
#                         [c',      v + sigma_a^2 ] ].
#
# Using l* = solve(L, c) and d* = sqrt(v + sigma_a^2 - sum(l*^2)),
# the new log-det increment is 2 * log(d*). So evaluating every
# candidate in a greedy step is O(m^2 * n_pool) after the initial
# O(n_pool * T) covariance-row computation is cached.

# --- per-tree prediction extraction ------------------------------------

.batchbald_tree_preds <- function(model, X) {
  # Returns an n_pool-by-T matrix of tree-wise predictions. `model` is
  # the `edaphos_al_model`'s inner `ranger::ranger` object.
  preds_all <- stats::predict(
    model, data = as.data.frame(X), predict.all = TRUE
  )$predictions
  # ranger returns (n_pool x num.trees) for regression.
  if (!is.matrix(preds_all)) {
    preds_all <- matrix(preds_all, nrow = nrow(X))
  }
  preds_all
}

# Aleatoric noise variance estimate from the ensemble residuals on the
# training data. We use the OOB residual if available (ranger exposes
# it), otherwise the in-sample residual.
.batchbald_aleatoric_var <- function(al_model) {
  rg <- al_model$model
  oob <- tryCatch(stats::na.omit(rg$predictions), error = function(e) NULL)
  y_train <- al_model$labeled[[al_model$target]]
  if (!is.null(oob) && length(oob) == length(y_train)) {
    stats::var(y_train - oob)
  } else {
    in_sample <- stats::predict(rg, data = al_model$labeled)$predictions
    stats::var(y_train - in_sample)
  }
}

# --- greedy BatchBALD selection ----------------------------------------

.batchbald_greedy <- function(tree_preds, sigma_a2, n_select) {
  # tree_preds: n_pool x T matrix of tree-wise predictions.
  # sigma_a2  : scalar aleatoric variance.
  # n_select  : batch size.
  #
  # Returns a length-n_select integer vector of chosen row indices.
  n_pool <- nrow(tree_preds)
  T_draws <- ncol(tree_preds)

  # Centre each row so cov is computed around the posterior-mean
  # function; this is what Lin, Zhu and Sugiyama (2022) call the
  # "centred BatchBALD" estimator, which is numerically more stable
  # than the raw quadratic form when T is moderate.
  row_means <- rowMeans(tree_preds)
  P <- tree_preds - row_means  # n_pool x T, row-centred

  # Diagonal (per-point epistemic + aleatoric variance).
  diag_var <- rowSums(P^2) / (T_draws - 1L) + sigma_a2

  # Cache for incremental Cholesky: selected indices, their L factor
  # and the already-selected submatrix of P (rows of P).
  selected <- integer(0)
  L        <- matrix(0, 0, 0)
  P_sel    <- matrix(0, 0, T_draws)
  available <- seq_len(n_pool)

  for (step in seq_len(n_select)) {
    if (length(available) == 0L) break
    if (length(selected) == 0L) {
      # Initial step: the score for a single point is
      # 0.5 * log(var(x) + sigma_a^2), i.e. the ordinary BALD score
      # (modulo a 0.5 log sigma_a^2 constant we drop).
      scores <- diag_var[available]
      best_k <- which.max(scores)
      idx <- available[best_k]
      L <- matrix(sqrt(diag_var[idx]), 1, 1)
    } else {
      # Cross-covariance between each candidate x* and the already-
      # selected batch: c_k = P_sel %*% P[x*, ] / (T - 1).
      C <- (P_sel %*% t(P[available, , drop = FALSE])) / (T_draws - 1L)
      # For each candidate compute l* = solve(L, c) and d* via
      # Schur complement.
      L_inv_c <- forwardsolve(L, C)
      new_var <- diag_var[available] -
                 colSums(L_inv_c^2)
      # Guard against numerical negative variances (rare but possible).
      new_var <- pmax(new_var, 1e-12)
      # The incremental log-det increment is log(new_var) (base e).
      # We just want the argmax; the outer 0.5 factor is monotone.
      best_k <- which.max(new_var)
      idx <- available[best_k]
      # Update the Cholesky factor.
      l_star <- L_inv_c[, best_k, drop = TRUE]
      d_star <- sqrt(new_var[best_k])
      L <- rbind(
        cbind(L, rep(0, nrow(L))),
        c(l_star, d_star)
      )
    }
    selected  <- c(selected, idx)
    P_sel     <- rbind(P_sel, P[idx, , drop = TRUE])
    available <- setdiff(available, idx)
  }
  selected
}

# --- public entry point -------------------------------------------------

#' BatchBALD information-theoretic batch acquisition
#'
#' Selects an **information-theoretically optimal batch** of Active
#' Learning queries from a pool of candidates, following Kirsch,
#' van Amersfoort and Gal 2019 (see the @references section below).
#' Unlike the top-`n` BALD strategy (which
#' repeatedly picks the single most uncertain candidate and therefore
#' tends to select *n* copies of "the same question" on clustered
#' pools), BatchBALD optimises the joint mutual information between
#' the *batch* \eqn{y_B = (y_{x_1}, \ldots, y_{x_n})} and the model
#' parameters:
#'
#' \deqn{
#'   \mathrm{BatchBALD}(B) \;=\;
#'     I\bigl(y_B ; \theta \mid x_B, \mathcal D\bigr).
#' }
#'
#' For a regression model with Gaussian aleatoric noise of variance
#' \eqn{\sigma_a^2} and an epistemic posterior represented by `T`
#' parameter draws \eqn{f_\theta^{(1)}, \ldots, f_\theta^{(T)}}, the
#' objective reduces to a log-determinant [see the source comment at
#' the top of `R/active_batchbald.R` for the derivation]:
#'
#' \deqn{
#'   \mathrm{BatchBALD}(B) \;\propto\;
#'   \tfrac{1}{2}\log\det\!\bigl(
#'     \mathrm{Cov}_\theta\bigl(f_\theta(B)\bigr) + \sigma_a^2 I_{|B|}
#'   \bigr).
#' }
#'
#' For a Quantile Regression Forest
#' (which is what `al_fit()` produces) the trees themselves are the
#' `T` parameter draws, so the joint covariance is just the per-tree
#' empirical covariance across candidates. The greedy selection
#' inherits the \eqn{(1 - 1/e)}-optimality guarantee of submodular
#' maximisation (Nemhauser, Wolsey and Fisher 1978) and is implemented via
#' Schur-complement / Cholesky updates so every greedy step is
#' \eqn{O(m^2 n_\mathrm{pool})} rather than \eqn{O(m^3 n_\mathrm{pool})}.
#'
#' This is a **complement** to [al_query()], not a replacement: the
#' hybrid uncertainty + diversity strategy there remains the default
#' for low-budget settings where a physical-distance term is needed.
#' Use BatchBALD when (a) the covariate pool contains clusters of
#' near-duplicate candidates and top-`n` BALD would select all of
#' them, (b) the QRF aleatoric noise is well-estimated, and (c) the
#' batch size is moderate (`n <= 50` for laptop-scale pools of up to
#' ~10 000 candidates).
#'
#' @param model A `edaphos_al_model` from [al_fit()] or [al_loop()].
#'   The underlying `ranger::ranger` object must have been trained
#'   with `keep.inbag = TRUE` (default in `al_fit()`), so that
#'   per-tree predictions are available via
#'   `predict(..., predict.all = TRUE)`.
#' @param candidates Data frame of unlabelled candidates. Must
#'   contain the covariates listed in `model$covariates`.
#' @param n Integer — batch size.
#' @param sigma_a2 Optional numeric — aleatoric noise variance
#'   \eqn{\sigma_a^2}. When `NULL` (default), estimated from the
#'   out-of-bag residuals of the fitted forest.
#' @param physics_gate Optional function
#'   `function(candidates, predicted_mean) -> logical`. See
#'   [al_query()].
#' @return Integer vector of row indices in `candidates` that form
#'   the selected batch, in greedy-selection order (the first index
#'   is the highest-BALD single point; each subsequent index is the
#'   point that maximally increases the joint log-determinant given
#'   the previously selected batch).
#' @seealso [al_query()] for uncertainty-plus-diversity acquisition;
#'   [al_fit()] for the QRF backbone.
#' @references
#' Kirsch, A., van Amersfoort, J. and Gal, Y. (2019). BatchBALD:
#' Efficient and diverse batch acquisition for deep Bayesian active
#' learning. *NeurIPS 32*, 7024–7035.
#'
#' Meinshausen, N. (2006). Quantile regression forests. *Journal of
#' Machine Learning Research* **7**, 983–999.
#'
#' Nemhauser, G. L., Wolsey, L. A. and Fisher, M. L. (1978). An
#' analysis of approximations for maximizing submodular set functions
#' — I. *Mathematical Programming* **14**, 265–294.
#' @examples
#' \dontrun{
#'   al <- al_initial_design(br_cerrado, c("elev","slope","twi"),
#'                            n = 20L, seed = 1L)
#'   fit <- al_fit(al, target = "soc")
#'   pool <- br_cerrado[setdiff(seq_len(nrow(br_cerrado)), al$idx), ]
#'   batch <- al_query_batchbald(fit, pool, n = 10L)
#' }
#' @export
al_query_batchbald <- function(model, candidates, n = 5L,
                                 sigma_a2 = NULL,
                                 physics_gate = NULL) {
  if (!inherits(model, "edaphos_al_model")) {
    stop("`model` must be a `edaphos_al_model` (from al_fit / al_loop).",
         call. = FALSE)
  }
  stopifnot(is.numeric(n), length(n) == 1L, n >= 1L)
  n <- as.integer(n)
  covs <- model$covariates
  .assert_covariates(candidates, covs)

  ok <- stats::complete.cases(candidates[, covs, drop = FALSE])
  if (!any(ok)) {
    stop("No candidate row has complete covariates.", call. = FALSE)
  }
  cand_ok <- candidates[ok, , drop = FALSE]
  orig_idx <- which(ok)

  # physics gate ----------------------------------------------------------
  if (!is.null(physics_gate)) {
    if (!is.function(physics_gate)) {
      stop("`physics_gate` must be a function or NULL.", call. = FALSE)
    }
    pred_mean <- stats::predict(
      model$model, data = cand_ok[, covs, drop = FALSE]
    )$predictions
    gate_mask <- physics_gate(cand_ok, pred_mean)
    if (!is.logical(gate_mask) || length(gate_mask) != nrow(cand_ok)) {
      stop("`physics_gate(candidates, predicted_mean)` must return a ",
           "logical vector of length nrow(candidates).", call. = FALSE)
    }
    if (!any(gate_mask)) {
      stop("`physics_gate` rejected every candidate; loosen the gate.",
           call. = FALSE)
    }
    cand_ok <- cand_ok[gate_mask, , drop = FALSE]
    orig_idx <- orig_idx[gate_mask]
  }

  n <- min(n, nrow(cand_ok))
  if (n < 1L) return(integer(0))

  # per-tree predictions + aleatoric variance -----------------------------
  tree_preds <- .batchbald_tree_preds(model$model,
                                        cand_ok[, covs, drop = FALSE])
  if (is.null(sigma_a2)) {
    sigma_a2 <- max(.batchbald_aleatoric_var(model), 1e-8)
  }
  sigma_a2 <- as.numeric(sigma_a2)
  if (!is.finite(sigma_a2) || sigma_a2 < 0) {
    stop("`sigma_a2` must be a non-negative finite number.",
         call. = FALSE)
  }

  sel_local <- .batchbald_greedy(tree_preds, sigma_a2, n)
  orig_idx[sel_local]
}
