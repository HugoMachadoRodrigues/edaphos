# Pillar 1 adapter to the unified v1.6.0 uncertainty API.
#
# `causal_estimate_effect()` produces a point estimate plus either an
# asymptotic CI (for the LM estimator) or a BART posterior sample
# (for the BART estimator). The v1.6.0 design requires every pillar
# to expose a sample-based posterior over the same quantity, so that
# `uncertainty_calibrate()` and `autoplot()` work uniformly.
#
# For Pillar 1 this means two helpers:
#
#   causal_effect_bootstrap(data, ..., B = 200L)
#     -- block-bootstrap by a user-supplied cluster column (the
#        established default on the v1.4.0 Cerrado pipeline). Returns
#        a length-B vector of direct-effect estimates.
#
#   causal_effect_posterior(data, ..., B = 500L)
#     -- high-level wrapper that runs the right posterior engine
#        (bootstrap for LM, BART posterior for BART) and returns an
#        `edaphos_posterior`.
#
# We also register an `as_edaphos_posterior.edaphos_causal_effect`
# method that adapts a `causal_estimate_effect()` return value
# directly when the bootstrap or BART draws are already attached.

#' Block-bootstrap the backdoor-adjusted direct effect
#'
#' Resamples clusters (not rows) with replacement and refits the
#' adjusted OLS on each resample, returning the vector of direct-effect
#' coefficients. When the clustering structure is k-means on `(lon,
#' lat)` (as in the Cerrado pipeline from v1.4.0 onward), this produces
#' spatial-clustering-aware confidence intervals that the asymptotic
#' `confint(lm)` interval ignores.
#'
#' @param data A data frame with the exposure, outcome, adjustment
#'   columns and a cluster-id column.
#' @param dag A `dagitty` DAG (only used when `adjustment` is `NULL`).
#' @param exposure,outcome Character; column names.
#' @param adjustment Character vector of adjustment-set column names
#'   (defaults to the minimal set from the DAG).
#' @param cluster Character; name of the cluster-id column in `data`.
#' @param B Integer; number of bootstrap resamples. Defaults to `500L`.
#' @param effect One of `"direct"`, `"total"` (passed to the adjustment
#'   set resolver when `adjustment = NULL`).
#' @param seed Optional integer for reproducibility.
#' @return Numeric vector of length `B` with one direct-effect estimate
#'   per bootstrap resample.
#' @export
causal_effect_bootstrap <- function(data, dag, exposure, outcome,
                                      adjustment = NULL,
                                      cluster = "kmeans_cluster",
                                      B = 500L,
                                      effect = c("direct", "total"),
                                      seed = NULL) {
  effect <- match.arg(effect)
  stopifnot(is.data.frame(data),
            is.character(exposure), length(exposure) == 1L,
            is.character(outcome),  length(outcome)  == 1L,
            is.character(cluster),  length(cluster)  == 1L)
  if (is.null(data[[cluster]])) {
    stop(sprintf("Cluster column `%s` not found in `data`.", cluster),
         call. = FALSE)
  }
  if (is.null(adjustment)) {
    .causal_require_dagitty()
    adjustment <- causal_adjustment_set(dag, exposure, outcome,
                                          effect = effect)
    if (is.null(adjustment)) {
      stop("Effect is not identifiable from the supplied DAG.",
           call. = FALSE)
    }
  }
  if (!is.null(seed)) set.seed(seed)

  clusters_all <- data[[cluster]]
  unique_clusters <- unique(clusters_all)
  terms <- unique(c(exposure, adjustment))
  form  <- stats::reformulate(terms, response = outcome)
  out   <- numeric(B)
  for (b in seq_len(B)) {
    resampled <- sample(unique_clusters, replace = TRUE)
    ix <- unlist(lapply(resampled, function(k) which(clusters_all == k)),
                  use.names = FALSE)
    fit <- stats::lm(form, data = data[ix, , drop = FALSE])
    out[b] <- unname(stats::coef(fit)[exposure])
  }
  out
}

