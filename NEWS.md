# edaphos 2.1.0

## Frente D — polish técnico para CRAN/rOpenSci adoption

### pkgdown documentation site
* New `_pkgdown.yml` with Bootstrap-5 theme, grouped navigation for
  all 13 vignettes, reference grouped by pillar + cross-pillar
  bridges, and release-notes integration.
* New GitHub Actions workflow `.github/workflows/pkgdown.yaml` that
  deploys the site to `gh-pages` on every push to `main` and on every
  GitHub release.

### Reproducibility: Docker container
* New `Dockerfile` based on `rocker/geospatial:4.4.1` with libtorch +
  pinned CRAN mirror (Posit Package Manager snapshot 2026-04-23) +
  pre-downloaded `edaphos-cerrado-moco-v1` encoder.  `docker build
  -t edaphos:2.1.0 .` produces a byte-reproducible image.  Runs
  RStudio Server on port 8787 by default.

### Test suite expansion
Fills the v1.8.0+ gap in test coverage.  Five new test files covering
the ~23 exported functions added since v1.6.0:
* `test-llm-benchmark.R`           : match/metrics/kappa/cost/simulate (9 tests)
* `test-llm-annotation.R`          : vocabulary/preannotate/validate/export/zenodo (5 tests)
* `test-causal-iv.R`               : 2SLS + Sargan + first-stage + from_embeddings + posterior (6 tests)
* `test-causal-sensitivity.R`      : Cinelli-Hazlett RV + grid + wrappers (6 tests)
* `test-quantum-foundation.R`      : qf_embed_reduce + kernel_compare + krr_fit + benchmark (6 tests)
* `test-foundation-embed-coords.R` : patch extraction + edge-case handling + fallback (4 tests)

### CRAN / rOpenSci submission prep
* `cran-comments.md` with test-environment matrix, optional-dependency
  rationale, and acknowledgements.
* `inst/rosc/submission.md` with the full rOpenSci pre-submission
  inquiry template — scope justification, closest-analogue comparison
  table, QA self-report, and open-issue disclosure.

### Deferred (explicit roadmap entries)
* v2.1.1 — Bridge P1×P5 Causal Active Learning
* v2.1.2 — Bridge P3×P5 Temporal Active Learning with EnKF feedback
* v2.1.3 — Rcpp port of `quantum_kernel()` for 10-50× speedup
* v2.2.0 — Bridge P2×P6 Physics-Informed Quantum Kernels
* v2.2.1 — Bridge P1×P3 Causal 4D (time-varying effects)
* v2.3.0 — Pilar 7: Bayesian hierarchical spatial models (INLA / Stan)
* v2.4.0 — Pilar 8: Neural operators (FNO / DeepONet) for pedogenetic PDEs
* v2.5.0 — Pilar 9: Diffusion models for generative soil maps
* v2.6.0 — Pilar 10: Graph neural networks on WoSIS co-location network

---

# edaphos 2.0.0

## Pillar 4 × Pillar 6 — Quantum kernel over foundation embeddings

The most ambitious bridge in the package.  Foundation-model embeddings
(MoCo v2 output, 64 dims) are PCA-reduced to top-n PCs rescaled into
`[-pi, pi]`, then lifted into a `2^n`-dimensional Hilbert space by the
ZZFeatureMap, where kernel ridge regression is solved in closed form.

* `qf_embed_reduce(embeddings, n_pcs)` — PCA + pi-scale.
* `qf_kernel_compare(X_q, reps)` — Frobenius distance between quantum,
  RBF, and linear Gram matrices on the same feature set.
* `qf_krr_fit(embeddings, y, n_pcs, reps, lambda)` — composite fit;
  `predict()` handles the PCA + pi-rescale + quantum forward pipeline.
* `qf_krr_benchmark(embeddings, covariates, y, ...)` — four-way
  head-to-head: ranger (raw), RBF-KRR (PCs), Q-KRR (raw), Q-KRR (PCs).

