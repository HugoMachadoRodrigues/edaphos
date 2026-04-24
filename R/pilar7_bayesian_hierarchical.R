# Pilar 7 -- Bayesian hierarchical spatial models (v2.3.0 scope).
#
# Status: SCAFFOLD.  This file ships as the v2.1.0 roadmap-anchor for
# the v2.3.0 release.  The function signatures and class structure
# below are stable; the method bodies call `stop("not yet
# implemented")` until the dedicated v2.3.0 session wires them up.
#
# Target scope for v2.3.0
# -----------------------
# A thin, edaphos_posterior-compatible wrapper over three backends:
#
#   (a) INLA  -- Bayesian SPDE models for spatially structured random
#                effects; by far the most common choice in modern DSM
#                (Poggio et al. 2021 SoilGrids, Malone et al. 2021).
#   (b) Stan  -- full-MCMC posterior over a Matern-like spatial GP
#                via the `brms` / `rstan` path.  Slower but
#                diagnostically transparent.
#   (c) spBayes -- MCMC for spatial Gaussian processes; useful when
#                the user does not have INLA binaries.
#
# The point of Pilar 7 in edaphos is NOT to reimplement any of these
# -- it is to:
#
#   1. Unify the `bhs_fit(data, formula, coords, backend, ...)` API
#      across the three backends;
#   2. Expose the posterior as an `edaphos_posterior` so
#      `uncertainty_calibrate()` compares BHS against Pilars 3/4/5
#      at par;
#   3. Ship a 1 095-WoSIS benchmark against the v1.3.1 ranger
#      baseline + the v1.6.0 unified calibration table so a
#      publication can see, finally, how classical hierarchical
#      geostatistics fares against edaphos's frontier pillars.
#
# TODO (v2.3.0)
# -------------
#  - [ ] Implement `bhs_fit(..., backend = "inla")`
#  - [ ] Implement `bhs_fit(..., backend = "stan")`
#  - [ ] Implement `bhs_fit(..., backend = "spBayes")`
#  - [ ] `predict.edaphos_bhs` with credible-interval output
#  - [ ] `as_edaphos_posterior.edaphos_bhs` method
#  - [ ] `data-raw/pilar7_bhs_benchmark.R` on 1 095 WoSIS profiles
#  - [ ] `vignettes/pilar7-bayesian-hierarchical.Rmd`

#' Fit a Bayesian hierarchical spatial model (scaffold, v2.3.0)
#'
#' @description
#' **Not yet implemented.**  Scheduled for v2.3.0.  The function
#' signature below is stable and may be called to inspect the planned
#' API; invoking it today raises an informative error.
#'
#' @param data Data frame with the response + covariates.
#' @param formula A `response ~ covariates` formula.
#' @param coords Character vector `c("lon", "lat")` giving the
#'   coordinate columns used to build the spatial random effect.
#' @param backend One of `"inla"` (default), `"stan"`, `"spBayes"`.
#' @param ... Forwarded to the chosen backend (priors, chains, etc.).
#' @return (When implemented) An `edaphos_bhs` S3 object carrying the
#'   fitted posterior, ready for `predict()` and
#'   `as_edaphos_posterior()`.
#' @export
bhs_fit <- function(data, formula, coords = c("lon", "lat"),
                      backend = c("inla", "stan", "spBayes"),
                      ...) {
  backend <- match.arg(backend)
  stop(
    "`bhs_fit()` is scheduled for edaphos v2.3.0 (Pilar 7 -- Bayesian\n",
    "hierarchical spatial models).  The API is fixed; the body will\n",
    "wire in INLA / Stan / spBayes in the dedicated v2.3.0 release.\n",
    "See R/pilar7_bayesian_hierarchical.R for the scope and TODO list.",
    call. = FALSE
  )
}