#' Posterior distribution of a backdoor-adjusted direct effect
#'
#' Unified v1.6.0 entry point for Pillar 1. Returns an
#' [`edaphos_posterior()`] with posterior draws over the identified
#' direct effect, ready for [`uncertainty_calibrate()`] and
#' [`autoplot()`]. For the LM estimator the draws are a
#' cluster-block bootstrap; for BART the draws are the native Markov-
#' chain posterior.
#'
#' @param data A data frame.
#' @param dag A `dagitty` DAG (required when `adjustment = NULL`).
#' @param exposure,outcome Character; column names.
#' @param adjustment Optional character vector of adjustment-set
#'   columns; derived from the DAG if `NULL`.
#' @param estimator `"lm"` or `"bart"`.
#' @param cluster,B,seed See [`causal_effect_bootstrap()`]; only used
#'   for the LM estimator.
#' @param bart_kwargs Named list of extra arguments forwarded to
#'   `dbarts::bart()` when `estimator = "bart"`.
#' @param delta Numeric; counterfactual increment for the BART
#'   estimator (defaults to `IQR(exposure) / 2`).
#' @param units Optional character; free-text tag passed through to
#'   the `edaphos_posterior`.
#' @return An `edaphos_posterior` with `query_type = "effect"` and
#'   `method` set to `"bootstrap"` (LM) or `"bayesian"` (BART).
#' @export
causal_effect_posterior <- function(data, dag, exposure, outcome,
                                      adjustment = NULL,
                                      estimator = c("lm", "bart"),
                                      cluster = "kmeans_cluster",
                                      B = 500L, seed = NULL,
                                      bart_kwargs = list(),
                                      delta = NULL,
                                      units = NULL) {
  estimator <- match.arg(estimator)

  if (estimator == "lm") {
    draws <- causal_effect_bootstrap(
      data       = data, dag = dag,
      exposure   = exposure, outcome = outcome,
      adjustment = adjustment, cluster = cluster,
      B = B, seed = seed
    )
    return(edaphos_posterior(
      samples    = matrix(draws, ncol = 1L),
      method     = "bootstrap",
      query_type = "effect",
      units      = units,
      metadata   = list(exposure = exposure, outcome = outcome,
                         adjustment = adjustment,
                         estimator = "lm", cluster = cluster, B = B)
    ))
  }

  # BART: run the estimator, harvest its built-in posterior sample.
  if (!requireNamespace("dbarts", quietly = TRUE)) {
    stop("Install the `dbarts` package to use estimator = \"bart\".",
         call. = FALSE)
  }
  fit <- causal_estimate_effect(
    data = data, dag = dag,
    exposure = exposure, outcome = outcome,
    adjustment = adjustment, effect = "direct",
    estimator = "bart", delta = delta, bart_kwargs = bart_kwargs
  )
  edaphos_posterior(
    samples    = matrix(fit$posterior, ncol = 1L),
    method     = "bayesian",
    query_type = "effect",
    units      = units,
    metadata   = list(exposure = exposure, outcome = outcome,
                       adjustment = fit$adjustment,
                       estimator = "bart", delta = fit$delta)
  )
}

#' @export
as_edaphos_posterior.edaphos_causal_effect <- function(x,
                                                         units = NULL,
                                                         ...) {
  # Prefer the block-bootstrap draws (post-hoc LM) when present,
  # else fall back to the BART posterior, else synthesise a Gaussian
  # shortcut from the asymptotic CI.
  if (!is.null(x$effect_boot)) {
    return(edaphos_posterior(
      samples    = matrix(as.numeric(x$effect_boot), ncol = 1L),
      method     = "bootstrap",
      query_type = "effect",
      units      = units,
      metadata   = list(exposure = x$exposure, outcome = x$outcome,
                         adjustment = x$adjustment,
                         estimator = x$estimator)
    ))
  }
  if (!is.null(x$posterior)) {
    return(edaphos_posterior(
      samples    = matrix(as.numeric(x$posterior), ncol = 1L),
      method     = "bayesian",
      query_type = "effect",
      units      = units,
      metadata   = list(exposure = x$exposure, outcome = x$outcome,
                         adjustment = x$adjustment,
                         estimator = x$estimator)
    ))
  }
  # Gaussian shortcut from `effect` + asymptotic `effect_ci`.
  if (!is.null(x$effect) && !is.null(x$effect_ci) &&
      length(x$effect_ci) >= 2L) {
    mu    <- as.numeric(x$effect)
    sigma <- (as.numeric(x$effect_ci)[2L] -
                 as.numeric(x$effect_ci)[1L]) / (2 * stats::qnorm(0.975))
    return(edaphos_posterior(
      mean       = mu,
      sd         = sigma,
      method     = "analytic",
      query_type = "effect",
      units      = units,
      metadata   = list(exposure = x$exposure, outcome = x$outcome,
                         adjustment = x$adjustment,
                         estimator = x$estimator,
                         note = "Gaussian shortcut from asymptotic LM CI")
    ))
  }
  stop("`edaphos_causal_effect` carries neither bootstrap nor posterior draws.",
       call. = FALSE)
}
