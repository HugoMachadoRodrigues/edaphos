# edaphos v1.6.0 — Unified Uncertainty Across the Six Pillars

**Status:** draft for Hugo's review (2026-04-23). Not yet a commitment.

## 1. Problem statement

Every pillar currently reports uncertainty in a different format, each
with its own semantics, units, and calibration baseline. A soil
scientist consuming `edaphos` cannot combine them into a single
decision-useful statement. Concretely, as of v1.5.0:

| Pillar | What "uncertainty" means today | Format |
|:---|:---|:---|
| 1. Causal AI | CI on an identified direct effect | `confint.lm()` OR `effect_boot_ci` vector |
| 2. PIML | MCMC draws on kinetic parameters | per-parameter posterior (`_bayes` fits) |
| 3. 4D Pedometry | ensemble forecast + Kalman posterior | `K × H × W × T` arrays |
| 4. Foundation Models | *none* | deterministic encoder |
| 5. Active Learning | QRF prediction interval | `lower`, `upper` columns |
| 6. Quantum ML | shot-based VQE error bars | per-iteration variance |

This is a genuinely hard problem — the pillars estimate different
things (an effect, a parameter, a map, a feature, a sample, a
molecular energy) — but they all boil down to **a posterior over a
scalar or vector quantity conditional on data and the fitted model**.
v1.6.0 exposes that posterior through a single API, adds the
missing inference-time uncertainty to pillars 4 and 6, and ships
calibration + plotting helpers that work for every pillar.

## 2. Core design: the unified posterior object

### 2.1 Class `edaphos_posterior`

A minimal S3 object carrying a predictive posterior for one or more
queries. Every pillar's predict-with-uncertainty wrapper returns one.

```r
structure(
  list(
    mean         = ...,       # point estimate, same shape as query
    sd           = ...,       # predictive standard deviation
    samples      = ...,       # (n_samples × ...) array of draws
    epistemic_sd = ...,       # model-uncertainty component
    aleatoric_sd = ...,       # data-noise component
    quantiles    = list(      # named list of quantile arrays
      q05 = ..., q50 = ..., q95 = ...
    ),
    method       = "...",     # "ensemble" | "bootstrap" |
                              #  "mcdropout" | "bayesian" |
                              #  "loo_cv" | "shots"
    query_type   = "...",     # "effect" | "param" | "map" |
                              #  "feature" | "sample" | "energy"
    units        = "...",     # human-readable units
    metadata     = list(...)
  ),
  class = "edaphos_posterior"
)
```

Invariants:

1. `mean` and `sd` always have the same shape as the user's query.
2. `samples` is always `(n_samples, then_query_shape)` — the first
   axis is always the posterior-draw axis.
3. `epistemic_sd^2 + aleatoric_sd^2 ≈ sd^2` (the variance
   decomposition holds approximately; exact for Gaussian posteriors).
4. `quantiles$q50` approximately equals `mean` for symmetric
   posteriors but we report both so skewed posteriors (bootstrap,
   MCMC) are honestly represented.

### 2.2 Unified print + summary

```r
print.edaphos_posterior(x)
#> <edaphos_posterior>  method = ensemble  query = map  n_samples = 10
#>   mean  range : [-4.859, 1.746]  (NDVI z-units)
#>   sd    mean  : 0.437            (epi 0.412, alea 0.156)
#>   q05-q95 range: [0.18, 1.22]
#>   calibrated? (PICP@95) : 0.93    (run uncertainty_calibrate() for full report)
```

### 2.3 `uncertainty_calibrate()`

One function, any pillar. Given `edaphos_posterior` + ground truth:

```r
calib <- uncertainty_calibrate(post, truth,
                                probs = seq(0.05, 0.95, by = 0.05))
calib$picp     # vector of empirical coverage at each nominal level
calib$crps     # continuous ranked probability score, per query unit
calib$mpiw_95  # mean prediction-interval width at 95 %
calib$reliability_df  # ready for ggplot (nominal, empirical, diff)
```

