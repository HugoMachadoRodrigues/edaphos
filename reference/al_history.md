# Extract the learning curve from a fitted Active-Learning model

Returns the iteration-by-iteration diagnostics (sample size, OOB RMSE,
mean queried-point uncertainty) as a tidy data frame, ready for plotting
with ggplot2 or base graphics.

## Usage

``` r
al_history(model)
```

## Arguments

- model:

  A `edaphos_al_model` returned by
  [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md)
  or
  [`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md).

## Value

A data frame with columns `iter`, `n_labeled`, `rmse_oob`,
`mean_uncertainty`.
