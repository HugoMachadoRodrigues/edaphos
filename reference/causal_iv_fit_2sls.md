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
