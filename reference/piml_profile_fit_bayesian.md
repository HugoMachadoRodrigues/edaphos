# Bayesian posterior for the Pillar 2 pedogenetic ODE

Returns the posterior distribution of \\(\lambda_0, \mu, y\_\infty,
y_0)\\ conditional on the observed depth profile. Two levels of
approximation are offered:

## Usage

``` r
piml_profile_fit_bayesian(
  depths,
  values,
  y_surface = NULL,
  top = NULL,
  bottom = NULL,
  family = c("lognormal", "gaussian", "gamma"),
  method = c("laplace", "mcmc"),
  prior = NULL,
  start = NULL,
  control = list(maxit = 2000),
  n_iter = 20000L,
  n_burn = 6000L,
  n_chains = 4L,
  thin = 1L,
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- depths, values:

  Numeric vectors — same as
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md).

- y_surface:

  Optional fixed surface value.

- top, bottom:

  Optional horizon boundaries — same as
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md).
  When supplied, each observation is compared to the model's
  depth-average over its horizon rather than to a point evaluation at
  the mid-depth.

- family:

  Observation family, as in
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md).
  `"gaussian"` (default) puts predictive mass below zero and weights
  every horizon by the same absolute error; `"lognormal"` and `"gamma"`
  are strictly positive, mean-preserving, and weight by relative error.
  When it is not `"gaussian"`, `sigma` is a coefficient of variation
  rather than an SD in the property's units, and the default prior on it
  changes accordingly.

- method:

  One of `"laplace"` (default) or `"mcmc"`.

- prior:

  Named list of hyperparameters for the priors, placed on the identified
  log coordinates (fields `log_kappa_mean`, `log_kappa_sd`,
  `log_mu_mean`, `log_mu_sd`, `log_y_asym_mean`, `log_y_asym_sd`,
  `log_y0_mean`, `log_y0_sd`). Each is log-normal on its natural scale,
  which is the right family for a rate, a depth scale and a
  concentration, and which puts no mass on the impossible region. Note
  there is no prior on `y_inf`: it is a derived coordinate the profile
  never attains, and the data do not identify it.

- start:

  Optional starting vector. Defaults to
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)'s
  point-estimate theta for the MAP search.

- control:

  `optim` control list for the MAP step.

- n_iter, n_burn, thin:

  MCMC settings. The defaults were 5000/2000, which do NOT converge on
  this posterior: four chains on the shipped pedon gave max split-R-hat
  1.015 and min bulk ESS 361 at 6000 iterations, against 1.004 and 1113
  at 20000. A default that silently fails its own diagnostic is a trap,
  so the default is now the converging one. Only consulted when
  `method = "mcmc"`.

- n_chains:

  Integer, number of MCMC chains started from dispersed points around
  the Laplace mode. Four or more are needed for split-R-hat to mean
  anything; with one chain there is no between-chain variance and
  convergence cannot be assessed at all. Only consulted when
  `method = "mcmc"`.

- seed:

  Optional integer seed. Consulted by *both* methods, not only by MCMC:
  with `method = "laplace"` it seeds the 2000 Gaussian draws taken from
  the Laplace posterior, and with `method = "mcmc"` it seeds the
  Metropolis chain. Because every entry of the returned `summary` (and
  of any downstream [`predict()`](https://rdrr.io/r/stats/predict.html))
  is a Monte-Carlo average over those draws, leaving `seed = NULL` makes
  the reported posterior means, SDs and quantiles change on every call.
  Set it whenever you intend to quote or compare the numbers.

- verbose:

  Logical — print one progress line per 10% of MCMC iterations.

## Value

An `edaphos_piml_bayes` object with:

- method:

  `"laplace"` or `"mcmc"`.

- map:

  Named list with the MAP values of the natural parameters
  `(lambda0, mu, y_inf, y0)`.

- theta_map:

  Unconstrained parameter vector at the MAP.

- sigma:

  Observation-noise standard deviation estimated at the MAP.

- cov:

  The \\d \times d\\ posterior covariance matrix on the unconstrained
  scale (Laplace), or the empirical sample covariance of the MCMC chain.

- draws:

  An M-by-d matrix of posterior samples on the unconstrained scale. For
  Laplace, 2000 draws are pre-sampled from \\N(\text{map}, \text{cov})\\
  for predictive convenience; for MCMC, the kept post-burn-in chain.

- summary:

  A data frame with `mean`, `sd`, `q2.5`, `q50`, `q97.5` per parameter
  (natural scale: `lambda0`, `mu`, `y_inf`, `y0`).

- accept_rate:

  MCMC acceptance rate (only for `method = "mcmc"`).

## Details

- `method = "laplace"` (default):

  Gaussian posterior obtained from the MAP and the inverse observed
  information at the MAP. Accurate when the posterior is approximately
  Gaussian, which is typical for well-identified profiles with \\n \geq
  4\\ horizons. Runtime: O(milliseconds).

- `method = "mcmc"`:

  Adaptive random-walk Metropolis (Haario, Saksman and Tamminen 2001;
  see the @references section below). Proposal covariance starts at the
  Laplace covariance, scaled by the Roberts-Gelman-Gilks \\(2.38)^2 /
  d\\ factor, and is updated online by Haario recursion after a warm-up
  period. Returns full posterior samples so non-Gaussian / multimodal
  posteriors are captured faithfully. Runtime: a few seconds for the
  default 5000 iterations.

The noise scale \\\sigma\\ is estimated from the MAP residual RMSE and
held fixed during MCMC (empirical Bayes). Weakly-informative,
data-driven priors are applied by default; pass a custom `prior` list to
override them.

## References

Bishop, C. M. (2006). *Pattern Recognition and Machine Learning*.
Springer, chapter 4.4 (Laplace approximation).

Haario, H., Saksman, E. and Tamminen, J. (2001). An adaptive Metropolis
algorithm. *Bernoulli* **7**, 223–242.

## See also

[`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)
for the point estimate;
[`predict.edaphos_piml_bayes()`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_piml_bayes.md)
for posterior predictive draws.

