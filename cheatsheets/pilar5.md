# Pilar 5 — Active Learning

Hybrid uncertainty + feature-space-diversity batch policy for
autonomous soil-sampling campaigns; logistical-cost-aware extension;
Physics-Informed rejection gates.

## Core API

```r
# Fit the AL backbone (a quantile-regression forest by default)
mod <- al_fit(
  labeled    = labelled_df,
  target     = "soc",
  covariates = c("elev", "slope", "twi"),
  coords     = c("lon", "lat"),
  num.trees  = 500L
)

# Query a batch of candidates from a pool
batch <- al_query(
  mod, candidates = pool_df,
  n        = 10L,
  strategy = "hybrid",     # or "uncertainty", "diverse", "cost"
  alpha    = 0.7
)

# Closed-loop run with an oracle function
loop <- al_loop(
  initial_labelled = init_df,
  candidates       = pool_df,
  target           = "soc",
  covariates       = c("elev", "slope"),
  coords           = c("lon", "lat"),
  oracle           = function(x) my_field_measurement(x),
  n_iter           = 5L, batch_size = 5L
)

# Posterior queries (BatchBALD-style mutual information)
post <- al_batchbald(
  mod, candidates = pool_df, n = 10L,
  K_mc = 50L
)
```

## v3.0.0 bridges

* `al_query_neural_operator()` (P8 × P5)
* `al_query_diffusion()` (P9 × P5)
* `al_query_bhs()` (P7 × P5; Thompson-sampling AL)

See `cheatsheets/pilar7.md`, `pilar8.md`, `pilar9.md`.

## Key references

* Settles (2009) *Active Learning Survey*.
* Minasny & McBratney (2006) cLHS.

## See also

* `vignette("pilar5-active-learning")` — full tutorial.
* `articles/pilar5-soilgrids-br.Rmd` — region-specific demo.
