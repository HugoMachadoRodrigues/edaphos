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

## Examples

``` r
if (requireNamespace("ggplot2", quietly = TRUE)) {
  # Synthetic panel whose MAP -> SOC effect decays over 36 slices,
  # with elevation as the confounder that must be adjusted away.
  set.seed(11)
  panel <- expand.grid(site = 1:10, t = 1:36)
  elev  <- runif(10, 400, 1100)
  panel$elev     <- elev[panel$site]
  panel$map_anom <- -0.10 * (panel$elev - 750) + rnorm(nrow(panel), 0, 60)
  panel$soc      <- 22 + 0.006 * panel$elev +
    (0.022 - 0.0006 * panel$t) * panel$map_anom + rnorm(nrow(panel), 0, 0.8)

  boot <- causal_effect_time_varying(panel, NULL, "map_anom", "soc",
                                     window = 12L, step = 3L,
                                     adjustment = "elev", B = 100L,
                                     seed = 42)
  g <- causal_4d_plot(boot)
  print(inherits(g, "ggplot"))   # print(g) draws it on the device

  # The subtitle is a live Mann-Kendall test on exactly the windows
  # being drawn, so it inherits their overlap.  Read it as a label
  # for the curve, not as an independent significance test.
  print(g$labels$subtitle)

  # The ribbon is simply ci_lo/ci_hi.  With B = 0 those are the OLS
  # normal limits rather than a bootstrap, and the ribbon looks no
  # different: here the bootstrap band is in fact the narrower of
  # the two (mean width 0.00485 against 0.00515).
  norm <- causal_effect_time_varying(panel, NULL, "map_anom", "soc",
                                     window = 12L, step = 3L,
                                     adjustment = "elev", B = 0L)
  print(round(c(bootstrap = mean(boot$ci_hi - boot$ci_lo),
                normal    = mean(norm$ci_hi - norm$ci_lo)), 5))

  # No autoplot() method is registered for this class, despite the
  # wording of the error raised when ggplot2 is missing.
  inherits(try(ggplot2::autoplot(boot), silent = TRUE), "try-error")
}
#> [1] TRUE
#> [1] "Mann-Kendall: S=-36, tau=-1, p=0.000263 (decreasing)"
#> bootstrap    normal 
#>   0.00485   0.00515 
#> [1] TRUE
```
