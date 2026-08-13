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

## Examples

``` r
# A backdoor fit of `soc` on mean annual rainfall in `br_cerrado`
# gives beta = 0.008583 g/kg per mm, SE = 0.000529, df = 2020.
s <- causal_sensitivity_summary(0.008583, 0.000529, 2020)

# The grid is the contour map that the robustness value summarises.
# Evaluate it out to r2_max = RV and the far corner of the
# equal-confounding diagonal lands exactly on zero.
corner <- causal_sensitivity_grid(0.008583, 0.000529, 2020,
                                  grid_size = 2L, r2_max = s$rv)
corner[, c("r2_xu_z", "r2_yu_xz", "adjusted_estimate")]
#>     r2_xu_z  r2_yu_xz adjusted_estimate
#> 1 0.0000000 0.0000000          0.008583
#> 2 0.3016734 0.0000000          0.008583
#> 3 0.0000000 0.3016734          0.008583
#> 4 0.3016734 0.3016734          0.000000

# The two axes are not interchangeable.  `r2_xu_z` enters the bias
# factor as r2 / (1 - r2), so confounding of the EXPOSURE bites
# harder: the (0.5, 0.2) cell has already flipped the sign of the
# estimate while (0.2, 0.5) is still positive.
g <- causal_sensitivity_grid(0.008583, 0.000529, 2020,
                             grid_size = 6L, r2_max = 0.5)
g[(g$r2_xu_z == 0.5 & g$r2_yu_xz == 0.2) |
  (g$r2_xu_z == 0.2 & g$r2_yu_xz == 0.5), ]
#>    r2_xu_z r2_yu_xz adjusted_estimate        bias bias_factor
#> 18     0.5      0.2     -0.0020497684 0.010632768   0.4472136
#> 33     0.2      0.5      0.0001770585 0.008405941   0.3535534

# Sign reversal is not an error: `adjusted_estimate` is the estimate
# pushed towards zero by `bias`, and beyond the RV it overshoots.
# Ten of these 36 cells come back negative.
sum(g$adjusted_estimate < 0)
#> [1] 10

# The default is 51 x 51 = 2601 rows, which is the long-format frame
# you hand to contour() or ggplot2::geom_contour().
nrow(causal_sensitivity_grid(0.008583, 0.000529, 2020))
#> [1] 2601
```
