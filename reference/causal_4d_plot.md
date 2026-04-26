# Plot a time-varying causal effect trajectory

Returns a `ggplot` object showing beta(t) + bootstrap CI ribbon, with a
Mann-Kendall trend summary as the plot subtitle. Requires `ggplot2`.

## Usage

``` r
causal_4d_plot(object, ...)
```

## Arguments

- object:

  An `edaphos_causal_4d` frame from
  [`causal_effect_time_varying()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_effect_time_varying.md).

- ...:

  Unused.

## Value

A `ggplot` object.
