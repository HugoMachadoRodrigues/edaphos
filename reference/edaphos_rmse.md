# Root-mean-square error

\\\mathrm{RMSE} = \sqrt{\frac{1}{n} \sum_i (y_i - \hat y_i)^2}\\.

## Usage

``` r
edaphos_rmse(observed, predicted)
```

## Arguments

- observed:

  Numeric vector of observed values.

- predicted:

  Numeric vector of predicted values.

## Value

Non-negative numeric scalar.

## Examples

``` r
obs  <- c(12.1, 18.4,  9.7, 22.0, 15.3)
pred <- c(11.5, 19.2, 10.4, 20.8, 15.9)

edaphos_rmse(obs, pred)
#> [1] 0.811172

# RMSE is in the units of the response and penalises large errors
# quadratically, so a single bad site dominates it.
pred_one_blunder <- pred
pred_one_blunder[3] <- 30
c(mae = edaphos_mae(obs, pred_one_blunder),
  rmse = edaphos_rmse(obs, pred_one_blunder))
#>      mae     rmse 
#> 4.700000 9.109226 
```
