# Pilar 2 — Physics-Informed ML (depth-profile ODE)

Soil depth profiles modelled with a parametric pedogenetic ODE:

  dy/dz = -lambda0 * exp(-mu * z) * (y - y_inf)

Frequentist Nelder-Mead fit + a Bayesian Laplace / MH variant.

## Core API

```r
# Frequentist single-pedon fit
fit <- piml_profile_fit(
  depths = c(5, 15, 30, 60, 100),
  values = c(25, 18, 12, 8, 6.5),
  reg    = 1e-3
)
fit$params      # list(lambda0, mu, y_inf, y0)
predict(fit, newdepths = c(10, 50))

# Bayesian posterior with priors
fit_b <- piml_profile_fit_bayesian(
  depths, values,
  prior  = piml_default_prior(values, depths),
  method = "laplace"  # or "mh"
)
predict(fit_b, newdepths = c(10, 50))   # MAP + posterior summary

# Hierarchical fit across many pedons (covariate-conditioned)
fit_h <- piml_hierarchical_fit(
  data = pedon_long_df,
  id    = "profile_id",
  depth = "depth_cm",
  value = "soc",
  cov_pool = c("lon", "lat", "map_mm")
)
```

## v3.0.0 bridge: `temporal_piml_loss()` (Pilar 2 × Pilar 3)

Returns a `function(y_pred, y_true, driver)` closure for use as the
`physics_loss_fn` of `temporal_convlstm_fit()`, penalising
predictions that violate the local-rate kinetics inferred from the
ODE fit.

## Key references

* Minasny & McBratney (2006) — pedogenetic depth functions.
* Karpatne et al. (2017) — physics-informed machine learning.

## See also

* `vignette("pilar2-piml-profile")` — full tutorial.
* `vignette("uncertainty-unified")` — `as_edaphos_posterior()` for
  Bayesian fits.
