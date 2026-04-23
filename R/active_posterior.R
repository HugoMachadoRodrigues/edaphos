# Pillar 5 adapter to the unified v1.6.0 uncertainty API.
#
# The Pillar 5 `al_fit()` uses a Quantile Regression Forest (Meinshausen
# 2006), which natively delivers a full conditional distribution of
# the target at every candidate location. The existing `al_query()`
# consumes the (q_lower, q_upper) summary; v1.6.0 surfaces the full
# per-cell distribution through `edaphos_posterior` and calibrate().

#' Posterior predictive distribution of an edaphos Active-Learning fit
#'
#' Samples the conditional distribution of the target at every row of
#' `candidates` by asking the underlying Quantile Regression Forest
#' (ranger) for a grid of quantiles. The returned
#' `edaphos_posterior` carries those quantile samples directly, so
#' [`uncertainty_calibrate()`] and [`autoplot()`] work without changes.
#'
#' @param model An `edaphos_al_model` produced by [`al_fit()`].
#' @param newdata A data frame with (at least) the columns used as
#'   covariates at fit time.
#' @param n_quantiles Integer; size of the equally-spaced grid of
#'   quantiles to request from the QRF. Defaults to `99L` (1 % to
#'   99 % in 1 % steps, which is a reasonable trade-off between a
#'   smooth empirical CDF and `ranger::predict()` cost).
#' @param units Optional free-text units tag.
#' @return An `edaphos_posterior` with `method = "ensemble"` (the QRF
#'   conditional distribution being itself an ensemble over tree
#'   leaves) and `query_type = "sample"`.
#' @references
#' Meinshausen, N. (2006). Quantile regression forests. *Journal of
#' Machine Learning Research* **7**, 983-999.
#' @export
active_learning_posterior <- function(model, newdata,
                                        n_quantiles = 99L,
                                        units = NULL) {
  stopifnot(inherits(model, "edaphos_al_model"))
  if (!requireNamespace("ranger", quietly = TRUE)) {
    stop("The `ranger` package is required for active_learning_posterior().",
         call. = FALSE)
  }
  covs <- model$covariates
  .assert_covariates(newdata, covs)
  ok <- stats::complete.cases(newdata[, covs, drop = FALSE])
  cand <- newdata[ok, covs, drop = FALSE]

  n_q <- as.integer(n_quantiles)
  stopifnot(n_q >= 5L)
  probs <- seq(from = 1 / (n_q + 1L),
                to   = n_q / (n_q + 1L),
                length.out = n_q)
  q_matrix <- stats::predict(
    model$model,
    data      = cand,
    type      = "quantiles",
    quantiles = probs
  )$predictions
  # q_matrix is (n_cand, n_q). We treat every quantile as an
  # equally-weighted sample from the conditional distribution.
  samples <- t(q_matrix)                         # (n_q, n_cand)
  edaphos_posterior(
    samples    = samples,
    method     = "ensemble",
    query_type = "sample",
    units      = units,
    metadata   = list(target = model$target,
                       covariates = covs,
                       n_quantiles = n_q,
                       n_candidates = nrow(cand),
                       source = "al_fit (ranger QRF)")
  )
}

#' @export
as_edaphos_posterior.edaphos_al_model <- function(x, newdata = NULL,
                                                     n_quantiles = 99L,
                                                     units = NULL, ...) {
  if (is.null(newdata)) {
    stop("Supply `newdata = ...` to adapt an AL model.", call. = FALSE)
  }
  active_learning_posterior(x, newdata = newdata,
                              n_quantiles = n_quantiles, units = units)
}
