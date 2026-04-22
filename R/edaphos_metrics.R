# Honest, publication-grade metrics for supervised digital-soil-mapping
# benchmarks. Every metric in this file was chosen for a specific
# rhetorical job in the case-study vignette:
#
#   * edaphos_rmse()        point-forecast accuracy (classical).
#   * edaphos_mae()         point-forecast robustness to outliers.
#   * edaphos_r2()          fraction of variance explained relative to
#                           the unconditional mean (Nash-Sutcliffe
#                           efficiency when the mean is the trivial
#                           model).
#   * edaphos_bias()        systematic error.
#   * edaphos_picp()        prediction-interval coverage probability
#                           (Shrestha and Solomatine 2006) -- the
#                           honest probe for whether the reported
#                           intervals are calibrated.
#   * edaphos_interval_score()  the negatively-oriented proper
#                           scoring rule of Gneiting and Raftery
#                           (2007) combining sharpness and calibration.
#   * edaphos_ece()         expected calibration error for a K-bin
#                           reliability diagram.
#
# All functions expect numeric vectors. NA values in `observed` or
# `predicted` are dropped pairwise unless explicitly noted.

.metrics_drop_na <- function(observed, predicted) {
  ok <- is.finite(observed) & is.finite(predicted)
  list(obs = observed[ok], pred = predicted[ok], n = sum(ok))
}

#' Root-mean-square error
#'
#' \eqn{\mathrm{RMSE} = \sqrt{\frac{1}{n} \sum_i (y_i - \hat y_i)^2}}.
#'
#' @param observed Numeric vector of observed values.
#' @param predicted Numeric vector of predicted values.
#' @return Non-negative numeric scalar.
#' @export
edaphos_rmse <- function(observed, predicted) {
  d <- .metrics_drop_na(observed, predicted)
  if (d$n == 0L) return(NA_real_)
  sqrt(mean((d$obs - d$pred)^2))
}

#' Mean absolute error
#'
#' @param observed,predicted Numeric vectors.
#' @return Non-negative numeric scalar.
#' @export
edaphos_mae <- function(observed, predicted) {
  d <- .metrics_drop_na(observed, predicted)
  if (d$n == 0L) return(NA_real_)
  mean(abs(d$obs - d$pred))
}

#' Coefficient of determination (Nash-Sutcliffe efficiency)
#'
#' \eqn{R^2 = 1 - \frac{\sum (y - \hat y)^2}{\sum (y - \bar y)^2}}.
#' Ranges from \eqn{-\infty} to 1; negative values mean the predictor
#' is worse than the unconditional mean.
#' @param observed,predicted Numeric vectors.
#' @return Numeric scalar.
#' @export
edaphos_r2 <- function(observed, predicted) {
  d <- .metrics_drop_na(observed, predicted)
  if (d$n <= 1L) return(NA_real_)
  ss_res <- sum((d$obs - d$pred)^2)
  ss_tot <- sum((d$obs - mean(d$obs))^2)
  if (ss_tot == 0) return(NA_real_)
  1 - ss_res / ss_tot
}

#' Mean bias (observed minus predicted)
#'
#' Positive = prediction under-estimates the target; negative = over-
#' estimate.
#' @param observed,predicted Numeric vectors.
#' @return Numeric scalar.
#' @export
edaphos_bias <- function(observed, predicted) {
  d <- .metrics_drop_na(observed, predicted)
  if (d$n == 0L) return(NA_real_)
  mean(d$obs - d$pred)
}

#' Prediction-interval coverage probability (PICP)
#'
#' Fraction of test points whose observed value falls inside the
#' `[lower, upper]` prediction interval. For a well-calibrated
#' interval the PICP should equal the nominal level
#' (e.g. 0.95 for a 95% interval).
#'
#' @param observed Numeric vector.
#' @param lower,upper Numeric vectors of the same length giving the
#'   lower and upper bounds of the prediction interval at each point.
#' @return Numeric scalar in `[0, 1]`.
#' @references
#' Shrestha, D. L. and Solomatine, D. P. (2006). Machine learning
#' approaches for estimation of prediction interval for the model
#' output. *Neural Networks* **19**, 225-235.
#' @export
edaphos_picp <- function(observed, lower, upper) {
  stopifnot(length(observed) == length(lower),
            length(observed) == length(upper))
  ok <- is.finite(observed) & is.finite(lower) & is.finite(upper)
  if (!any(ok)) return(NA_real_)
  mean(lower[ok] <= observed[ok] & observed[ok] <= upper[ok])
}

