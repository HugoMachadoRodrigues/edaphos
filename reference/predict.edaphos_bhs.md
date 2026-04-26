# Predict at new sites from a fitted Bayesian hierarchical spatial model

Bayesian kriging: for each posterior draw of `(beta, sigma^2, tau^2)` we
sample the latent GP at new locations conditional on the observed latent
field, then add iid noise. Returns posterior mean and quantiles at each
`newdata` row.

## Usage

``` r
# S3 method for class 'edaphos_bhs'
predict(object, newdata, quantiles = c(0.025, 0.5, 0.975), n_draws = 500L, ...)
```

## Arguments

- object:

  An `edaphos_bhs` fit.

- newdata:

  A data frame with covariates + coordinates matching the training
  schema.

- quantiles:

  Quantile levels to return. Default `c(0.025, 0.5, 0.975)`.

- n_draws:

  Integer; how many posterior samples to use (capped by the actual
  number available in the fit). Default `500L`.

- ...:

  Unused.

## Value

A data frame with `newdata` rows plus columns `mean`, `sd`, and one
column per quantile.
