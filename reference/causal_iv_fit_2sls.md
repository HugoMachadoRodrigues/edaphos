# Two-stage least squares (2SLS) instrumental variable estimator

Estimates the causal effect of an endogenous exposure `exposure` on an
outcome `outcome` using one or more instruments, optionally conditional
on exogenous controls. Implements the classical 2SLS estimator with the
Wooldridge (2010) asymptotic variance – the naive
[`lm()`](https://rdrr.io/r/stats/lm.html) SE of the second stage is
biased because it treats the generated regressor as observed, a common
mistake.

## Usage

``` r
causal_iv_fit_2sls(data, exposure, outcome, instruments, covariates = NULL)
```

## Arguments

- data:

  A data frame.

- exposure:

  Character; name of the endogenous exposure column.

- outcome:

  Character; name of the outcome column.

- instruments:

  Character vector; names of instrument columns. More instruments than
  exposures gives an over-identified model on which the Sargan test is
  applicable.

- covariates:

  Optional character vector of exogenous-control column names included
  in both first and second stage.

## Value

An `edaphos_causal_iv` object with components `effect`, `se`, `ci`,
`stage1_F`, `stage1_R2`, `sargan_p` (NULL if exactly identified), `n`,
plus auxiliary fits for inspection.

## Details

### Formal setup

Let

- `X` be the endogenous exposure (one column),

- `Z` the matrix of instruments,

- `W` the matrix of exogenous controls (included in both stages).

Define the augmented matrices `X_all = [W, X]` and `Z_all = [W, Z]` and
the projection `P = Z_all (Z_all' Z_all)^-1 Z_all'`. The 2SLS estimator
is

\$\$\hat{\beta} = (X\_{\text{all}}^\top P X\_{\text{all}})^{-1}
X\_{\text{all}}^\top P Y\$\$

with residuals computed using the ORIGINAL `X_all`, not the first-stage
fitted values, so that

\$\$\hat{\sigma}^2 = (Y - X\_{\text{all}} \hat{\beta})^\top (Y -
X\_{\text{all}} \hat{\beta}) / (n - k)\$\$
\$\$\widehat{\mathrm{Var}}(\hat{\beta}) = \hat{\sigma}^2
(X\_{\text{all}}^\top P X\_{\text{all}})^{-1}\$\$

Identification conditions (Wooldridge 2010, section 5.1):

- Relevance: \\\mathrm{rank}(Z' X) = \dim(X)\\; the first-stage
  F-statistic should exceed 10 (Stock & Yogo 2005).

- Exclusion: \\Z\\ affects \\Y\\ only through \\X\\.

- Unconfoundedness: \\Z \perp U\\ where \\U\\ is any unobserved
  confounder.

## Examples

``` r
# A liming study confounded by management: unobserved agronomic
# intensity raises both soil pH and yield, so no regression of
# yield on pH can identify the causal effect.
set.seed(42)
n <- 300
mgmt      <- rnorm(n)          # unobserved agronomic intensity
carbonate <- runif(n, 0, 12)   # parent-rock CaCO3, per cent
quarry_km <- runif(n, 1, 60)   # distance to the nearest lime quarry
ph    <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km +
         0.45 * mgmt + rnorm(n, 0, 0.25)
yield <- 1.0 + 1.5 * ph + 1.3 * mgmt + rnorm(n, 0, 0.4)
soil  <- data.frame(ph, yield, carbonate, quarry_km)

# The true effect is 1.5 t/ha per pH unit. OLS returns 2.85 --
# nearly double -- because it credits pH with the yield that
# management delivered.
ols <- lm(yield ~ ph, data = soil)
coef(ols)[["ph"]]
#> [1] 2.852879

# 2SLS uses only the pH variation forced by geology, which
# management cannot touch: 1.62, with a 95 per cent interval that
# covers 1.5.
fit <- causal_iv_fit_2sls(soil, exposure = "ph", outcome = "yield",
                          instruments = c("carbonate", "quarry_km"))
fit
#> <edaphos_causal_iv>
#>   ph -> yield  (estimator: 2SLS, n = 300)
#>   instruments : carbonate, quarry_km
#>   effect      : 1.6161  (se = 0.1758, 95% CI [1.2715, 1.9606])
#>   stage-1 F   : 116.23 (p = 5.18e-38)  partial R^2 = 0.439
#>   Sargan J    : chi2(1) = 0.27, p = 0.604

# Consistency is bought with variance: the IV standard error here
# is about twice the OLS one. Quoting the narrow OLS interval
# around the wrong number is what this estimator exists to avoid.
c(ols = summary(ols)$coefficients["ph", "Std. Error"], iv = fit$se)
#>        ols         iv 
#> 0.09183934 0.17579015 

# `effect` is the exposure coefficient alone; `coefs` carries the
# whole second-stage vector and `vcov` its 2SLS covariance -- not
# the naive lm() covariance of a regression on fitted values.
fit$coefs
#> intercept        ph 
#> 0.4044785 1.6160522 
sqrt(diag(fit$vcov))
#> intercept        ph 
#> 0.8615058 0.1757901 
```
