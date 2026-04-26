# Fit a Quantile Regression Forest for Active Learning

Fits a Quantile Regression Forest (Meinshausen 2006) on the currently
labeled soil dataset, using `ranger::ranger(..., quantreg = TRUE)`. The
resulting object carries the data, model, and an initial history entry
and is the value on which
[`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md),
[`al_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_update.md)
and
[`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md)
operate.

## Usage

``` r
al_fit(labeled, target, covariates, coords = NULL, num.trees = 500L, ...)
```

## Arguments

- labeled:

  Data frame with observed target + covariates (+ optional coordinates).

- target:

  Character, name of the target column.

- covariates:

  Character vector of covariate column names.

- coords:

  Optional length-2 character vector naming the x/y coordinate columns.
  Required by the `"cost"` query strategy.

- num.trees:

  Integer, number of trees (default 500).

- ...:

  Additional arguments forwarded to
  [`ranger::ranger()`](http://imbs-hl.github.io/ranger/reference/ranger.md).

## Value

A `edaphos_al_model` object.

## References

Meinshausen N (2006). Quantile Regression Forests. *Journal of Machine
Learning Research* 7, 983-999.

## Examples

``` r
# \donttest{
  if (requireNamespace("sp", quietly = TRUE)) {
    data(meuse, package = "sp")
    m <- al_fit(
      labeled    = stats::na.omit(meuse[1:30, ]),
      target     = "lead",
      covariates = c("dist", "elev"),
      coords     = c("x", "y")
    )
    m
  }
#> <edaphos_al_model>
#>   target     : lead 
#>   covariates : dist, elev 
#>   coords     : x, y 
#>   n labeled  : 29 
#>   iterations : 0 
#>   last RMSE  : 41.99 
# }
```
