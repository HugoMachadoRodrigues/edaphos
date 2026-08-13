# Benchmark wrapper: Pilar 1 – DAG-adjusted OLS + parametric bootstrap

Restricts OLS to covariates that appear in the supplied DAG as direct
parents of the outcome (falling back to the full covariate set when the
DAG has no matching variables) and generates a parametric-bootstrap
predictive posterior. Intended for the v3.1.0 WoSIS head-to-head; the
exported API is stable enough for use on any regional subset that
follows the same schema.

## Usage

``` r
benchmark_fit_p1_causal(
  train,
  test,
  cov_cols,
  dag = NULL,
  n_boot = 300L,
  seed = 1L,
  calibrate = TRUE
)
```

## Arguments

- train, test:

  Data frames with a response column `soc`, coord columns `lon`/`lat`,
  and the columns listed in `cov_cols`.

- cov_cols:

  Character vector of candidate covariate names.

- dag:

  A `dagitty` DAG object (or `NULL` to use the full covariate set).

- n_boot:

  Number of bootstrap resamples. Default `300`.

- seed:

  Optional RNG seed.

- calibrate:

  Logical (default `TRUE`). When `TRUE`, an estimate of the in-sample
  residual standard deviation is added as iid Gaussian noise to every
  posterior sample so the predictive posterior carries BOTH epistemic
  (bootstrap-spread) AND aleatoric (residual) uncertainty. Set to
  `FALSE` to reproduce the v3.1.0 epistemic-only behaviour.

## Value

An `edaphos_posterior` with `method = "bootstrap"`,
`query_type = "map"`.

## Examples

``` r
data(br_cerrado)

# The wrapper checks for the response `soc` and the named covariates
# and nothing else -- it never reads a coordinate column, and its
# bootstrap is a plain row resample. So the split below is RANDOM, not
# spatial, and the interval it produces does not account for spatial
# dependence between train and test. For a spatially blocked
# comparison see `data-raw/benchmark_wosis_6pilar.R`, which is what
# the published six-pillar figures use.
set.seed(1)
sub <- br_cerrado[sample(nrow(br_cerrado), 300L), ]
covs  <- c("elev", "slope", "twi", "map_mm", "ndvi")
train <- sub[1:240, ]; test <- sub[241:300, ]

post <- benchmark_fit_p1_causal(train, test, covs, n_boot = 300L, seed = 1L)
dim(post$samples)          # 300 bootstrap draws x 60 held-out sites
#> [1] 300  60

# Score it against the baseline any soil map has to beat -- predicting
# the training mean everywhere.  3.680 g/kg against 6.173.
cal <- uncertainty_calibrate(post, truth = test$soc)
round(c(rmse = cal$point_rmse,
        null = sqrt(mean((mean(train$soc) - test$soc)^2))), 3)
#>  rmse  null 
#> 3.680 6.173 

# `calibrate = TRUE` (the default) convolves the in-sample residual sd
# into every draw.  The noise is centred within each test column, so the
# point prediction survives untouched -- colMeans() moves by ~3e-14 --
# and only the interval changes.
raw <- benchmark_fit_p1_causal(train, test, covs, n_boot = 300L,
                               seed = 1L, calibrate = FALSE)
max(abs(colMeans(post$samples) - colMeans(raw$samples)))
#> [1] 0

# Read that next to the coverage, which is the whole point of the term.
# Bootstrap spread alone is the uncertainty of the FITTED MEAN, not of a
# new profile: its 90% intervals are 1.99 g/kg wide and hold 22% of the
# held-out truth.  With the aleatoric term they are 13.46 wide and hold
# 93%, which on 60 sites is 0.9 binomial standard errors off nominal --
# calibrated, as far as this test set can tell.
cal_raw <- uncertainty_calibrate(raw, truth = test$soc)
round(c(picp90_raw = cal_raw$picp[["0.90"]],
        picp90_cal = cal$picp[["0.90"]],
        mpiw90_raw = cal_raw$mpiw[["0.90"]],
        mpiw90_cal = cal$mpiw[["0.90"]],
        se90 = sqrt(0.9 * 0.1 / nrow(test))), 3)
#> picp90_raw picp90_cal mpiw90_raw mpiw90_cal       se90 
#>      0.217      0.933      1.989     13.461      0.039 

# TRAP: the DAG filter asks for the parents of a hard-coded outcome node
# named "soc_topsoil_gkg".  A DAG that calls its outcome anything else
# raises inside dagitty::parents(), and the fallback keeps every node
# NAME in the graph -- so `elev` and `slope`, parents of nothing but
# `ndvi` and `twi`, survive a selection advertised as causal.
if (requireNamespace("dagitty", quietly = TRUE)) {
  d_wrong <- dagitty::dagitty(
    "dag { elev -> ndvi ; ndvi -> soc ; map_mm -> soc ; slope -> twi }")
  print(dagitty::parents(d_wrong, "soc"))     # map_mm, ndvi
  print(benchmark_fit_p1_causal(train, test, covs, dag = d_wrong,
                                n_boot = 50L,
                                seed = 1L)$metadata$adjusted_features)

  # Name the outcome the way the wrapper expects and the parent set is
  # honoured: three covariates instead of five.
  d_ok <- dagitty::dagitty(
    "dag { map_mm -> soc_topsoil_gkg ; ndvi -> soc_topsoil_gkg ;
           twi -> soc_topsoil_gkg ; elev -> map_mm ; slope -> twi }")
  print(benchmark_fit_p1_causal(train, test, covs, dag = d_ok,
                                n_boot = 50L,
                                seed = 1L)$metadata$adjusted_features)

  # And a DAG leaving fewer than two covariates reverts to the full set
  # rather than fitting a one-covariate model -- also silently.
  # `metadata$adjusted_features` is the only place any of this shows.
  d_one <- dagitty::dagitty("dag { ndvi -> soc_topsoil_gkg }")
  print(benchmark_fit_p1_causal(train, test, covs, dag = d_one,
                                n_boot = 50L,
                                seed = 1L)$metadata$adjusted_features)
}
#> [1] "map_mm" "ndvi"  
#> [1] "elev"   "slope"  "twi"    "map_mm" "ndvi"  
#> [1] "twi"    "map_mm" "ndvi"  
#> [1] "elev"   "slope"  "twi"    "map_mm" "ndvi"  
```