#' Interval score (Gneiting and Raftery 2007)
#'
#' Proper scoring rule balancing sharpness (narrower intervals score
#' better) against calibration (penalising intervals that miss the
#' observed value). Lower is better.
#'
#' \deqn{IS_\alpha = (u - \ell) + \frac{2}{\alpha}(\ell - y) \mathbb 1\{y < \ell\}
#'                  + \frac{2}{\alpha}(y - u) \mathbb 1\{y > u\}.}
#'
#' @param observed,lower,upper Numeric vectors.
#' @param alpha Nominal miscoverage level (1 - nominal PICP). Default
#'   `0.05` for a 95% prediction interval.
#' @return Non-negative numeric scalar (mean over the test set).
#' @references
#' Gneiting, T. and Raftery, A. E. (2007). Strictly proper scoring
#' rules, prediction, and estimation. *Journal of the American
#' Statistical Association* **102**(477), 359-378.
#' @export
edaphos_interval_score <- function(observed, lower, upper, alpha = 0.05) {
  stopifnot(length(observed) == length(lower),
            length(observed) == length(upper),
            alpha > 0, alpha < 1)
  ok <- is.finite(observed) & is.finite(lower) & is.finite(upper)
  if (!any(ok)) return(NA_real_)
  y <- observed[ok]; l <- lower[ok]; u <- upper[ok]
  width   <- u - l
  pen_lo  <- (2 / alpha) * pmax(l - y, 0)
  pen_hi  <- (2 / alpha) * pmax(y - u, 0)
  mean(width + pen_lo + pen_hi)
}

#' Expected calibration error (ECE) for a regression reliability diagram
#'
#' Bins predictions by their predicted quantile, then within each bin
#' compares the empirical miscoverage rate to the nominal level.
#' Lower is better; 0 = perfect calibration.
#'
#' For each quantile level \eqn{q_k = k / K} we compute the fraction
#' of test points whose observed value is below the predicted
#' \eqn{q_k} quantile and compare to the nominal level.
#'
#' @param observed Numeric vector.
#' @param predicted_quantiles A numeric matrix with one column per
#'   nominal quantile level in `quantile_levels`.
#' @param quantile_levels Numeric vector in `(0, 1)` giving the
#'   nominal level of each column of `predicted_quantiles`.
#' @return Numeric scalar (mean of per-level absolute calibration
#'   errors).
#' @export
edaphos_ece <- function(observed, predicted_quantiles, quantile_levels) {
  stopifnot(is.numeric(observed),
            is.matrix(predicted_quantiles),
            length(quantile_levels) == ncol(predicted_quantiles))
  ok <- is.finite(observed) &
        apply(predicted_quantiles, 1L, function(r) all(is.finite(r)))
  if (!any(ok)) return(NA_real_)
  y <- observed[ok]
  q <- predicted_quantiles[ok, , drop = FALSE]
  levels <- as.numeric(quantile_levels)
  errs <- vapply(seq_along(levels), function(k) {
    emp <- mean(y <= q[, k])
    abs(emp - levels[k])
  }, numeric(1L))
  mean(errs)
}

#' Summarise a pointwise + interval prediction against observations
#'
#' Convenience wrapper returning a one-row data frame with RMSE, MAE,
#' R2, bias, PICP and the interval score at the stated level. Used as
#' the row-per-method aggregator in the case-study benchmark table.
#'
#' @param observed Numeric vector.
#' @param predicted Numeric vector (point estimate).
#' @param lower,upper Optional numeric vectors with the interval
#'   bounds. When `NULL` the PICP and interval-score columns are
#'   returned as `NA`.
#' @param interval Nominal coverage of `[lower, upper]`; default 0.95.
#' @param method Character label written into the `method` column.
#' @return A one-row data frame.
#' @export
edaphos_metrics_summary <- function(observed, predicted,
                                      lower = NULL, upper = NULL,
                                      interval = 0.95,
                                      method   = "unnamed") {
  data.frame(
    method           = as.character(method),
    n                = sum(is.finite(observed) & is.finite(predicted)),
    rmse             = edaphos_rmse(observed, predicted),
    mae              = edaphos_mae(observed, predicted),
    r2               = edaphos_r2(observed, predicted),
    bias             = edaphos_bias(observed, predicted),
    picp             = if (!is.null(lower) && !is.null(upper))
                         edaphos_picp(observed, lower, upper) else NA_real_,
    interval_score   = if (!is.null(lower) && !is.null(upper))
                         edaphos_interval_score(
                           observed, lower, upper,
                           alpha = 1 - interval
                         ) else NA_real_,
    stringsAsFactors = FALSE
  )
}
