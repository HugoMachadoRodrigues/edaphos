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
  method = c("laplace", "mcmc"),
  prior = NULL,
  start = NULL,
  control = list(maxit = 2000),
  n_iter = 5000L,
  n_burn = 2000L,
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

- method:

  One of `"laplace"` (default) or `"mcmc"`.

- prior:

  Named list of hyperparameters for the priors. See the source for the
  default structure (fields `log_lambda0_mean`, `log_lambda0_sd`,
  `mu_sd`, `y_inf_mean`, `y_inf_sd`, `y0_mean`, `y0_sd`).

- start:

  Optional starting vector. Defaults to
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)'s
  point-estimate theta for the MAP search.

- control:

  `optim` control list for the MAP step.

- n_iter, n_burn, thin, seed:

  MCMC settings. Only consulted when `method = "mcmc"`.

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
fit_bayes <- piml_profile_fit_bayesian(depths, values)
fit_bayes
#> <edaphos_piml_bayes>
#>   method     : laplace
#>   n draws    : 2000
#>   sigma (noise): 0.1653
#>   posterior summary (natural scale):
#>  parameter      mean       sd      q2.5       q50    q97.5
#>    lambda0  0.049372 0.002535  0.044675  0.049299  0.05443
#>         mu  0.004418 0.005045 -0.005313  0.004254  0.01431
#>      y_inf  6.093350 0.470976  5.151652  6.104465  6.99052
#>         y0 30.249753 0.446190 29.368545 30.234666 31.14010
summary(fit_bayes)
#>   parameter         mean          sd         q2.5         q50       q97.5
#> 1   lambda0  0.049372224 0.002535136  0.044675167  0.04929949  0.05443345
#> 2        mu  0.004418308 0.005045119 -0.005313292  0.00425414  0.01430524
#> 3     y_inf  6.093350122 0.470975653  5.151652473  6.10446482  6.99052275
#> 4        y0 30.249753364 0.446190249 29.368544610 30.23466595 31.14010333
```
