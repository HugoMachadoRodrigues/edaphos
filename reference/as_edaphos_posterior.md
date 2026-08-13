# Coerce a native pillar object to `edaphos_posterior`

Each pillar ships an `as_edaphos_posterior()` method that wraps its
natural uncertainty representation in the unified class. The default
method accepts already-wrapped objects, numeric vectors (treated as a
1-D scalar posterior), and numeric matrices (treated as
`n_samples x n_query` matrices).

## Usage

``` r
as_edaphos_posterior(x, ...)
```

## Arguments

- x:

  Object to coerce.

- ...:

  Additional arguments passed to the pillar-specific method (e.g.
  `query_type`, `units`).

## Value

An `edaphos_posterior`.

## Examples

``` r
# The default method reads a matrix as (draws x query cells): 200
# draws of SOC at 3 profiles, the shape a Pillar-1 block bootstrap
# or a Pillar-4 head ensemble hands back.
set.seed(11)
draws <- matrix(stats::rnorm(200L * 3L, mean = c(18, 22, 26), sd = 2),
                nrow = 200L, ncol = 3L, byrow = TRUE)
post <- as_edaphos_posterior(draws, query_type = "sample",
                             units = "g/kg")
post
#> <edaphos_posterior>
#>   method      : ensemble
#>   query_type  : sample
#>   units       : g/kg
#>   n_samples   : 200
#>   query shape : 3
#>   mean range  : [+18.1625, +25.9983]  mean = +22.0262
#>   sd   range  : [+1.9416, +2.0797]  mean = +1.9967

# Nothing checks the orientation. The transpose is accepted in
# silence and gives 200 query cells with 3 draws each; the per-cell
# sd (3.32, 5.18, 2.63 for the first three) is then the spread
# ACROSS profiles, which is not a posterior sd of anything.
pT <- as_edaphos_posterior(t(draws), query_type = "sample")
c(cells = length(pT$mean), draws = dim(pT$samples)[1L])
#> cells draws 
#>   200     3 
round(as.numeric(pT$sd)[1:3], 2)
#> [1] 3.32 5.18 2.63

# A bare numeric vector is n draws of ONE scalar, not n predictions.
# Passing 200 per-site predictions this way collapses them to a
# single query cell whose "sd" (2.08) is the spread between sites.
v <- as_edaphos_posterior(as.numeric(draws[, 1L]))
c(cells = length(v$mean), draws = dim(v$samples)[1L],
  sd = round(as.numeric(v$sd), 3))
#>  cells  draws     sd 
#>   1.00 200.00   2.08 

# `method` defaults to "ensemble" whatever produced the draws, so a
# bootstrap posterior mislabels its own provenance unless you say so.
c(default = as_edaphos_posterior(draws)$method,
  tagged  = as_edaphos_posterior(draws, method = "bootstrap")$method)
#>     default      tagged 
#>  "ensemble" "bootstrap" 

# The identity method returns `x` and drops every extra argument, so
# an existing posterior cannot be re-tagged through the adapter:
# `units` stays "g/kg" and the object comes back untouched.
identical(as_edaphos_posterior(post, units = "kg/m2"), post)
#> [1] TRUE

# The adapter is narrower than the constructor it wraps: a
# (draws x H x W) map ensemble has no default method and must go
# through edaphos_posterior(samples = ) directly.
arr <- array(stats::rnorm(50L * 4L * 5L), dim = c(50L, 4L, 5L))
try(as_edaphos_posterior(arr))
#> Error : No `as_edaphos_posterior` method for class <array>.
dim(edaphos_posterior(samples = arr, query_type = "map")$mean)
#> [1] 4 5
```
