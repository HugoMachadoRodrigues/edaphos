# Bias-adjustment grid for a Cinelli & Hazlett sensitivity contour

Builds a 2-D grid over (R^2 of U with X \| Z, R^2 of U with Y \| X, Z)
and returns the bias-adjusted estimate at each cell, ready for
[`contour()`](https://rdrr.io/r/graphics/contour.html) /
[`ggplot2::geom_contour()`](https://ggplot2.tidyverse.org/reference/geom_contour.html).
The grid is dense enough (51 x 51 by default) to render smooth contours.

## Usage

``` r
causal_sensitivity_grid(effect, se, df, grid_size = 51L, r2_max = 0.6)
```

## Arguments

- effect, se, df:

  Point estimate, SE, degrees of freedom of the causal effect.

- grid_size:

  Integer; grid resolution per axis. Default `51L`.

- r2_max:

  Numeric in (0, 1); maximum partial-R^2 to plot. Default `0.6` (values
  above this are typically unrealistic for real covariates).

## Value

A long-format data frame with columns `r2_xu_z`, `r2_yu_xz`,
`adjusted_estimate`, `bias`, `bias_factor`.
