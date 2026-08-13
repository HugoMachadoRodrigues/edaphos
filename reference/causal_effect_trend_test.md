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

## Examples

``` r
# One synthetic soil panel per seed: elevation confounds a rainfall
# anomaly and topsoil SOC, and `drift` fixes how fast the causal
# MAP -> SOC slope decays across the 36 time slices.
sim_beta <- function(seed, drift) {
  set.seed(seed)
  d <- expand.grid(site = 1:10, t = 1:36)
  e <- runif(10, 400, 1100)
  d$elev     <- e[d$site]
  d$map_anom <- -0.10 * (d$elev - 750) + rnorm(nrow(d), 0, 60)
  d$soc      <- 22 + 0.006 * d$elev +
    (0.022 - drift * d$t) * d$map_anom + rnorm(nrow(d), 0, 0.8)
  causal_effect_time_varying(d, NULL, "map_anom", "soc", window = 12L,
                             step = 3L, adjustment = "elev", B = 0L)
}

# A genuine decay is picked up: tau = -1, p = 0.000263, "decreasing".
bt <- sim_beta(11, drift = 0.0006)
causal_effect_trend_test(bt)
#> $S
#> [1] -36
#> 
#> $tau
#> [1] -1
#> 
#> $p_value
#> [1] 0.0002632608
#> 
#> $trend_direction
#> [1] "decreasing"
#> 
#> $z
#> [1] -3.649002
#> 
#> $n
#> [1] 9
#> 

# The test reads `beta_hat` and nothing else.  Inflating every
# standard error a thousandfold leaves the verdict untouched, so a
# window fitted on 30 points votes as loudly as one fitted on 3000.
loose <- bt
loose$se <- loose$se * 1000
identical(causal_effect_trend_test(loose), causal_effect_trend_test(bt))
#> [1] TRUE

# "none" can also mean "not enough windows": with fewer than four
# finite beta_hat values the test returns p_value = NA and direction
# "none".  That is silence, not evidence of a stable effect.
causal_effect_trend_test(bt[1:3, ])
#> $S
#> [1] NA
#> 
#> $tau
#> [1] NA
#> 
#> $p_value
#> [1] NA
#> 
#> $trend_direction
#> [1] "none"
#> 

# The normal approximation assumes independent windows.  At step = 3
# and window = 12 neighbouring windows share 9 of their 12 slices, so
# the p-value is badly anti-conservative: under a constant effect
# (drift = 0) it still flags a trend in 0.3 of 60 replicates, six
# times the nominal 0.05.  Use step >= window before quoting p.
p_null <- vapply(1:60, function(s) {
  causal_effect_trend_test(sim_beta(s, drift = 0))$p_value
}, numeric(1))
mean(p_null < 0.05)
#> [1] 0.3
```
