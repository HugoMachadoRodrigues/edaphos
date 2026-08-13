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

## Examples

``` r
# `carb_direct` and `quarry_direct` let an instrument reach yield
# WITHOUT going through pH, i.e. break the exclusion restriction.
sim_liming <- function(seed = 42, carb_direct = 0,
                       quarry_direct = 0) {
  set.seed(seed)
  n <- 300
  mgmt      <- rnorm(n)
  carbonate <- runif(n, 0, 12)
  quarry_km <- runif(n, 1, 60)
  ph    <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km +
           0.45 * mgmt + rnorm(n, 0, 0.25)
  yield <- 1.0 + 1.5 * ph + 1.3 * mgmt + rnorm(n, 0, 0.4) +
           carb_direct * carbonate + quarry_direct * quarry_km
  data.frame(ph, yield, carbonate, quarry_km)
}
soil <- sim_liming()

# The test needs MORE instruments than endogenous exposures. One
# instrument for one exposure is exactly identified: there is
# nothing to over-identify, and you get NA rather than a
# reassuring p-value.
causal_iv_sargan_test(soil, "ph", "yield", instruments = "carbonate")
#> $stat
#> [1] NA
#> 
#> $df
#> [1] 0
#> 
#> $p
#> [1] NA
#> 

# Two instruments, both valid by construction: J = 0.27 on 1 df,
# p = 0.60, no evidence against the exclusion restriction.
causal_iv_sargan_test(soil, "ph", "yield",
                      instruments = c("carbonate", "quarry_km"))
#> $stat
#> [1] 0.2685378
#> 
#> $df
#> [1] 1
#> 
#> $p
#> [1] 0.6043143
#> 

# Let carbonate fertilise the crop directly, breaking exclusion for
# that instrument only. The two instruments now disagree about the
# effect and the test fires: J = 19.6, p = 9.4e-06.
causal_iv_sargan_test(sim_liming(carb_direct = 0.15), "ph", "yield",
                      instruments = c("carbonate", "quarry_km"))
#> $stat
#> [1] 19.63545
#> 
#> $df
#> [1] 1
#> 
#> $p
#> [1] 9.371428e-06
#> 

# What a non-rejection does NOT prove. Break BOTH instruments in
# proportion to their first-stage strength and they agree on the
# same wrong answer, so Sargan sees no conflict (p = 0.92) while
# 2SLS returns 2.93 against a truth of 1.5. The J-statistic
# compares instruments with each other; a bias they share is
# invisible to it, and no over-identification test can license the
# exclusion restriction on its own.
soil_worse <- sim_liming(carb_direct = 0.15, quarry_direct = -0.015)
causal_iv_sargan_test(soil_worse, "ph", "yield",
                      instruments = c("carbonate", "quarry_km"))$p
#> [1] 0.9240283
causal_iv_fit_2sls(soil_worse, "ph", "yield",
                   instruments = c("carbonate", "quarry_km"))$effect
#> [1] 2.934698
```
