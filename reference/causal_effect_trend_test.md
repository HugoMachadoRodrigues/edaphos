# Mann-Kendall trend test on a beta(t) trajectory

Non-parametric two-sided Mann-Kendall test for a monotonic trend in the
time-varying causal effect. The S statistic counts sign- consistent
pairs; p-value is the normal approximation.

## Usage

``` r
causal_effect_trend_test(beta_df)
```

## Arguments

- beta_df:

  An `edaphos_causal_4d` object.

## Value

Named list with `S`, `tau`, `p_value`, `trend_direction` (`"increasing"`
/ `"decreasing"` / `"none"`).