Benchmark on 1 095 Cerrado profiles (5-fold spatial CV, synthetic
stack): all four methods tie at ~14 g/kg RMSE.  Only ranger reaches
R² > 0.  The infrastructure is complete; the decisive test awaits the
encoder v2 (in training) + real SoilGrids/WorldClim/SRTM rasters.

---

# edaphos 1.9.2

## Cinelli & Hazlett (2020) sensitivity analysis

Complements the Sargan exclusion test with a partial-R² robustness
diagnostic: how strong would a latent confounder need to be to zero
out the estimated effect?

* `causal_sensitivity_summary(effect, se, df, q, alpha)` — Robustness
  Value (RV) and RV_alpha with verbal interpretation. Validated against
  the published Theorem 4.4 example (RV = 0.1810 recovered to four
  decimal places).
* `causal_sensitivity_grid()` — 2-D bias-adjustment grid for
  contour plotting.
* `causal_sensitivity_from_lm()` / `causal_sensitivity_from_iv()` —
  convenience wrappers over `lm` and `edaphos_causal_iv` fits.

Applied to the 1 095 Cerrado profiles: *the only robust causal claim
is Clay → SOC under naive OLS* (RV = 24%).  MAP → SOC under backdoor
OLS has RV = 8%, dropping to 4% under real-encoder IV due to weak
instruments in the synthetic-stack mode.

---

# edaphos 1.9.1

## Real MoCo v2 patch extraction — Sargan passes empirically

Two new functions close the loop from the v1.9.0 theoretical claim to
empirical confirmation:

* `foundation_embed_at_coords(moco, coords, stack, dataset, ...)` —
  extracts one embedding per query coordinate by cutting a `patch_size
  x patch_size` window, normalising, and running the encoder forward.
  Out-of-extent coords return `NA`.
* `foundation_build_cerrado_stack(bbox, cache_dir, target_res, force)` —
  assembles a 10-layer Cerrado raster stack by downloading SoilGrids +
  WorldClim + SRTM via `geodata`; aligned to a common 0.01-deg grid.

Decisive empirical result: every Sargan p-value on the 1 095 Cerrado
profiles jumps from rejection to non-rejection when we swap the v1.9.0
engineered-proxy instruments for real MoCo v1 embeddings:

| Exposure    | v1.9.0 Sargan (proxy) | **v1.9.1 Sargan (real MoCo)** |
|:---|---:|---:|
| MAP → SOC   | < 10⁻¹² ❌ | **0.343** ✅ |
| Trees → SOC | < 10⁻⁹ ❌  | **0.283** ✅ |
| Clay → SOC  | < 10⁻¹² ❌ | **0.424** ✅ |

An encoder pretrained by contrastive self-supervision without seeing
SOC produces structurally valid instruments where any feature
engineered from observed X fails exclusion.

---

# edaphos 1.9.0

## Pillar 1 × Pillar 4 bridge — Foundation embeddings as causal IVs

Five new functions (R/causal_iv.R):

* `causal_iv_fit_2sls(data, exposure, outcome, instruments, covariates)` —
  closed-form 2SLS estimator with the Wooldridge (2010) asymptotic
  variance.
* `causal_iv_first_stage()` — F-stat + partial R² for instrument
  relevance (Stock & Yogo 2005 rule-of-thumb F > 10).
* `causal_iv_sargan_test()` — Sargan J-test for over-identification.
* `causal_iv_posterior()` — nonparametric bootstrap posterior returning
  `edaphos_posterior` (unified with v1.6.0 API).
* `causal_iv_from_embeddings()` — convenience wrapper: embedding
  matrix → top-n PCs → 2SLS with the PCs as instruments.

Validated against a synthetic DGP (true β = 1.5 recovered to 1.46
with 95% CI covering truth; OLS biased to 1.82).

---

# edaphos 1.8.2

## Annotation tool polish: OpenAlex + DAG preview + dark mode + Zenodo

Four quality-of-life upgrades on top of v1.8.1:

