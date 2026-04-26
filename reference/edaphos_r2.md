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
