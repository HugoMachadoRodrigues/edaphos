# Mean absolute error

Mean absolute error

## Usage

``` r
edaphos_mae(observed, predicted)
```

## Arguments

- observed, predicted:

  Numeric vectors.

## Value

Non-negative numeric scalar.

## Examples

``` r
obs  <- c(12.1, 18.4,  9.7, 22.0, 15.3)
pred <- c(11.5, 19.2, 10.4, 20.8, 15.9)

edaphos_mae(obs, pred)
#> [1] 0.78

# Report MAE alongside RMSE: MAE >> RMSE is impossible, while
# RMSE >> MAE tells you the error is concentrated in a few sites.
c(mae = edaphos_mae(obs, pred), rmse = edaphos_rmse(obs, pred))
#>      mae     rmse 
#> 0.780000 0.811172 
```