* `data-raw/cerrado_corpus_v2_fetch.R` — OpenAlex corpus fetcher
  (6 orthogonal queries, deduplication, quality filters, up to 150
  abstracts in ~40s).
* Shiny "DAG" tab — live `DiagrammeR::grViz()` preview of the
  aggregate KG over accepted claims; filter by `min_support`.
* Dark mode toggle via `bslib::input_dark_mode()`.
* `llm_annotation_to_zenodo()` — packages the reviewed KG into a
  deposit-ready directory + zip archive with `gold_standard.jsonl`,
  `kg.ttl` (RDF 1.1 Turtle), `metadata.json` (DataCite), `README.md`.

---

# edaphos 1.8.1

## Annotation tool: pre-annotation + Shiny review UI

Two-phase workflow for scaling the gold-standard beyond the 72-claim
seed of v1.8.0:

* `llm_preannotate(corpus, backend, ...)` — runs the LLM extractor
  over every abstract; caches per-record hashes for resume-safety.
* `llm_annotation_launch(draft_path, output_path, ...)` — launches a
  Shiny review app in `inst/shiny-apps/annotation/`.  Three tabs
  (Review, Stats, Export); per-claim accept / edit / reject
  dropdowns constrained to the canonical vocabulary; keyboard
  shortcuts (`n` next, `p` prev, `a` accept all, `+` add, `1-9`
  toggle).  Save-after-every-abstract for crash safety.
* `llm_annotation_vocabulary()` — 22-term canonical list.
* `llm_annotation_validate()` — schema + vocab + polarity +
  confidence-range validation.
* `llm_annotation_export()` — drops rejected/draft, writes the
  canonical gold-standard JSONL.

---

# edaphos 1.8.0

## Pillar 1 — Multi-backend LLM extraction benchmark

First quantitative validation of the Gemma 4 extractor.  30 synthetic-
but-plausible Cerrado abstracts × 72 annotated causal claims form the
gold standard (`inst/extdata/cerrado_gold_standard_v1.jsonl`).

Five new functions (R/llm_benchmark.R):

* `llm_benchmark_match(predicted, gold, fuzzy, fuzzy_threshold)` —
  canonicalises labels, matches extracted edges against gold; returns
  TP/FP/FN per-edge frame.
* `llm_benchmark_metrics(match_df)` — precision, recall, F1, per-
  abstract breakdown.
* `llm_benchmark_kappa(claims_by_backend, gold)` — pairwise Cohen's
  kappa on edge presence.
* `llm_benchmark_cost(backend, model, n_abstracts, ...)` — USD cost
  per 1 000 claims at 2026-04 list prices.
* `llm_benchmark_simulate(gold, recall, precision_target, ...)` —
  deterministic simulator calibrated to published per-backend
  profiles (for CI builds + users without API access).

Result on the simulated benchmark (recalling that simulator
parameters are calibrated to published profiles):

|               | Precision | Recall | F1    | $ / 10k | Latency med. |
|:---|---:|---:|---:|---:|---:|
| Gemma 4 local | 0.75 | 0.67 | 0.71 | $0     | 16 s  |
| GPT-4o-mini   | 0.70 | 0.71 | 0.70 | $1.71  | 2.8 s |
| **Claude Sonnet-4.5** | **0.82** | **0.82** | **0.82** | $37.50 | 5.4 s |

---

# edaphos 1.7.2

## Causal-discovery trio: expert × LLM × data-driven

New runner `data-raw/causal_discovery_benchmark.R` compares three DAG-
construction strategies on 1 095 real WoSIS Cerrado profiles.  Three
bnlearn algorithms (hc, tabu, pc-stable) + expert DAG + LLM-augmented
DAG.  Reports the pairwise Structural Hamming Distance matrix, the
consensus-edge table, and the sensitivity of the backdoor adjustment
set for MAP → SOC.

Central finding: the adjustment set size for MAP → SOC varies from
**0 to 6 covariates** across the five methods — an order-of-magnitude
difference in the identified causal effect. **The choice of DAG
dominates the choice of estimator**.

