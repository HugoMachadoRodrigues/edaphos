# Coefficient of determination (Nash-Sutcliffe efficiency)

\\R^2 = 1 - \frac{\sum (y - \hat y)^2}{\sum (y - \bar y)^2}\\. Ranges
from \\-\infty\\ to 1; negative values mean the predictor is worse than
the unconditional mean.

## Usage

``` r
edaphos_r2(observed, predicted)
```

## Arguments

- observed, predicted:

  Numeric vectors.

## Value

Numeric scalar.

## See also

[`edaphos_nse()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_nse.md),
which takes the null as an argument so the choice cannot be made
silently.

## Examples

``` r
obs  <- c(12.1, 18.4,  9.7, 22.0, 15.3)
pred <- c(11.5, 19.2, 10.4, 20.8, 15.9)

edaphos_r2(obs, pred)
#> [1] 0.9656934

# Negative R2 is not a bug: it means the model is worse than
# predicting the mean of `observed`.
edaphos_r2(obs, rep(30, length(obs)))
#> [1] -10.96194

# When scoring a held-out set, the denominator should be built from
# the TRAINING mean -- an achievable null -- not from mean(obs),
# which is an oracle no deployed map has access to.
train_mean <- 14.8
1 - sum((obs - pred)^2) / sum((obs - train_mean)^2)
#> [1] 0.966548
```
