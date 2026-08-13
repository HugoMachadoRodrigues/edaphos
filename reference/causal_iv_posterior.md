# Bootstrap posterior for a 2SLS effect as an edaphos_posterior

Wraps
[`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md)
in a nonparametric bootstrap over rows (or over clusters if `cluster` is
supplied) and packages the resulting vector of effect estimates as an
[`edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_posterior.md)
so that
[`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md)
and
[`autoplot()`](https://ggplot2.tidyverse.org/reference/autoplot.html)
apply uniformly.

## Usage

``` r
causal_iv_posterior(
  data,
  exposure,
  outcome,
  instruments,
  covariates = NULL,
  B = 500L,
  cluster = NULL,
  seed = NULL,
  units = NULL
)
```

## Arguments

- data:

  A data frame.

- exposure:

  Character; name of the endogenous exposure column.

- outcome:

  Character; name of the outcome column.

- instruments:

  Character vector; names of instrument columns. More instruments than
  exposures gives an over-identified model on which the Sargan test is
  applicable.

- covariates:

  Optional character vector of exogenous-control column names included
  in both first and second stage.

- B:

  Integer; number of bootstrap resamples. Default `500L`.

- cluster:

  Optional character; column in `data` to resample by block (e.g.
  `"kmeans_cluster"` for spatial resampling).

- seed:

  Optional RNG seed.

- units:

  Optional units string.

## Value

An `edaphos_posterior` with `query_type = "effect"` and
`method = "bootstrap"`.

## Examples

``` r
# Geology is a landscape attribute, so the instruments are constant
# within a farm -- and the agronomy shock is shared within a farm
# too. That is the regime where row-wise resampling lies.
set.seed(7)
n_farm     <- 40
farm       <- rep(seq_len(n_farm), each = 8)
farm_shock <- rnorm(n_farm, 0, 1.2)[farm]   # shared agronomy
carbonate  <- runif(n_farm, 0, 12)[farm]    # parent-rock CaCO3
quarry_km  <- runif(n_farm, 1, 60)[farm]    # km to the lime quarry
n     <- length(farm)
mgmt  <- rnorm(n)
ph    <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km +
         0.45 * mgmt + rnorm(n, 0, 0.25)
yield <- 1.0 + 1.5 * ph + 1.3 * mgmt + farm_shock + rnorm(n, 0, 0.4)
soil  <- data.frame(ph, yield, carbonate, quarry_km, farm)

# Resampling rows pretends the 320 plots are 320 independent draws.
iv_rows <- causal_iv_posterior(
  soil, "ph", "yield", instruments = c("carbonate", "quarry_km"),
  B = 150L, seed = 1, units = "t/ha per pH unit")

# Resampling farms respects the level at which the instruments and
# the shock actually vary.
iv_farms <- causal_iv_posterior(
  soil, "ph", "yield", instruments = c("carbonate", "quarry_km"),
  B = 150L, cluster = "farm", seed = 1, units = "t/ha per pH unit")

# The cluster bootstrap is about twice as wide, 0.48 against 0.23.
# The analytic 2SLS standard error, 0.22, agrees with the row
# bootstrap and is just as wrong: neither knows the effective
# sample size is 40 farms, not 320 plots.
fit <- causal_iv_fit_2sls(soil, "ph", "yield",
                          instruments = c("carbonate", "quarry_km"))
c(analytic = fit$se, boot_rows = iv_rows$sd, boot_farms = iv_farms$sd)
#>   analytic  boot_rows boot_farms 
#>  0.2201736  0.2332016  0.4827354 

# The centre barely moves: clustering is about uncertainty, not
# about bias. Both results are ordinary edaphos_posterior objects.
iv_farms
#> <edaphos_posterior>
#>   method      : bootstrap
#>   query_type  : effect
#>   units       : t/ha per pH unit
#>   n_samples   : 150
#>   query shape : 1
#>   mean range  : [+1.7026, +1.7026]  mean = +1.7026
#>   sd   range  : [+0.4827, +0.4827]  mean = +0.4827
c(rows = iv_rows$mean, farms = iv_farms$mean)
#>     rows    farms 
#> 1.649371 1.702640 

# Resamples that fail to fit are dropped silently, so check how
# many draws actually survived before quoting an interval.
iv_farms$metadata$B
#> [1] 150
```
