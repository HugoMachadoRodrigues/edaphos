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
