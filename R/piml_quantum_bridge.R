# Pilar 2 x Pilar 6 bridge -- Physics-Informed Quantum Kernels
# (v2.2.0 scope).
#
# Status: SCAFFOLD.
#
# Why this bridge?
# ----------------
# The ZZFeatureMap of Pillar 6 is AGNOSTIC to the physical meaning of
# its input features.  For pedogenetic-profile data we KNOW a lot
# more: the input dimensions (depth z, current property y, covariate
# vector x) follow a specific ODE structure (dy/dz = f(z, y, x)).  A
# physics-informed quantum kernel constrains the ZZFeatureMap in two
# concrete ways:
#
#   1. Monotonicity constraint: patches that increase z monotonically
#      should be mapped to states whose inner product also respects
#      that monotonicity (physically: deeper horizons are "further"
#      in feature space).
#   2. ODE-solution kernel: instead of comparing raw (x, y, z)
#      triples, compare their ODE-solution trajectories under a
#      shared f_theta.  Two patches are "similar" if they evolve
#      similarly under the physical model.
#
# TODO (v2.2.0)
# -------------
#  - [ ] `piml_quantum_kernel(X, ode_fit)`: compute the physics-
#        informed Gram matrix using ODE-trajectory distance + ZZFM
#        inner product.
#  - [ ] `piml_qkrr_fit(X, y, ode_fit, ...)`: quantum KRR with the
#        physics-informed kernel.
#  - [ ] Benchmark: standard Q-KRR vs PI-QKRR on the colusa profile
#        + Cerrado pedons.
#  - [ ] `vignettes/pilar2-pilar6-piqk.Rmd`

#' Physics-informed quantum kernel over ODE-trajectory distance
#' (scaffold, v2.2.0)
#'
#' @description **Not yet implemented.**  Scheduled for v2.2.0.
#' @param X Feature matrix (n x p) whose rows contain depth + state
#'   + covariates.
#' @param ode_fit A fit from [`piml_profile_fit_bayesian()`] or
#'   [`piml_neural_ode_fit()`] that supplies the shared drift
#'   function f_theta.
#' @param reps Integer; ZZFeatureMap repetitions.
#' @return (When implemented) An `n x n` kernel matrix.
#' @export
piml_quantum_kernel <- function(X, ode_fit, reps = 2L) {
  stop(
    "`piml_quantum_kernel()` is scheduled for edaphos v2.2.0 (Pilar\n",
    "2 x Pilar 6 -- Physics-Informed Quantum Kernels).",
    call. = FALSE
  )
}
