# First-stage regression diagnostics for an IV design

Regresses the endogenous exposure on instruments + controls and reports
the F-statistic for the joint significance of the INSTRUMENTS (controls
partialed out), the partial R-squared, and the overall R-squared. Stock
& Yogo (2005) recommend F \> 10 as a rule of thumb to avoid
weak-instrument bias.

## Usage

``` r
causal_iv_first_stage(data, exposure, instruments, covariates = NULL)
```

## Arguments

- data:

  A data frame.

- exposure:

  Character; name of the endogenous exposure column.

- instruments:

  Character vector; names of instrument columns. More instruments than
  exposures gives an over-identified model on which the Sargan test is
  applicable.

- covariates:

  Optional character vector of exogenous-control column names included
  in both first and second stage.

## Value

Named list with `F`, `F_pvalue`, `R2`, `R2_partial`.
