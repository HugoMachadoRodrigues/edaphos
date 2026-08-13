# Skill against an explicit null predictor

\\\mathrm{NSE} = 1 - \frac{\sum (y - \hat y)^2}{\sum (y - y_0)^2}\\,
where \\y_0\\ is a null prediction the caller supplies. Zero means the
model is exactly as good as the null; negative means worse.

## Usage

``` r
edaphos_nse(observed, predicted, null_prediction)
```

## Arguments

- observed, predicted:

  Numeric vectors of equal length.

- null_prediction:

  The null predictor: either a single number (a constant null, e.g. the
  training-fold mean) or a vector the same length as `observed` (a
  varying null, e.g. a covariate-free baseline model).

## Value

Numeric scalar, or `NA_real_` when the null has zero residual variance
and the ratio is undefined.

## Details

[`edaphos_r2()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_r2.md)
is the special case \\y_0 = \bar y\\, the mean of the observations being
scored. On a held-out fold that is an **oracle**: no deployed map knows
the mean of the cells it has not visited. Scoring against it is a harder
and less meaningful bar than scoring against the mean of the training
fold, which is the null a practitioner could actually deploy.

The distinction is not academic. On this package's own six-method
benchmark, three methods score below zero against the oracle null and
only one scores below zero against the achievable one — and the
manuscript reported the former under the latter's name until this
function existed to keep them apart. `null_prediction` is mandatory here
for exactly that reason.

## See also

[`edaphos_r2()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_r2.md)

## Examples

``` r
obs   <- c(12.1, 18.4,  9.7, 22.0, 15.3)
pred  <- c(11.5, 19.2, 10.4, 20.8, 15.9)

# The achievable null: the mean of the training fold, known before the
# test rows are seen.
edaphos_nse(obs, pred, null_prediction = 14.8)
#> [1] 0.966548

# The oracle null, which is what edaphos_r2() uses. It is the harder bar,
# because the mean of the test set is the best constant predictor OF the
# test set -- so a method can clear the achievable null and fail this one.
edaphos_nse(obs, pred, null_prediction = mean(obs))
#> [1] 0.9656934
edaphos_r2(obs, pred)
#> [1] 0.9656934

# A method that beats the training mean but not the test mean: exactly the
# case that gets mislabelled when the two are conflated.
round(c(achievable = edaphos_nse(obs, pred, 14.8),
        oracle     = edaphos_nse(obs, pred, mean(obs))), 3)
#> achievable     oracle 
#>      0.967      0.966 
```
