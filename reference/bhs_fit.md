# Fit a Bayesian hierarchical spatial linear model (Pilar 7)

The v2.3.0 activation of the Pilar 7 scaffold. Fits a Bayesian spatial
linear model `y_i = x_i' beta + w_i + eps_i` with a latent
exponential-correlation Gaussian process on the residual field and
returns full posterior draws.

## Usage

``` r
bhs_fit(
  data,
  formula,
  coords = c("lon", "lat"),
  backend = c("gibbs", "rcpp", "spBayes"),
  nmcmc = 2000L,
  burn = NULL,
  thin = 1L,
  prior_var_beta = 1000,
  prior_ig_a = 2,
  prior_ig_b = 1,
  phi_range = c(0.01, 10),
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- data:

  A data frame with the response + covariates + spatial coordinates.

- formula:

  A `response ~ covariates` formula.

- coords:

  Character length-2 (default `c("lon", "lat")`) giving the coordinate
  columns.

- backend:

  One of `"gibbs"` (pure-R Gibbs sampler, default, no external deps),
  `"spBayes"` (dispatches to
  [`spBayes::spLM`](https://rdrr.io/pkg/spBayes/man/spLM.html) when
  available).

- nmcmc:

  Integer; number of MCMC iterations. Default `2000L`.

- burn:

  Integer; burn-in to discard. Default `nmcmc %/% 2`.

- thin:

  Integer; keep every `thin`-th post-burn draw. Default `1L`.

- prior_var_beta:

  Numeric; Gaussian prior variance on `beta`.

- prior_ig_a, prior_ig_b:

  Shape and scale of the inverse-Gamma priors on `sigma^2` and `tau^2`.

- phi_range:

  Numeric length-2; bracket for the profile-MLE of the GP rate parameter
  `phi`. Default `c(0.01, 10)`.

- seed:

  Optional RNG seed.

- verbose:

  Logical.

## Value

An `edaphos_bhs` S3 object.