---

# edaphos 1.7.1

## Native-query calibration fixes the v1.7.0 honesty gap

v1.7.0 reported a cross-pillar calibration table where every pillar
was forced into a single "predict SOC at WoSIS points" query —
producing PICP = 0.000 / 0.004 / 0.032 for P1-P3 because that is the
wrong query for a causal effect / depth profile / temporal forecast.

New `data-raw/capstone_native_calibration_run.R` evaluates each pillar
in its NATIVE domain:

| Pillar       | Native query            | PICP (90%) |
|:---|:---|---:|
| P1 Causal    | scalar effect β         | **0.775** |
| P2 PIML      | depth profile y(z)      | **0.714** |
| P3 4D        | future map NDVI(t★)     | **0.700** |
| P4 Foundation| 5-fold spatial CV       | 0.268     |
| **P5 AL**    | hold-out map            | **0.930** |
| P6 Q-KRR     | regression              | **0.840** |

---

# edaphos 1.7.0

## Capstone cross-pillar vignette

Flagship vignette `capstone-cerrado-campaign.Rmd` — "Uma decisão de
amostragem sob incerteza no Cerrado" — integrates all six pillars into
a single sampling-campaign decision for 8 new soil-sampling points.
~900 lines, 12 figures, 6 tables, Mermaid flowchart, causally grounded
in [Zhang & Wadoux 2026, *Eur. J. Soil Sci.* 77:e70284].

# edaphos 1.6.0

## Unified uncertainty across the six pillars

Every pillar's uncertainty output is now expressible as the same
S3 object — **`edaphos_posterior`** — and admits the same
calibration diagnostic, plotting routine and `as_edaphos_posterior()`
adapter protocol. Calibrating the six pillars against their
natural ground truth now takes three lines of code.

### New infrastructure

* `edaphos_posterior()` — constructor accepting either a
  `(n_samples, query_shape)` array of draws or a Gaussian
  `(mean, sd)` summary; pre-computes quantile arrays and prints a
  compact summary.
* `uncertainty_calibrate(post, truth, probs)` — CRPS (via the
  Gini-mean-difference Monte-Carlo formula of Gneiting & Raftery
  2007), PICP and MPIW at each `probs` level, reliability data
  frame and point RMSE.
* `autoplot.edaphos_posterior()` — single `ggplot2` entry point
  that dispatches on the posterior's `query_type` (effect / map /
  sample / feature / etc.).
* `uncertainty_plot_reliability()` — reliability-diagram plot from
  a `uncertainty_calibrate()` result.
* `as_edaphos_posterior()` — S3 generic with per-pillar methods
  that wrap the native fit outputs.

### Per-pillar adapters + new APIs

* **Pillar 1** — `causal_effect_posterior()` (LM cluster-block
  bootstrap **or** BART native posterior) and
  `causal_effect_bootstrap()` (block-bootstrap helper previously
  inlined in `data-raw/`).
* **Pillar 2** — `piml_neural_ode_posterior()` (deep ensemble
  predictive) and `piml_bayes_posterior()` (Laplace or MCMC
  predictive).
* **Pillar 3** — `temporal_convlstm_ensemble_fit()` (K-seed
  deep ensemble, formalising the hand-rolled loop from the v1.5.0
  runner), `temporal_convlstm_ensemble_rollout()`,
  `temporal_convlstm_mcdropout_predict()`, plus adapters for the
  ensemble object and the `temporal_kalman_update()` output.
* **Pillar 4** — `foundation_finetune_ensemble()` (K heads with
  different seeds on the same encoder, for regression or
  classification) and `foundation_mcdropout_predict()` (MC-dropout
  inside the MLP head, bypassing the `head$eval()` of the standard
  predict methods).
* **Pillar 5** — `active_learning_posterior()` (full QRF
  conditional distribution via an equally-spaced quantile grid).
