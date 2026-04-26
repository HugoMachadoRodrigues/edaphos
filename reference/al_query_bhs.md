# Bayesian Hierarchical Active Learning (Pilar 7 x Pilar 5)

Ranks candidate sites by their predictive variance averaged over the BHS
posterior MCMC draws – Thompson-sampling-style AL in the language of
Settles (2009, Section 3.3).

## Usage

``` r
al_query_bhs(bhs_fit, pool_data, n_select = 5L, n_draws = 200L)
```

## Arguments

- bhs_fit:

  An `edaphos_bhs` from
  [`bhs_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/bhs_fit.md).

- pool_data:

  Data frame of candidate sites with covariates + coords.

- n_select:

  Integer; number of candidates to return.

- n_draws:

  Integer; number of posterior draws to average.

## Value

`edaphos_al_bhs_query` data frame sorted by descending average
predictive variance.
