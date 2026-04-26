# Initial sampling design via Conditioned Latin Hypercube (cLHS)

Picks an initial labeled subset from a pool of candidate locations using
Conditioned Latin Hypercube Sampling (Minasny & McBratney 2006). cLHS
spreads the sample uniformly across the joint distribution of the
covariates, which is a strong starting point before any model is fit.

## Usage

``` r
al_initial_design(pool, covariates, n = 20L, seed = NULL, iter = 10000L)
```

## Arguments

- pool:

  Data frame of candidate locations. Must contain the `covariates`
  columns; rows with any `NA` in those columns are dropped prior to
  optimisation.

- covariates:

  Character vector with covariate column names.

- n:

  Integer, number of initial samples to select.

- seed:

  Optional integer for reproducibility.

- iter:

  Integer, cLHS optimiser iterations (default 1e4 follows
  [`clhs::clhs`](https://rdrr.io/pkg/clhs/man/clhs.html) default — use a
  smaller value for quick prototyping).

## Value

Integer vector with row indices of `pool` that form the initial labeled
set.

## Details

This is the *seed* step of the Pillar 5 closed-loop Active Learning
workflow — the subsequent iterations replace random exploration by
uncertainty-guided exploitation (see
[`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md)
/
[`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md)).

## References

Minasny B, McBratney AB (2006). A conditioned Latin hypercube method for
sampling in the presence of ancillary information. *Computers &
Geosciences* 32, 1378-1388.

## Examples

``` r
# \donttest{
  if (requireNamespace("sp", quietly = TRUE)) {
    data(meuse, package = "sp")
    idx <- al_initial_design(meuse, covariates = c("dist", "elev"),
                             n = 15, seed = 1, iter = 500)
    head(meuse[idx, ])
  }
#>          x      y cadmium copper lead zinc  elev     dist   om ffreq soil lime
#> 119 179717 331441     0.2     21   56  166 9.206 0.249852  4.1     2    2    0
#> 88  178912 330779     5.6     68  429 1136 6.420 0.070355  8.2     1    1    1
#> 16  180830 333246     9.5     86  240 1032 7.702 0.000000 16.2     1    1    1
#> 34  180954 332399     1.2     26   80  192 7.971 0.385807  1.9     1    2    0
#> 42  180494 332330     2.4     32  102  298 7.516 0.135709  1.4     1    2    0
#> 49  180282 331861     1.7     26  135  365 8.180 0.423826  4.9     1    2    0
#>     landuse dist.m
#> 119      Ah    310
#> 88        W    100
#> 16        W     10
#> 34        B    500
#> 42       Am    170
#> 49       Ah    480
# }
```
