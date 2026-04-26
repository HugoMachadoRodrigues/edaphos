# Cinelli & Hazlett (2020) sensitivity summary for a causal effect

Computes the **Robustness Value (RV)**: the minimum partial R-squared
(on *both* exposure and outcome, with the observed adjustments partialed
out) that an unobserved confounder U would need to have to bring the
estimate to zero (`q = 1`) or reduce it by a fraction `q` of its
magnitude. Also reports the **RV at 5% significance** (RV_q): the
minimum R-squared to push the t-ratio below the critical value.

## Usage

``` r
causal_sensitivity_summary(effect, se, df, q = 1, alpha = 0.05)
```

## Arguments

- effect:

  Numeric; point estimate of the causal effect.

- se:

  Numeric; standard error of the estimate.

- df:

  Numeric; degrees of freedom (n - k - 1).

- q:

  Numeric; the fraction of the estimate we want to neutralise. `q = 1`
  is zero-out; `q = 0.5` is half-reduction.

- alpha:

  Significance level for RV_alpha (default `0.05`).

## Value

Named list with `rv`, `rv_alpha`, `t_stat`, and a verbal interpretation.

## Details

Interpretation: if RV = 0.10, then any confounder explaining more than
10 percent of the residual variance in both X and Y (jointly) would be
enough to kill the effect. Small RV = fragile estimate.

## Examples

``` r
# A 2SLS effect of beta = 0.008, SE = 0.003, df = 1080:
causal_sensitivity_summary(0.008, 0.003, 1080)
#> $effect
#> [1] 0.008
#> 
#> $se
#> [1] 0.003
#> 
#> $df
#> [1] 1080
#> 
#> $t_stat
#> [1] 2.666667
#> 
#> $rv
#> [1] 0.07791866
#> 
#> $rv_alpha
#> [1] 0.02120882
#> 
#> $q
#> [1] 1
#> 
#> $alpha
#> [1] 0.05
#> 
#> $interpretation
#> [1] "An unobserved confounder explaining 7.8% of the residual variance in BOTH X and Y would suffice to zero out the estimate. At the 95% significance threshold, 2.1% is enough to make the result statistically insignificant."
#> 
```
