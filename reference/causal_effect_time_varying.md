# Time-varying causal effect beta(t) over a sliding window

Closes the Pilar 1 x Pilar 3 loop: the v1.4.0 backdoor-adjusted
estimator is applied within non-overlapping (or overlapping) windows of
the temporal frame, producing a beta_hat(t) trajectory with bootstrap
CIs. Mann-Kendall tests for a significant trend.

## Usage

``` r
causal_effect_time_varying(
  frame,
  dag,
  exposure,
  outcome,
  window = 24L,
  step = 6L,
  adjustment = NULL,
  B = 200L,
  min_n = 30L,
  seed = NULL
)
```

## Arguments

- frame:

  A data frame with columns `t`, `lon`, `lat`, the `exposure`, `outcome`
  and any `adjustment` columns.

- dag:

  A `dagitty` DAG. Used only to derive the adjustment set when
  `adjustment = NULL`.

- exposure, outcome:

  Character column names.

- window:

  Integer; number of distinct `t` values per window.

- step:

  Integer; how many `t` values to advance the window.

- adjustment:

  Optional character vector of adjustment columns.

- B:

  Integer bootstrap replicates per window. `0` disables CI estimation
  (just a point estimate per window).

- min_n:

  Minimum in-window sample size to fit a window. Windows smaller than
  this yield `NA` estimates.

- seed:

  Optional RNG seed for bootstrap reproducibility.

## Value

A `data.frame` of class `edaphos_causal_4d` with columns `t_start`,
`t_end`, `t_centre`, `n`, `beta_hat`, `se`, `ci_lo`, `ci_hi`.

## Examples

``` r
# A synthetic 36-slice soil panel: 10 sites, an annual-rainfall
# anomaly (mm from the long-term normal) driving topsoil SOC, and
# elevation confounding both (orographic rain, cooler moister
# soils).  The MAP -> SOC slope is built to decay over the record.
set.seed(11)
panel <- expand.grid(site = 1:10, t = 1:36)
elev  <- runif(10, 400, 1100)
panel$elev     <- elev[panel$site]
panel$map_anom <- -0.10 * (panel$elev - 750) + rnorm(nrow(panel), 0, 60)
panel$soc      <- 22 + 0.006 * panel$elev +
  (0.022 - 0.0006 * panel$t) * panel$map_anom + rnorm(nrow(panel), 0, 0.8)

# `dag` is consulted only when `adjustment = NULL`, so an explicit
# adjustment set lets you pass `dag = NULL`.  Only `t`, the exposure,
# the outcome and the adjustment columns are ever read -- the panel
# here carries no `lon`/`lat` at all.
bt <- causal_effect_time_varying(panel, dag = NULL,
                                 exposure = "map_anom", outcome = "soc",
                                 window = 12L, step = 3L,
                                 adjustment = "elev", B = 0L)
bt
#> <edaphos_causal_4d>  (Pilar 1 x Pilar 3 bridge)
#>   target effect : map_anom -> soc
#>   adjustment    : elev
#>   window / step : 12 / 3
#>   n windows     : 9
#>   beta_hat mean : 0.0103 (range [0.0046, 0.0154])
#>   Mann-Kendall  : S=-36, tau=-1, p=0.000263, trend=decreasing

# Dropping the confounder does not merely add noise: it collapses
# the level of the whole trajectory while leaving the downward shape
# intact.  A convincing-looking beta(t) decline is therefore no
# evidence at all that the backdoor was closed.
naive <- causal_effect_time_varying(panel, NULL, "map_anom", "soc",
                                    window = 12L, step = 3L,
                                    adjustment = character(0), B = 0L)
round(rbind(adjusted = bt$beta_hat, naive = naive$beta_hat), 4)
#>            [,1]   [,2]   [,3]   [,4]   [,5]   [,6]   [,7]    [,8]    [,9]
#> adjusted 0.0154 0.0149 0.0139 0.0122 0.0104 0.0088 0.0069  0.0056  0.0046
#> naive    0.0066 0.0059 0.0053 0.0033 0.0031 0.0035 0.0018 -0.0012 -0.0046
round(c(adjusted = mean(bt$beta_hat), naive = mean(naive$beta_hat)), 4)
#> adjusted    naive 
#>   0.0103   0.0026 

# With B = 0 the interval is exactly beta_hat +/- 1.96 * se, not a
# bootstrap.  Note also how the metadata attributes survive
# subsetting: `[` KEEPS them when you subset rows (R >= 4.0), but
# drops them the moment you subset columns, after which print()
# reports "adjustment : <none>".  as.data.frame() is the safe route
# when you only want the numbers.
isTRUE(all.equal(bt$ci_lo, bt$beta_hat - qnorm(0.975) * bt$se))
#> [1] TRUE
head(as.data.frame(bt)[, c("t_centre", "n", "beta_hat", "ci_lo")], 3)
#>   t_centre   n   beta_hat      ci_lo
#> 1        7 120 0.01537246 0.01275146
#> 2       10 120 0.01489947 0.01232345
#> 3       13 120 0.01392307 0.01137323

# dagitty can derive the same adjustment set from the graph instead.
if (requireNamespace("dagitty", quietly = TRUE)) {
  dag <- dagitty::dagitty(
    "dag { elev -> map_anom  elev -> soc  map_anom -> soc }")
  bt2 <- causal_effect_time_varying(panel, dag, "map_anom", "soc",
                                    window = 12L, step = 3L, B = 0L)
  identical(attr(bt2, "adjustment"), "elev")
}
#> [1] TRUE
```