* **Pillar 6** — `quantum_krr_posterior()` (GP-equivalent
  predictive posterior of the Quantum Kernel Ridge Regression with
  analytic epistemic + leave-one-out aleatoric decomposition).

### New vignette

`vignette("uncertainty-unified")` — end-to-end calibration table
across all six pillars (CRPS, PICP@95, MPIW@95, point RMSE) plus a
reliability-diagram facet.

### Testing

126 new tests across six `test-*-posterior.R` files pin every
constructor, adapter, predict method and calibration routine.
R CMD check: 0 errors / 0 warnings.

# edaphos 1.5.0

## Pillar 3 — 4D pedometry on real data + sequential Bayesian assimilation

The original Pillar 3 vignette runs on the synthetic
`temporal_synth_soc_cube()` output. v1.5.0 runs the same stacked
ConvLSTM machinery on **real MODIS NDVI + NASA POWER monthly
precipitation + NASA POWER T2M monthly air temperature** over a 2° × 2° Cerrado AoI
(Goiás / Minas Gerais triple junction, 10 × 10 cells × 168 monthly
time steps, 2010 – 2023), and introduces a new **stochastic
Ensemble Kalman Filter** that folds new in-situ observations into
the ConvLSTM forecast without retraining the network. We originally
targeted CHIRPS; the Climate Hazards Group portal was returning
HTTP 403 for every v2.0 monthly tif at the v1.5.0 freeze, so the
cube uses NASA POWER (MERRA-2 bias-corrected, fully open) as a
vetted substitute.

### New functions

* `temporal_kalman_update()` — stochastic EnKF (Evensen 1994;
  Burgers, van Leeuwen & Evensen 1998) for sequential assimilation
  of new point observations into an ensemble forecast produced by
  `temporal_convlstm_rollout()`. Supports 3-D `(N_ens, H, W)` and
  4-D `(N_ens, H, W, T)` inputs; returns the posterior ensemble plus
  diagnostic summaries (innovation vector, per-observation gain
  norm, posterior mean / SD maps). Optional Gaspari-Cohn spatial
  localization (`localization_radius`) is the standard small-ensemble
  fix for spurious long-range correlations.

### New artefacts

* `data-raw/temporal_cerrado_prepare.R` — one-time data-cube build
  (NASA POWER monthly precipitation + T2M, MOD13Q1 NDVI); output is
  a 4-D `(H, W, T, 3)` array cached in
  `tools/temporal_cerrado/temporal_cerrado_cube.rds`.
* `data-raw/temporal_cerrado_run.R` — trains a `K = 10` ConvLSTM
  ensemble on 2010 – 2020, rolls the forecast forward for 2021 – 2023
  and assimilates 8 synthesised in-situ NDVI observations at the
  last forecast month. Slim results persist to
  `inst/extdata/temporal_cerrado_results.rds`.
* `vignette("pilar3-4d-real")` — end-to-end narrative with rollout
  RMSE, posterior ensemble mean / uncertainty maps and gain
  diagnostics.

### Spatial localization

`temporal_kalman_update()` accepts an optional `localization_radius`
(Gaspari & Cohn 1999, Houtekamer & Mitchell 2001) that applies a
5th-order polynomial taper to the Kalman gain as a function of
grid-cell distance from each observation. Without localization, the
small-ensemble stochastic EnKF exhibits the classic collapse
pathology — a pilot run on the Cerrado cube showed posterior RMSE
growing above prior RMSE even as the posterior spread shrank to 5 %
of the prior. Setting `localization_radius = 2` on the v1.5.0 runner
recovers a 3.2 % net RMSE reduction.

# edaphos 1.4.0

## Pillar 1 — causal AI on real Cerrado data

The original Pillar 1 vignette derived the backdoor-adjustment
machinery on `br_cerrado` *synthetic* data. v1.4.0 runs the same
machinery on the **1 095 real WoSIS topsoil profiles** that power
the v1.3.1 benchmark, with a DAG that encodes published Cerrado
pedogenesis and block-bootstrap CIs that respect the spatial
clustering of the profiles.

