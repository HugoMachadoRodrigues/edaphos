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

## Examples

``` r
data(br_cerrado)

# Effect of dry-season greenness on topsoil carbon, holding the
# usual climate/terrain backdoor set fixed.
fit <- lm(soc ~ ndvi + map_mm + elev + slope, data = br_cerrado)
s <- causal_sensitivity_from_lm(fit, "ndvi")
round(c(effect = s$effect, t = s$t_stat,
        rv = s$rv, rv_alpha = s$rv_alpha), 3)
#>   effect        t       rv rv_alpha 
#>   29.840   15.448    0.290    0.258 

# RV = 0.290 reads: an unobserved confounder -- soil texture, say --
# would have to explain 29% of the residual variance of `ndvi` AND
# 29% of the residual variance of `soc`, on top of the three
# covariates, before the coefficient reached zero.  `rv_alpha`
# (0.258) is always the smaller of the two: it only has to reach
# statistical insignificance, not zero.

# Trap: the RV depends on the fit only through |t| and df, so it is
# blind to the units of the exposure.  Rescaling rainfall from mm to
# metres multiplies the coefficient by 1000 and leaves the RV where
# it was -- a numerically larger effect is not a more robust one.
cerrado_m <- br_cerrado
cerrado_m$map_m <- cerrado_m$map_mm / 1000
mm <- causal_sensitivity_from_lm(
  lm(soc ~ map_mm + ndvi + elev + slope, data = br_cerrado), "map_mm")
m <- causal_sensitivity_from_lm(
  lm(soc ~ map_m + ndvi + elev + slope, data = cerrado_m), "map_m")
round(c(rv_mm = mm$rv, rv_m = m$rv,
        effect_ratio = m$effect / mm$effect), 4)
#>        rv_mm         rv_m effect_ratio 
#>       0.3015       0.3015    1000.0000 
```
