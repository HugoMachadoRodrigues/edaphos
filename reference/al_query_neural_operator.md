# Causal-driven AL via Neural Operator disagreement (Pilar 8 x Pilar 5)

Ranks candidate sites by the disagreement between a Neural Operator's
predicted depth profile and a classical Pilar 2 pedogenetic ODE's
predicted profile, normalised by the NO's perturbation-spread
uncertainty.

## Usage

``` r
al_query_neural_operator(
  no_fit,
  ode_fit,
  pool_covariates,
  pool_depths = NULL,
  n_select = 5L,
  n_pert = 20L,
  pert_sd = 0.1,
  seed = NULL
)
```

## Arguments

- no_fit:

  A fit from
  [`no_deeponet_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/no_deeponet_fit.md)
  or
  [`no_fno_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/no_fno_fit.md).

- ode_fit:

  A fit from
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)
  or
  [`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md).

- pool_covariates:

  Matrix of per-site summary covariates (n_pool x p_in) matching the
  branch input of `no_fit`.

- pool_depths:

  Optional depths to evaluate at; defaults to the training depths of
  `no_fit`.

- n_select:

  Integer; number of candidates to return.

- n_pert:

  Integer; number of Gaussian-noise perturbations per candidate to
  estimate NO uncertainty.

- pert_sd:

  Numeric; standard deviation of the Gaussian perturbation (in
  covariate-standard-deviation units).

- seed:

  Optional RNG seed.

## Value

A data frame of class `edaphos_al_neural_operator_query` sorted by
descending score.