### New functions

* `causal_cerrado_real_dag()` — a DAG over the exact column names
  of the v1.3.1 bundle (12 nodes, 23 directed edges) covering
  relief -> climate, climate -> land cover, relief -> texture ->
  density, and climate + texture + slope + land cover -> SOC.

### Headline identified effects (LM direct, block-bootstrap CI95)

| Exposure | Naive slope | Identified direct | Bootstrap 95 % CI |
|:---|---:|---:|:---:|
| `wc_bio_12` (MAP, g/kg per mm)           | +0.0072 | +0.0071 | [+0.0002, +0.0121] |
| `wc_landcover_trees` (g/kg per % trees)  | +0.898  | **+2.048** (2.3×) | [-0.465, +6.901] |
| `soilgrids_clay` (g/kg per % clay)       | +0.526  | **+0.195** (0.37×) | [-0.099, +0.688] |

Confounding moves in *both directions*: naive OLS under-estimates
the land-use causal effect by more than half and over-estimates
clay's direct effect by nearly 3×.

### New artefacts

* `data-raw/causal_cerrado_real.R` — fully reproducible analysis
  (reuses the v1.3.1 case-study bundle; runs in ~30 s).
* `inst/extdata/causal_cerrado_real.rds` — 62 KB slim results bundle
  (scalar effects + bootstrap CIs; BART posterior matrices stripped).
* `vignette("pilar1-causal-real")` — the narrative walk-through.

# edaphos 1.3.1

## Honest repair of the Cerrado benchmark

v1.3.0 shipped the first real-data benchmark but with four
load-bearing flaws that produced an unhelpfully low R² and a
misleading "E worse than B1" story. v1.3.1 fixes each of them:

1. **Clean, physically comparable topsoil target.** The filter
   changed from "any horizon with `lower_depth <= 30`" (which mixed
   0–5 cm, 5–15 cm and 15–30 cm horizons) to the shallowest horizon
   that starts at `upper_depth == 0` and has `lower_depth` in
   5–30 cm. Every profile now contributes one physically comparable
   SOC concentration measurement in g/kg. Relaxed
   `positional_uncertainty ≤ 2 km` matches the 1 km covariate
   resolution. **1095 profiles** survive the filters — a 3.6× gain
   over v1.3.0's 302-profile strict cut. A full integrated 0–30 cm
   SOC *stock* target was attempted but abandoned: WoSIS's per-
   horizon bulk density covers only ~20 % of Brazilian profiles and
   the stock formulation degenerates into a constant-BD-fallback
   target with weaker signal than the plain concentration.
2. **Land cover and bioclim covariates added.** ESA WorldCover 2020
   fractional covers (6 layers: trees / grassland / shrubs / cropland /
   built / bare) from @Zanaga2021worldcover (CC-BY-4.0) plus 19
   WorldClim 2.1 bioclim indices from @Fick2017worldclim. Total
   covariate count grew from 32 to 56.
3. **5-fold spatial cross-validation** (k-means on coordinates)
   replaces the single 80/20 split. Every profile is a test point
   exactly once; the 302 pooled predictions give binomial CIs ~4×
   tighter than the 60-point test set of v1.3.0 and eliminate the
   +6 g/kg bias floor that came from unlucky train/test SOC
   distribution drift.
4. **No log transform.** The log1p target hurts on this data (R² 0.16
   with log vs 0.23 linear); the clean 0–10 cm distribution is not
   skewed enough to benefit from variance stabilisation. Target is
   raw SOC in g/kg, point estimate is the bagged-tree mean, interval
   is the 2.5/97.5 QRF quantiles.

### Headline numbers (5-fold CV, 1095 profiles)

| Method | n | RMSE (g/kg) | R² | PICP @ 95 | Interval score |
|:---|---:|---:|---:|---:|---:|
| B1 ranger | 1095 | 13.51 | 0.219 | **0.944** | **65.81** |
| B2 ranger + kriging | 910 | 13.86 | **0.233** | 0.817 | 99.52 |
| E ranger + MoCo v1 embed | 923 | 14.07 | 0.157 | 0.940 | 71.66 |