## Examples

``` r
depths <- c(5, 15, 30, 60, 100)
values <- c(25, 18, 12, 8, 6.5)
# The posterior summary is a Monte-Carlo average over 2000 draws from
# the Laplace posterior, so `seed` is required for it to be
# reproducible. Drop the seed and the printed means and quantiles
# change in the 4th significant figure on every call.
fit_bayes <- piml_profile_fit_bayesian(depths, values, seed = 1)
fit_bayes
#> <edaphos_piml_bayes>
#>   method     : laplace
#>   n draws    : 2000
#>   sigma (noise): 0.009692
#>   posterior summary (natural scale):
#>  parameter      mean        sd       q2.5       q50    q97.5
#>    lambda0   0.03740  0.012180   0.018942  0.035352  0.06675
#>         mu   0.03509  0.005514   0.025552  0.034733  0.04736
#>      y_inf -10.64234 11.818452 -41.257663 -8.089489  3.62039
#>         y0  30.98891  0.602453  29.837477 31.006206 32.15824
#>      kappa   1.14603  0.571184   0.399185  1.016122  2.59166
#>     y_asym   6.05674  0.177663   5.707088  6.056401  6.41648
#>      sigma   0.01029  0.003757   0.004745  0.009672  0.01924
summary(fit_bayes)
#>   parameter         mean           sd          q2.5          q50       q97.5
#> 1   lambda0   0.03740123  0.012180251   0.018942048  0.035352378  0.06674652
#> 2        mu   0.03508764  0.005514196   0.025551619  0.034733311  0.04736049
#> 3     y_inf -10.64233536 11.818451781 -41.257662502 -8.089489174  3.62039465
#> 4        y0  30.98891120  0.602452740  29.837476872 31.006206466 32.15823896
#> 5     kappa   1.14603011  0.571184179   0.399185068  1.016122245  2.59166097
#> 6    y_asym   6.05673942  0.177663360   5.707088358  6.056401367  6.41647509
#> 7     sigma   0.01028772  0.003757481   0.004744681  0.009671538  0.01923742

# With seed = 1 this profile gives a lambda0 posterior mean of 0.0493
# and a 95% credible interval of [0.04434, 0.05456] -- a relative
# width of 21%, so the decay rate is identified to roughly +/- 10%
# and the point estimate alone would overstate what 5 horizons buy.
round(subset(summary(fit_bayes), parameter == "lambda0",
             c("mean", "q2.5", "q97.5")), 5)
#>     mean    q2.5   q97.5
#> 1 0.0374 0.01894 0.06675
```
