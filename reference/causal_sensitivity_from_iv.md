# Sensitivity analysis of an `edaphos_causal_iv` fit

The 2SLS estimator of
[`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md)
is consistent when IV conditions hold. This wrapper gives a classical
Cinelli-Hazlett envelope **treating the 2SLS estimate AS IF it were a
backdoor OLS estimate**. This is a conservative sensitivity check: the
IV effect is bias-adjusted against a hypothetical remaining confounder U
that affects BOTH the exposure and the outcome **after** the instruments
have been projected out. It is the right envelope to report alongside
the Sargan test.

## Usage

``` r
causal_sensitivity_from_iv(fit, q = 1, alpha = 0.05)
```

## Arguments

- fit:

  An `edaphos_causal_iv` object.

- q, alpha:

  See
  [`causal_sensitivity_summary()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_summary.md).

## Value

List identical to
[`causal_sensitivity_summary()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_summary.md)
with an extra `fit_estimator` field.

## Examples

``` r
# A liming trial where the ASSIGNED rate was randomised but the
# APPLIED rate was not: growers on clay-rich plots limed more, and
# clay content raises SOC on its own.  Clay is never measured; the
# assigned rate is the instrument.
set.seed(42)
n        <- 400
clay     <- stats::rnorm(n)
assigned <- stats::rnorm(n)
applied  <- 0.8 * assigned + 0.9 * clay + stats::rnorm(n)
soc      <- 1.5 * applied + 1.2 * clay + stats::rnorm(n)
trial    <- data.frame(assigned, applied, soc)

ols <- lm(soc ~ applied, data = trial)
iv  <- causal_iv_fit_2sls(trial, exposure = "applied",
                          outcome = "soc", instruments = "assigned")

# OLS is biased upwards (1.922 against a true effect of 1.5) and
# 2SLS recovers 1.533.  Now compare the two robustness values.
pick <- c("effect", "se", "rv")
round(rbind(
  ols = unlist(causal_sensitivity_from_lm(ols, "applied")[pick]),
  iv  = unlist(causal_sensitivity_from_iv(iv)[pick])
), 3)
#>     effect    se    rv
#> ols  1.922 0.043 0.855
#> iv   1.533 0.098 0.535

# Trap: the RV rewards precision, not correctness.  The confounded
# OLS estimate scores 0.855 and the consistent 2SLS estimate only
# 0.535, purely because instrumenting more than doubled the standard
# error.  Read this wrapper's RV as "how much confounding survives
# the instruments", never as a ranking of the two estimators.

# The one structural difference from the `lm` wrapper is the
# recorded estimator label.
causal_sensitivity_from_iv(iv)$fit_estimator
#> [1] "2SLS"
```
