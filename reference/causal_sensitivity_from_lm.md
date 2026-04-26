# Sensitivity analysis of an `lm` backdoor fit

Convenience wrapper around
[`causal_sensitivity_summary()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_summary.md)
that extracts the effect, SE and df from a fitted `lm`.

## Usage

``` r
causal_sensitivity_from_lm(fit, exposure, q = 1, alpha = 0.05)
```

## Arguments

- fit:

  An `lm` object.

- exposure:

  Character; the exposure coefficient name.

- q, alpha:

  See
  [`causal_sensitivity_summary()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_summary.md).

## Value

List identical to
[`causal_sensitivity_summary()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_summary.md).
