# Posterior predictive distribution of an edaphos Active-Learning fit

Samples the conditional distribution of the target at every row of
`candidates` by asking the underlying Quantile Regression Forest
(ranger) for a grid of quantiles. The returned `edaphos_posterior`
carries those quantile samples directly, so
[`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md)
and
[`ggplot2::autoplot()`](https://ggplot2.tidyverse.org/reference/autoplot.html)
work without changes.

## Usage

``` r
active_learning_posterior(model, newdata, n_quantiles = 99L, units = NULL)
```

## Arguments

- model:

  An `edaphos_al_model` produced by
  [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md).

- newdata:

  A data frame with (at least) the columns used as covariates at fit
  time.

- n_quantiles:

  Integer; size of the equally-spaced grid of quantiles to request from
  the QRF. Defaults to `99L` (1 % to 99 % in 1 % steps, which is a
  reasonable trade-off between a smooth empirical CDF and
  `ranger::predict()` cost).

- units:

  Optional free-text units tag.

## Value

An `edaphos_posterior` with `method = "ensemble"` (the QRF conditional
distribution being itself an ensemble over tree leaves) and
`query_type = "sample"`.

## References

Meinshausen, N. (2006). Quantile regression forests. *Journal of Machine
Learning Research* **7**, 983-999.
