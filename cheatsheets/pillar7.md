# Pillar 7 — Bayesian Hierarchical Spatial

Spatial linear model with a latent exponential-correlation Gaussian
process residual, fit via a profile-MLE for the GP rate `phi`
followed by a Gibbs sweep over `(beta, sigma^2, tau^2, w)`.

## Core API

```r
fit <- bhs_fit(
  data    = my_df,
  formula = soc ~ elev + slope + twi,
  coords  = c("lon", "lat"),
  backend = "rcpp",      # or "gibbs" (R fast-path), "spBayes"
  nmcmc   = 2000L,
  burn    = 1000L,
  phi_range = c(0.05, 5),
  seed    = 1L
)

# Posterior summary at new sites (Bayesian kriging)
pr <- predict(fit, newdata = new_df,
                quantiles = c(0.025, 0.5, 0.975),
                n_draws   = 200L)
pr$mean; pr$sd; pr$q2.5; pr$q97.5

# Wrap as the unified `edaphos_posterior`
post <- as_edaphos_posterior(fit)
uncertainty_calibrate(post, truth = test$soc)
```

## Backends

* `"gibbs"` — pure-R Gibbs (triangular-solve fast path).
  ~2.5x over the earlier dense-inverse path.
* `"rcpp"` — RcppArmadillo C++.  ~2-3x over the R fast
  path on n >= 200.
* `"spBayes"` — dispatch to `spBayes::spLM` (Suggests dependency).

## Bridge: `al_query_bhs()` (Pillar 7 × Pillar 5)

Thompson-sampling AL: ranks pool sites by predictive variance
averaged over MCMC draws.  See `cheatsheets/pillar5.md`.

## Key references

* Banerjee, Carlin & Gelfand (2014) *Hierarchical Modeling and
  Analysis for Spatial Data*.
* Finley, Banerjee & Carlin (2007) — spBayes JSS.

## See also

* `vignette("uncertainty-unified")` — `as_edaphos_posterior()`
  contract for BHS.