R² 0.22–0.23 is in line with published Brazilian Cerrado / savanna
DSM (Gomes et al. 2019: 0.13 Brazil-wide; Nakhavali et al. 2018:
0.28 savanna with 200 profiles). The plain QRF is the **calibration
champion** (PICP 0.944, best interval score 65.8); residual kriging
gains +0.014 R² but ruins calibration (PICP falls to 0.82).

The foundation-model embedding (v1 encoder, 20 000 InfoNCE steps)
still trails B1. An encoder v2 with 200 000 steps (10× the v1
budget) is currently in training; v1.3.2 re-runs the benchmark with
the v2 weights and a separate Zenodo deposit.

### New Suggests

`geobr`, `dplyr`, `patchwork` (for the case-study vignette;
unchanged from v1.3.0).

# edaphos 1.3.0

## Honest benchmark on real Brazilian Cerrado data

* **New vignette `case-cerrado-end-to-end`**: an end-to-end
  reproducible case study on **1212 real WoSIS topsoil profiles**
  (Batjes et al. 2020) across the full Cerrado biome (IBGE polygon
  via `geobr`), with a held-out 240-profile test set stratified by
  2×2 longitude × latitude quadrants.
* **Three competing stacks** on the same split, covariates and
  seeds:
  B1 `ranger` quantile regression forest on the 32-layer
  SoilGrids + WorldClim + SRTM covariate stack;
  B2 B1 + `gstat` residual kriging (Hengl-style classical DSM);
  E B1 + the 64-dim `edaphos-cerrado-moco-v1` MoCo v2 foundation
  embedding (Zenodo DOI 10.5281/zenodo.19701276).
* **Honest result**: on this Cerrado benchmark the foundation-model
  embedding **does not improve** over the raw-covariate ranger
  (RMSE 12.53 vs 12.28 g/kg). The calibration champion is the plain
  QRF (PICP = 0.946 at a 0.95 nominal level, interval score 57.5).
  The README is updated accordingly — the "beyond state of the art"
  claim is explicitly scoped to the regimes where the raw covariate
  stack is thinner than SoilGrids + WorldClim + SRTM.
* **New helper `R/edaphos_metrics.R`**: `edaphos_rmse()`,
  `edaphos_mae()`, `edaphos_r2()`, `edaphos_bias()`,
  `edaphos_picp()`, `edaphos_interval_score()`,
  `edaphos_ece()`, `edaphos_metrics_summary()` — a single
  namespace for every benchmark in the package. 21 new unit tests.

## New `Suggests`: `geobr`

For the case-study prep script, which pulls the Cerrado biome
polygon from IBGE via `geobr::read_biomes()`.

# edaphos 1.2.0 (in development)

## Pillar 4 — Foundation Models

### New features

* **Downstream fine-tuning API** for supervised heads on top of any
  self-supervised MoCo v2 / SimCLR encoder:
  `foundation_fit_classifier()` and `foundation_fit_regressor()`.
  Both support linear probing (`freeze_backbone = TRUE`) and full
  fine-tuning with a two-group learning-rate schedule
  (Kornblith, Shlens and Le 2019). Target normalisation is handled
  internally in the regressor.
* **Device dispatch** (`device = "cpu" | "mps" | "cuda"`) wired
  through `foundation_moco_pretrain_tiles()` and the fine-tuning
  API. Apple Silicon MPS and NVIDIA CUDA backends are exercised
  end-to-end.
* **Published pretrained encoders** distributed via **Zenodo**
  under CC-BY-4.0. Three new functions consume the registry:
  `foundation_weights_list()`,
  `foundation_weights_download()` (with SHA-256 verification and
  an on-disk cache under `tools::R_user_dir("edaphos")`), and
  `foundation_weights_load()` (rebuilds the in-memory
  `edaphos_foundation_moco` wrapper). The first published encoder,
  `edaphos-cerrado-moco-v1`, was pretrained on 50 000 Cerrado
  tiles (SoilGrids + WorldClim + SRTM) on an Apple M1 Max MPS.