### 2.4 `autoplot.edaphos_posterior()`

A `ggplot2::autoplot` method that produces the right figure for the
`query_type`:

- `"effect"`, `"param"`, `"energy"` — posterior-density + CI on a
  1-D slice.
- `"map"` — fan of three panels: point-estimate, SD, interval-width.
- `"sample"` — quantile-ribbon over the query batch.
- `"feature"` — boxplot / density by feature dimension.

## 3. Per-pillar changes

### 3.1 Pillar 1 — Causal AI

Thin wrapper. The existing block-bootstrap in
`causal_estimate_effect()` already draws `B = 200` resamples. We
simply keep the draws (currently discarded in the slim-save) and
wrap them in `edaphos_posterior`.

```r
post <- causal_effect_posterior(dag, data,
                                 exposure = "wc_landcover_trees",
                                 outcome  = "soc_topsoil_gkg",
                                 estimator = "lm",
                                 B = 1000L)
print(post)
```

**New API:** `causal_effect_posterior()`. No new science.

### 3.2 Pillar 2 — PIML

Two paths already exist:

- `piml_profile_ode_fit()` (deterministic) — wrap a **K-seed deep
  ensemble** around it. `K = 10` re-fits with different
  initialisations; optimiser noise drives the spread. New function:
  `piml_profile_ode_posterior(..., K_ens = 10L)`.
- `piml_profile_ode_bayes_fit()` (MCMC) — already produces draws.
  Just wrap them in `edaphos_posterior`.

**New APIs:** `piml_profile_ode_posterior()` (deep ensemble),
`as_edaphos_posterior.piml_bayes_fit()` (MCMC adapter).

### 3.3 Pillar 3 — 4D Pedometry

Already has the ensemble apparatus from v1.5.0. New work:

- `temporal_convlstm_ensemble_fit()` — wraps the current per-seed
  loop the v1.5.0 runner hand-rolls.
- `temporal_convlstm_mcdropout_predict()` — MC-dropout at inference
  time for cheap single-model uncertainty (Gal & Ghahramani 2016).
  The existing `StackCtor` gets a `dropout_p` argument.
- `temporal_kalman_update()` already returns the posterior ensemble;
  add `as_edaphos_posterior()` adapter.

**New APIs:** the two above. Existing `temporal_kalman_update()`
keeps its shape but gains an `as.edaphos_posterior` S3 method.

### 3.4 Pillar 4 — Foundation Models

This is where the most new ground gets broken. The current
`foundation_encoder_load()` + downstream fine-tune path is
deterministic. We add:

- **Fine-tuned head deep ensemble.** `foundation_finetune_head()`
  already accepts a `seed`; add `foundation_finetune_ensemble()` that
  trains `K` heads and returns a list.
- **MC-dropout at the head.** The head is currently a small MLP;
  adding `dropout_p` + sampling at predict time is cheap and
  standard.
- **Encoder weight perturbation.** Optional at first — perturb the
  frozen encoder with small Gaussian noise on a copy (deep-ensemble
  hyperparameter perturbation, Lakshminarayanan et al. 2017).

**New APIs:** `foundation_finetune_ensemble()`,
`foundation_predict_uncertainty()`.

### 3.5 Pillar 5 — Active Learning

QRF already exposes prediction intervals. The Pillar 5 batch query
ranker uses them internally. We surface them through the unified
API: `active_learning_predict_posterior()`.

The more interesting addition is **uncertainty-aware acquisition**
— the current cLHS + QRF query already uses variance, but the new
unified posterior lets us plug in epistemic-only uncertainty
(BALD-like) and compare against total uncertainty. This will be an
*optional* acquisition strategy, not a replacement.

### 3.6 Pillar 6 — Quantum ML

The closed-form Quantum Kernel Ridge Regression returns
`y_hat = K_test (K_train + λI)^{-1} y`. To give it a predictive
distribution we leverage the GP-like equivalence of Kernel Ridge
Regression (Rasmussen & Williams 2006, §2.3):

