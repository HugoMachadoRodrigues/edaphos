# Sensitivity analysis of an `edaphos_causal_iv` fit

The 2SLS estimator of
[`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md)
is consistent when IV conditions hold. This wrapper gives a classical
Cinelli-Hazlett envelope **treating the 2SLS estimate AS IF it were a
backdoor OLS estimate**. This is a conservative sensitivity check: the
IV effect is bias-adjusted against a hypothetical remaining confounder U
that affects BOTH the exposure and the outcome **after** the instruments
have been projected out. It is the right envelope to report alongside
the Sargan test.

## Usage

``` r
causal_sensitivity_from_iv(fit, q = 1, alpha = 0.05)
```

## Arguments

- fit:

  An `edaphos_causal_iv` object.

- q, alpha:

  See
  [`causal_sensitivity_summary()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_summary.md).

## Value

List identical to
[`causal_sensitivity_summary()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_summary.md)
with an extra `fit_estimator` field.
