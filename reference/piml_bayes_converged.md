# Did this MCMC fit converge?

The single verdict function for
[`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md).
Every call site asks this rather than re-deriving the threshold rule –
which is how the same inverted comparison came to sit in five places at
once.

## Usage

``` r
piml_bayes_converged(fit, rhat_max = 1.01, ess_min = 400, accept_min = 0.005)
```

## Arguments

- fit:

  An `edaphos_piml_bayes` object.

- rhat_max:

  Numeric; the split-\\\hat{R}\\ ceiling. Default 1.01.

- ess_min:

  Numeric; the bulk-ESS floor. Default 400.

- accept_min:

  Numeric; an acceptance rate below this is reported in its own right,
  because a frozen chain is easier to recognise from its acceptance rate
  than from a diagnostic. Default 0.005.

## Value

A list with `ok` (logical, or `NA` when the object carries no MCMC
diagnostics), `reasons` (character; empty when `ok`) and `caveats`
(character; conditions that qualify the result without disqualifying it,
such as an effective sample size that is an upper bound).

## Why the comparison was inverted

Split-\\\hat{R}\\ is undefined for a chain that never moved (Vehtari et
al. 2021), and `.piml_rhat_ess()` correctly returned `NA` for it. But
`NA` does not survive R's reductions in the direction a diagnostic
needs: `max(x, na.rm = TRUE)` over an all-`NA` vector empties the
argument set and returns \\-\infty\\, the identity element of the
maximum over an empty set; `min` likewise returns \\+\infty\\. Both sit
on the PASSING side of a one-sided threshold, so a chain with an
acceptance rate of 0.00 was certified as converged. On a 60-profile
sample of the shipped WoSIS extract, a quarter of every positive verdict
was of that kind.

The diagnostics now encode an uncomputable statistic as \\\hat{R} =
\infty\\ and ESS \\= 0\\, so every reduction fails on it, and this
function reads them without `na.rm`.

## References

Vehtari A, Gelman A, Simpson D, Carpenter B, Bürkner P-C (2021).
Rank-normalization, folding, and localization: an improved \\\hat{R}\\
for assessing convergence of MCMC. *Bayesian Analysis* 16:667-718.

## See also

[`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md)

## Examples

``` r
# A frozen chain: R-hat is undefined, and the verdict says so rather than
# letting an empty-set reduction turn it into a pass.
frozen <- lapply(1:4, function(k) matrix(rep(k, 400), 200, 2))
dg <- edaphos:::.piml_rhat_ess(frozen)
dg$rhat          # Inf, not NA
#> [1] Inf Inf
max(dg$rhat, na.rm = TRUE) > 1.01   # TRUE -- this used to be FALSE
#> [1] TRUE
```