- Treat `K_train + λI` as the GP covariance; the predictive
  variance at a new query is
  `σ² = K_test_test - K_test_train (K_train + λI)^{-1} K_train_test`.
- Aleatoric `σ_a` comes from the leave-one-out residual RMSE.
- Epistemic `σ_e` comes from the GP variance.

No new quantum circuits; just a linear-algebra wrapper around the
existing `quantum_kernel_matrix()`.

**New API:** `quantum_krr_posterior()`.

## 4. Calibration diagnostic — the unified yardstick

Every pillar will be benchmarked on its Cerrado artefact bundle
(`inst/extdata/*_results.rds`) against the truth column it was
trained to predict. We report a single calibration table in the
v1.6 README + release notes:

| Pillar | Query type | n | CRPS | PICP @ 95 % | MPIW @ 95 % |
|:---|:---|---:|---:|---:|---:|
| 1 | effect, LM  | ... | ... | ... | ... |
| 1 | effect, BART | ... | ... | ... | ... |
| 2 | depth profile | ... | ... | ... | ... |
| 3 | NDVI map | 100 | ... | ... | ... |
| 4 | fine-tune pred | ... | ... | ... | ... |
| 5 | AL query score | ... | ... | ... | ... |
| 6 | SOC class | ... | ... | ... | ... |

A "calibrated" pillar has PICP close to 0.95 and small MPIW relative
to the target dynamic range.

## 5. Implementation roadmap (6 PRs, each ~1 day)

1. **v1.6.0-a** — `edaphos_posterior` class + `uncertainty_calibrate`
   + `autoplot` methods. Purely infrastructure, no scientific
   change. ~200 LoC, ~15 tests.
2. **v1.6.0-b** — Pillar 1 wrapper (`causal_effect_posterior`). ~80
   LoC, ~8 tests.
3. **v1.6.0-c** — Pillar 2 deep ensemble + MCMC adapter. ~150 LoC,
   ~10 tests.
4. **v1.6.0-d** — Pillar 3 ensemble + MC-dropout APIs. ~200 LoC,
   ~12 tests.
5. **v1.6.0-e** — Pillar 4 fine-tune ensemble + MC-dropout + encoder
   perturbation. ~250 LoC, ~12 tests.
6. **v1.6.0-f** — Pillar 5 wrapper + Pillar 6 GP-style posterior +
   unified calibration table vignette. ~300 LoC, ~20 tests.

Each PR is R CMD-check-clean on its own. The 6 merge into one
`v1.6.0` release with a single unified-uncertainty vignette that
runs the calibration table end-to-end.

## 6. Open questions for Hugo

1. **Scope of unification.** Is the `edaphos_posterior` class
   abstraction enough, or do we want every pillar to expose a
   `predict()` method with a `uncertainty = TRUE` argument instead?
   (The former is additive and safer for back-compat; the latter is
   more ergonomic but touches every pillar's existing API.)
2. **MC-dropout for Pillar 4.** The encoder is frozen. Do we want
   dropout only at the head, or also inside the encoder (costly)?
3. **Calibration benchmark.** For Pillar 1 the "truth" for a causal
   effect is undefined — there is no ground-truth effect. Do we skip
   Pillar 1 from the calibration table, or report a *pseudo-PICP*
   where the truth is the point estimate on the full data?
4. **Unified-uncertainty vignette depth.** A compact 4-page
   side-by-side is probably right; a deeper discussion of
   calibration theory (reliability, sharpness, CRPS properness)
   could go in a separate vignette or a `vignette("uncertainty-theory")`.
5. **Release cadence.** Do you want one v1.6.0 that lands all six
   PRs, or stagger as v1.6.0 (infrastructure + Pillar 3, which is
   already 80 % done) → v1.6.1 (Pillars 1, 2) → v1.6.2 (Pillars 4,
   5, 6)?

My default recommendation: one big v1.6.0 with a fat release note
(matches the six-pillar branding of the package), and a staggered
release cadence only if the full thing slips past a week of
calendar time.
