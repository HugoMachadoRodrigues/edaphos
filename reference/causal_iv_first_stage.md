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

## Examples

``` r
# Relevance is the one IV assumption the data can actually check,
# so run the first stage before trusting any 2SLS point estimate.
set.seed(42)
n <- 300
mgmt      <- rnorm(n)
carbonate <- runif(n, 0, 12)   # parent-rock CaCO3, per cent
quarry_km <- runif(n, 1, 60)   # distance to the nearest lime quarry
clay      <- rnorm(n, 35, 8)   # exogenous control that also drives pH
ph <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km + 0.06 * clay +
      0.45 * mgmt + rnorm(n, 0, 0.25)
soil <- data.frame(ph, carbonate, quarry_km, clay,
                   rainfall_resid = rnorm(n))

fs <- causal_iv_first_stage(soil, exposure = "ph",
                            instruments = c("carbonate", "quarry_km"),
                            covariates = "clay")
c(F = fs$F, R2 = fs$R2, R2_partial = fs$R2_partial)
#>          F         R2 R2_partial 
#> 80.9710469  0.5787263  0.3536301 

# F = 81 clears the Stock-Yogo rule of thumb by a wide margin. The
# rule is not a significance test: F = 10 is roughly where 2SLS
# bias back towards OLS, and under-coverage of the nominal 95 per
# cent interval, stop being negligible.
fs$F > 10
#> [1] TRUE

# The trap: `R2` scores the WHOLE first stage, controls included,
# so it stays respectable even when the instruments are worthless.
# Replacing them with noise leaves R2 at 0.35 -- down from 0.58, but
# still the sort of number that reads as "the model fits", and all
# of it carried by clay. F and the partial R2 do not survive the
# substitution at all: 81 -> 0.33 and 0.354 -> 0.001. A drop of
# 40 per cent against drops of 245x and 320x is the whole point --
# only `R2_partial` and `F` speak to identification.
bad <- causal_iv_first_stage(soil, exposure = "ph",
                             instruments = "rainfall_resid",
                             covariates = "clay")
c(F = bad$F, R2 = bad$R2, R2_partial = bad$R2_partial)
#>           F          R2  R2_partial 
#> 0.330165277 0.348970414 0.001110433 

# `full_fit` is the fitted lm, so the individual first-stage slopes
# can be signed against agronomy: carbonate raises pH, distance to
# the quarry lowers it.
coef(fs$full_fit)
#>  (Intercept)         clay    carbonate    quarry_km 
#>  4.638072937  0.057186405  0.103831703 -0.009107511 
```
