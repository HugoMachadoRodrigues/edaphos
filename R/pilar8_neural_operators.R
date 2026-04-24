# Pilar 8 -- Neural operators (FNO, DeepONet) for pedogenetic PDEs
# (v2.4.0 scope).
#
# Status: SCAFFOLD.
#
# Why a pillar?
# -------------
# Pilar 2 (PIML) ships a *parametric* pedogenetic ODE + a Neural ODE
# solver.  Pilar 8 lifts that machinery one level: instead of fitting
# parameters for a single ODE, we LEARN THE OPERATOR that maps
# initial conditions + forcings to solution trajectories -- the
# infinite-dimensional generalisation that has transformed scientific
# ML in the last five years (Kovachki et al. 2023; Lu et al. 2021 for
# DeepONet; Li et al. 2021 for Fourier Neural Operator).
#
# Applied to pedometry, an FNO parameterises the solution operator of
#
#   dy/dz = f(z, y, x)        (the generic pedogenesis PDE)
#
# across *families* of covariate stacks.  It gives you zero-shot
# prediction at new sites with no re-training of the ODE coefficients
# -- a step change compared to site-by-site Pilar 2 fitting.
#
# TODO (v2.4.0)
# -------------
#  - [ ] `no_fno_module()` -- torch nn_module implementing FNO 1-D
#        spectral convolution (SoftplusGELU activation; 4 hidden
#        FNO blocks; 32 Fourier modes).
#  - [ ] `no_fno_fit(depths, targets, covariates, epochs, lr, ...)`
#  - [ ] `no_deeponet_module()` -- Lu et al. 2021 branch+trunk.
#  - [ ] `no_deeponet_fit()`
#  - [ ] `no_operator_posterior()` -- predictive uncertainty via
#        dropout on the spectral layers.
#  - [ ] Benchmark: FNO vs DeepONet vs Pilar 2 Neural ODE on aqp::sp4
#        + a multi-pedon hold-out set.
#  - [ ] `vignettes/pilar8-neural-operators.Rmd`

#' Fit a Fourier Neural Operator for pedogenetic profile operators
#' (scaffold, v2.4.0)
#'
#' @description **Not yet implemented.**  Scheduled for v2.4.0.
#' @param depths Numeric vector of depths in metres.
#' @param targets Matrix of observed profile properties (`n_obs x
#'   n_depths`).
#' @param covariates Matrix of site-level covariates (`n_obs x p`).
#' @param ... Passed to the torch training loop (epochs, lr, etc.).
#' @return (When implemented) An `edaphos_no_fno` S3 object.
#' @export
no_fno_fit <- function(depths, targets, covariates, ...) {
  stop(
    "`no_fno_fit()` is scheduled for edaphos v2.4.0 (Pilar 8 -- Neural\n",
    "operators).  The API is fixed; the body will wire torch + FNO\n",
    "architecture in the dedicated v2.4.0 release.",
    call. = FALSE
  )
}

#' Fit a DeepONet for pedogenetic profile operators (scaffold, v2.4.0)
#'
#' @description **Not yet implemented.**  Scheduled for v2.4.0.
#' @param depths,targets,covariates See [`no_fno_fit()`].
#' @param ... Passed to the torch training loop (epochs, lr, etc.).
#' @export
no_deeponet_fit <- function(depths, targets, covariates, ...) {
  stop(
    "`no_deeponet_fit()` is scheduled for edaphos v2.4.0 (Pilar 8 --\n",
    "Neural operators).",
    call. = FALSE
  )
}
