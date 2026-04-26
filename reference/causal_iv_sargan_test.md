# Sargan test for instrument over-identification

When the model is over-identified (more instruments than endogenous
exposures), the Sargan (1958) J-statistic tests the null hypothesis that
all instruments are valid (i.e., the exclusion restriction holds). The
statistic is

## Usage

``` r
causal_iv_sargan_test(data, exposure, outcome, instruments, covariates = NULL)
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

Named list with `stat`, `df`, `p`.

## Details

\$\$J = n \cdot R^2\_{uu}\$\$

where `R^2_uu` is the R-squared of regressing the 2SLS residuals on all
instruments (and controls). Under H0, `J ~ chi-sq(L - K)` where `L` is
the number of instruments and `K` is the number of endogenous
regressors. Rejection (p \< 0.05) is evidence that at least one
instrument is invalid.