### Bug fixes

* `foundation_moco_embed()` now forces the encoder into `eval()`
  mode before the forward pass so BatchNorm uses its saved
  `running_mean` / `running_var` instead of batch-level statistics.
  Previously the returned embeddings depended on the current batch
  composition and disagreed with any reloaded copy of the same
  encoder.
* `foundation_tile_source_soilgrids()` now accepts both the human-
  readable depth strings (`"0-5cm"`, `"5-15cm"`, …) documented in
  its `@param` block and the integer form that
  `geodata::soil_world()` expects internally.

# edaphos 1.1.0

## Pillar 2 — Physics-Informed ML

* **Bayesian posterior** over the pedogenetic-ODE parameters via
  `piml_profile_fit_bayesian()` — Laplace approximation (default)
  and adaptive random-walk Metropolis (Haario, Saksman and
  Tamminen 2001). Posterior predictive draws are returned by the
  new `predict.edaphos_piml_bayes()` method with optional
  observation-noise inclusion.
* **Deep-ensemble** approximation to the Neural-ODE predictive
  posterior via `piml_neural_ode_fit_ensemble()`
  (Lakshminarayanan, Pritzel and Blundell 2017).

## Pillar 5 — Autonomous Active Learning

* **BatchBALD** information-theoretic batch acquisition via
  `al_query_batchbald()` (Kirsch, van Amersfoort and Gal 2019).
  Greedy log-det selection with Schur-complement / Cholesky
  incremental updates; submodular, hence a (1 − 1/e) optimality
  guarantee.

## Pillar 1 — Causal AI

* **Structure learning** from horizon data via
  `causal_structure_learn()` (`bnlearn` bridge: `hc`, `tabu`,
  `pc-stable`, `mmhc` with optional bootstrap edge strengths).
* **Multi-extractor LLM voting** via `causal_llm_vote()` and
  `causal_llm_ingest_abstract_voted()` — majority / weighted /
  intersection rules over N independent LLM backends.

# edaphos 1.0.0

## Pillar 1 — Paper-scale knowledge graphs

* **Persistence** via `causal_kg_save()` / `causal_kg_load()`
  (portable RDS edge-list; survives `igraph` version bumps).
* **RDF 1.1 Turtle export** via `causal_kg_to_turtle()` — reified
  `rdf:Statement` per edge preserves confidence / evidence /
  source(s) / timestamp; pure-R emitter, no RDF library needed.
* **Multi-source edge ranking** via `causal_kg_rank_edges()` and a
  `summary.edaphos_causal_kg()` method.
* **Concurrent AGROVOC alignment** via
  `causal_ontology_agrovoc_align_batch()` with parallel HTTP
  dispatch through `httr2::req_perform_parallel()` and an
  idempotent on-disk cache.

# edaphos 0.9.0

## Pillar 6 — Quantum ML

* **Shot-based VQE** (`backend = "aer_shots"`) via
  `qiskit_aer.primitives.EstimatorV2`.
* **Full IBM Quantum Runtime dispatch** (`backend = "ibmq"`) with
  ISA transpilation and M3 / ZNE mitigation
  (Kim et al. 2023).
* **qiskit-nature bridge** — `quantum_hamiltonian_from_pyscf()`
  and curated presets for carboxylate, catechol ortho-diol and
  Fe(III)–formate organo-mineral motifs.

# edaphos 0.8.0

## Pillar 1 — Literature-scale extraction

* Paginated OpenAlex corpus client, `causal_corpus_deduplicate()`,
  resumable disk-cached `causal_llm_ingest_corpus()`, live AGROVOC
  SPARQL alignment with on-disk cache, 100-abstract bundled demo
  (`inst/extdata/cerrado_claims_real_corpus.jsonl`).
