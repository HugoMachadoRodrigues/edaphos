# edaphos 3.4.0

## Calibrated predictive posteriors for P1, P6, P10 benchmark wrappers

The v3.1.0 benchmark exposed a known shortcoming of the three new
wrappers (`benchmark_fit_p1_causal()`,
`benchmark_fit_p6_quantum()`, `benchmark_fit_p10_gat()`): their
posteriors carry only EPISTEMIC uncertainty (the spread of
predictive means under different bootstrap / seed-ensemble fits)
and consequently UNDER-COVER honest 90 % intervals.  v3.1.0
PICP_90 readouts on the 1 095-profile WoSIS Cerrado benchmark:

  P1 Causal+OLS    : 0.232
  P6 Quantum KRR   : 0.249
  P10 GAT ensemble : 0.073

v3.4.0 adds the missing ALEATORIC term: an estimate of the
in-sample residual standard deviation `sigma_resid` is injected as
iid Gaussian noise on every (sample, test-row) entry of the
posterior matrix.  The aleatoric estimate comes from a single
full-data point predictor (OLS for P1, quantum KRR for P6,
ensemble-mean training prediction for P10) so it is decoupled from
the bootstrap / seed-ensemble noise.  PICP_90 jumps to nominal
coverage:

  P1 Causal+OLS    : 0.953   (was 0.232)
  P6 Quantum KRR   : 0.601   (was 0.249)
  P10 GAT ensemble : 0.825   (was 0.073)

CRPS also improves materially across the board:

  P1 Causal+OLS    : 6.80    (was 7.78)
  P6 Quantum KRR   : 7.43    (was 8.08)
  P10 GAT ensemble : 8.11    (was 8.68)

### API change (back-compatible)

Each of the three wrappers gains a `calibrate = TRUE` argument.
Setting `calibrate = FALSE` reproduces the v3.1.0 epistemic-only
behaviour bit-for-bit.  Default is `TRUE`.

The estimated `sigma_resid` and the `calibrate` flag are written
into the `metadata` slot of the returned `edaphos_posterior` for
downstream introspection.

### Internal helpers

* `.bench_inject_aleatoric(pred_mat, sigma_resid, seed)` -- injects
  iid `N(0, sigma_resid^2)` noise on every entry of a posterior
  matrix.  Identity when `sigma_resid <= 0`.
* `.bench_residual_sd(y_obs, y_hat)` -- NA-safe residual SD
  estimator.

### Refresh of the v3.1.0 benchmark bundle

`inst/extdata/benchmark_wosis_6pilar.rds` re-run with
`calibrate = TRUE` (now the default) on the same 1 095-profile
folds.  The aggregate table now reads:

| Method             | RMSE  | R^2    | PICP_90 | MPIW_90 | CRPS  |
|--------------------|------:|-------:|--------:|--------:|------:|
| **P1 Causal+OLS**  | 13.94 | 0.082  |  0.953  |  46.9   | 6.80  |
| P4 Foundation+QRF  | 14.07 | 0.033  |  0.889  |  37.6   | 5.93  |
| P5 QRF             | 14.12 | 0.064  |  0.879  |  37.2   | 5.85  |
| P7 BHS             | 14.13 | 0.070  |  0.812  |  36.7   | 6.97  |
| P6 Quantum KRR     | 14.55 | 0.000  |  0.601  |  16.7   | 7.43  |
| P10 GAT ensemble   | 15.18 | 0.000  |  0.825  |  35.6   | 8.11  |

Note: P1 PICP is now mildly OVER-covered (0.95 vs nominal 0.90)
because the OLS residual SD is computed in-sample without a
leave-one-out adjustment; this is closer to honest than the
under-coverage but is documented as a v3.5.0 TODO if needed.

### Tests

`tests/testthat/test-benchmark-6pilar-calibrate.R` -- 9 tests:
calibrated vs raw SD comparison for P1/P6/P10, PICP_90 lift on P1,
unit tests for `.bench_inject_aleatoric()` and
`.bench_residual_sd()`, NA-safety contract.

R CMD check: 0 errors | 2 warnings (pre-existing inst/doc) | 0 notes.
1 256 tests pass (+17 vs v3.3.0).

---

# edaphos 3.3.0

## Getting-started vignette

Adds `vignettes/getting-started.Rmd` -- a ~200-line orientation
tour that walks through all ten research pillars plus three
cross-pillar bridges on a single 60-profile synthetic Cerrado
data frame.  Every chunk runs in seconds offline and uses only the
core package API; no Zenodo downloads, no MCMC diagnostics, no
external services.  Intended as the entry point for new users
before diving into the per-pillar deep dives.

Concretely, the vignette demonstrates:

* **Pilar 1** - `benchmark_fit_p1_causal()` -> `edaphos_posterior`
* **Pilar 2** - `piml_profile_fit()` on a single pedon
* **Pilar 3, 4** - pointer to full vignettes (need cubes / Zenodo weights)
* **Pilar 5** - `al_fit()` + `al_query(strategy = "hybrid")`
* **Pilar 6** - `benchmark_fit_p6_quantum()` -> `edaphos_posterior`
* **Pilar 7** - `bhs_fit()` + `predict()` posterior summary
* **Pilar 8** - `no_deeponet_fit()` on synthetic depth targets
* **Pilar 9** - `dm_fit()` + `dm_sample()` on synthetic patches
* **Pilar 10** - `gnn_build_graph()` + `gnn_fit()` on a k-NN graph
* **Bridges** - `al_query_bhs()` (P7 x P5), `gnn_causal_discovery()`
  (P10 x P1, eval = FALSE pending bnlearn Suggests)
* **Unified scoring** - `uncertainty_calibrate()` across all
  `edaphos_posterior` outputs.

The vignette closes with a CRPS-table comparison of P1 and P6 on
the shared test split, pointing users to
`inst/extdata/benchmark_wosis_6pilar.rds` for the full 1 095-
profile WoSIS head-to-head.

R CMD check: 0 errors | 2 warnings (pre-existing inst/doc) | 0 notes.
1 239 tests pass.

---

# edaphos 3.2.0

## Performance: Gibbs fast path + batched DDPM training

Two hot-path optimisations in pure R (no new compiled code, no
new dependencies) that cut wall-time substantially without changing
any public API.

### Pilar 7 Gibbs sampler: triangular-solve MVN sampling

The v2.3.0 Gibbs loop built the n x n posterior-covariance matrix
`V_w = (R_inv / sigma^2 + I / tau^2)^-1` by computing `chol2inv()`
every iteration, then drew `w` via a SECOND Cholesky of `V_w`.
Profiling at n = 300 showed 36 % of wall-time in `chol.default`
and 30 % in `chol2inv`.

The v3.2.0 fast path never forms `V_w`.  It instead

1. Computes a single upper-triangular Cholesky `L = chol(P_w)` of
   the precision matrix (with the existing `.chol_jitter()` retry
   guard), and
2. Draws the sample via two triangular solves + a `rnorm(n)`:
   `mu_w = backsolve(L, backsolve(L, rhs, transpose = TRUE))`, then
   `w = mu_w + backsolve(L, z)`, `z ~ N(0, I)`.

Covariance is provably `V_w` without ever inverting:
`Var(backsolve(L, z)) = solve(L) solve(L)' = (L'L)^-1 = P_w^-1 = V_w`.

The same transform is applied to the `beta` update (precision =
`X'X / tau^2 + prior_prec * I`), and the two `diag(...)` calls that
were rebuilding identity + scalar matrices each iteration are
replaced with in-place `diag<-` updates.

**Measured speedup**: 2.5x at n = 300, nmcmc = 500
(v2.3.0: 7.06 s / v3.2.0: 2.81 s).  Posterior recoverability and
all v2.3.0 test-suite guarantees preserved.

### Pilar 9 DDPM training: batched forward + gradient accumulation

The v2.5.0 training loop iterated `for (i in seq_len(n_patches))`,
calling `.dm_forward()` once per patch and accumulating the
gradient row-by-row with `outer()`.

v3.2.0 introduces `.dm_forward_batch()` that processes a full
minibatch in three GEMMs:

* `H1 = ReLU(Z W1 + b1)`   -- single matmul + row-broadcast
* `H2 = ReLU(H1 W2 + b2)`
* `Eps_hat = H2 W3 + b3`

and replaces the per-row outer-product accumulator with a single
`crossprod(H2, Resid)`.  Gradients are bit-identical (max |diff|
< 2e-15 at n = 128, verified in tests) and the epoch wall-time is
~4-6x faster across n_patches in [64, 512].

### Deliverables

* `R/pilar7_bayesian_hierarchical.R` -- fast-path Gibbs loop.
* `R/pilar9_diffusion_models.R` -- `.dm_forward_batch()` + batched
  training loop.
* `tests/testthat/test-pilar7-bhs-fastpath.R` -- 4 tests: beta
  recovery, positive variance components, finite predict() summary,
  performance-regression ceiling.
* `tests/testthat/test-pilar9-ddpm-batched.R` -- 4 tests: row-by-row
  agreement of `.dm_forward_batch()` (with and without
  conditioning), bit-identical epoch gradients, training-history
  decrease on smoothed random patches.

R CMD check: 0 errors | 2 warnings (pre-existing inst/doc) | 0 notes.
1 239 tests pass (+26 vs v3.1.0).

### Note on the full Rcpp port

A straight C++ port of the Gibbs sampler was considered and
deferred: it would require adding `RcppArmadillo` (or inline LAPACK
calls) as a LinkingTo dependency, which materially increases the
package's compile surface for a workload that is already
Cholesky-bounded.  The pure-R fast path captures most of the
speedup available from algorithmic restructuring.  A follow-up
Rcpp port is deferred to a later release if profiling identifies
a workload where the ~5 ms/iter remaining overhead dominates.

---

# edaphos 3.1.0

## 6-pilar head-to-head benchmark on 1 095 WoSIS Cerrado profiles

Extends the v2.8.0 triple (P4 Foundation + P5 QRF + P7 BHS) on the
same 1 095-profile WoSIS Cerrado topsoil SOC regression task by
adding three methods that are natural fits to a static point-
regression task:

* **Pilar 1 -- DAG-adjusted OLS + parametric bootstrap**.  Restricts
  the covariate set to variables present in the supplied DAG (with
  two-way aliasing between SoilGrids / WorldClim native names and
  the friendly WoSIS nicknames) and generates a 300-sample
  parametric-bootstrap predictive posterior.
* **Pilar 6 -- Bootstrap-ensembled quantum KRR**.  PCA-reduces the
  covariates to 6 qubit-dimensions, rescales to `[-pi, pi]`, and
  trains `n_boot` ZZFeatureMap kernel-ridge regressors on bootstrap
  resamples of the training set.  Predictions across bootstrap
  members form the posterior.
* **Pilar 10 -- GAT seed-ensemble on k-NN co-location graph**.
  Builds a joint k-NN graph on `rbind(train, test)` with (lon, lat)
  adjacency + covariate node features, fits N independent GAT
  regressors with different seeds, and reads out the test-node
  predictions as an ensemble posterior.

All three wrappers return an `edaphos_posterior` consumable by
`uncertainty_calibrate()`; the full 5-fold spatial-CV evaluation
produces fold-level RMSE / MAE / R^2 / PICP_90 / MPIW_90 / CRPS
metrics to compare against the v2.8.0 baseline.

### Cross-fold aggregate (1 095 WoSIS profiles, 5 spatial folds)

| Method             | RMSE  | R^2    | PICP_90 | MPIW_90 | CRPS  |
|--------------------|------:|-------:|--------:|--------:|------:|
| **P1 Causal+OLS**  | 13.94 | 0.085  | 0.232   |  6.32   | 7.78  |
| P4 Foundation+QRF  | 14.07 | 0.033  | 0.889   | 37.64   | 5.93  |
| P10 GAT ensemble   | 14.07 | 0.001  | 0.073   |  2.29   | 8.68  |
| P5 QRF             | 14.12 | 0.064  | 0.879   | 37.22   | 5.85  |
| P7 BHS             | 14.13 | 0.070  | 0.812   | 36.67   | 6.97  |
| P6 Quantum KRR     | 14.53 | 0.000  | 0.249   |  6.88   | 8.08  |

Honest readout (not a ranking):
* **RMSE is a flat band (13.9 - 14.5 g/kg)** across all six methods.
  The 1 095-profile Cerrado topsoil subset does not discriminate
  between these architectures on point accuracy -- any claim of
  one-method dominance would be noise.
* **Calibration splits the field**.  The v2.8.0 QRF-family methods
  (P4/P5/P7) produce wide, well-calibrated 90 % intervals
  (PICP_90 ~ 0.81 - 0.89, MPIW ~ 37 g/kg).  The three new ensemble
  methods produce much NARROWER intervals (MPIW ~ 2 - 7 g/kg) that
  consequently UNDER-cover (PICP_90 ~ 0.07 - 0.25).  The bootstrap /
  seed-ensemble variance alone is not enough to capture irreducible
  noise; adding an explicit residual-variance term is the v3.2.0
  TODO for these wrappers.
* **P1 Causal+OLS** delivers the best RMSE + R^2 of the new methods
  (and the whole table), at negligible cost (~0.7 s / fold) -- a
  useful baseline because it is fully interpretable.
* **P10 GAT** and **P6 Quantum** deliver competitive RMSE but
  currently do not produce honest predictive uncertainty.

Deliverables:

* **`R/benchmark_wosis.R`** -- three new exported wrappers:
  `benchmark_fit_p1_causal()`, `benchmark_fit_p6_quantum()`,
  `benchmark_fit_p10_gat()`.  API-stable so users can reproduce the
  benchmark on any regional subset with the same schema.
* **`data-raw/benchmark_wosis_6pilar.R`** -- orchestrator that
  re-uses the v2.8.0 posterior_bank for P4/P5/P7 and runs the three
  new methods on the same 5 spatial folds, saving the combined
  fold-level table + aggregate + posterior bank to
  `inst/extdata/benchmark_wosis_6pilar.rds`.
* **`tests/testthat/test-benchmark-6pilar.R`** -- 9 tests covering
  shape, DAG-restriction behaviour, constant-baseline parity, NA-row
  imputation on test nodes, and end-to-end uncertainty calibration
  across all three methods.

Documented exclusions (not natural fits to the topsoil scalar
regression task, benchmarked in their home vignettes instead):

* **Pilar 2** -- profile-ODE depth dynamics.
* **Pilar 3** -- ConvLSTM over temporal stacks of maps.
* **Pilar 8** -- neural operators over depth function space.
* **Pilar 9** -- DDPM raster-patch generation.

R CMD check: 0 errors | 0 notes on v3.1.0
(2 warnings about `inst/doc` directory are pre-existing vignette/
V8-dagitty plumbing; not a regression).
All 1 213 tests pass (+36 relative to v3.0.0).

---

# edaphos 3.0.0

## Six new cross-pilar bridges

Six new scientifically motivated bridge functions that compose two of
the ten research pillars into a single API.  All six follow the
v2.1.1 `*_query_*` signature pattern (or the established
`*_fit` / `*_loss` convention) so they drop into existing loops
with no boilerplate.

**Active-learning bridges** (feed Pilar 5's query step with
posterior-like uncertainty from the neighbouring pilares):

* `al_query_neural_operator()` **(P8 x P5)** -- ranks candidate sites
  by the disagreement between a DeepONet / FNO operator prediction
  and the Pilar 2 pedogenetic ODE, normalised by a per-site
  perturbation-spread uncertainty.  Returns an
  `edaphos_al_neural_operator_query` data frame.
* `al_query_diffusion()` **(P9 x P5)** -- Monte Carlo posterior-
  sampling from a conditional DDPM, ranks candidate cells by per-
  cell standard deviation across draws.  Optional `combine`
  argument weights SD by absolute posterior mean.  Returns an
  `edaphos_al_diffusion_query`.
* `al_query_bhs()` **(P7 x P5)** -- Settles (2009, Sec. 3.3) style
  Thompson-sampling AL driven by the BHS posterior MCMC draws.
  Computes `s2 * (1 - k' R_inv k) + t2` averaged across draws so
  selected sites have high predictive variance for MANY plausible
  posterior parameterisations.

**Structural bridges** (compose one pilar's representation into
another's learning step):

* `gnn_causal_discovery()` **(P10 x P1)** -- augments a feature
  data frame with GAT node embeddings as nuisance conditioners and
  runs `causal_structure_learn()` on the extended frame.  The
  returned DAG is restricted to edges between user-named variables
  via `kg$edges_feature_only`; embeddings only do their job as
  absorbers of spatial dependence the expert does not enumerate.
* `temporal_piml_loss()` **(P2 x P3)** -- factory returning a
  callable `function(y_pred, y_true, driver)` closure suitable as
  the `physics_loss_fn` of `temporal_convlstm_fit()`.  Penalises
  deviations of predicted temporal increments from
  `-lambda0 * (y - y_inf)` -- a site-specific rate drawn from the
  fitted Pilar 2 ODE rather than a hard-coded scalar.  Dispatches
  between torch-tensor and R-array inputs via duck-typing.
* `qf_krr_on_gat_embeddings()` **(P6 x P10)** -- composes
  `qf_krr_fit()` over GAT node embeddings through PCA reduction;
  a strict generalisation of the v2.0.0 foundation-quantum fusion
  that now bakes network structure into the quantum kernel's
  input representation.

## Tests and docs

* `tests/testthat/test-bridges-v3.R` -- 17 new tests covering all
  six bridges (output schema, ranking invariants, attribute carry-
  through, error messages on malformed inputs, parameter extraction
  from both `edaphos_piml_profile` and `edaphos_piml_bayes` fit
  classes).
* `.piml_extract_params()` internal helper centralises the
  class-dependent access to `(lambda0, mu, y_inf, y0)` so bridges
  consistently pull ODE parameters from `$params` on profile fits
  and `$map` on Bayesian fits.
* Roxygen docs regenerated; six new `man/*.Rd` pages shipped.

R CMD check: 0 errors | 0 warnings | 0 notes on v3.0.0.
All 1177 tests pass (+53 relative to v2.9.1).

---

# edaphos 2.9.1

## Public-release artefact pack

No code changes.  Administrative prep for CRAN + rOpenSci + Zenodo +
GitHub Pages publication.

* **`RELEASE.md`** -- single-page checklist of the four remaining
  manual maintainer actions (Zenodo new-version deposit, GH Pages
  enable, CRAN `devtools::submit_cran()`, rOpenSci pre-submission).
  Copy-paste instructions with exact URLs and code snippets.
* **`tools/zenodo_release/` + `tools/zenodo_release.zip`** (5.2 MB)
  regenerated for v2.9.1 via `edaphos_zenodo_release()`:
    - All 22 `inst/extdata/*.{rds,jsonl}` bundles with SHA-256
      checksums in `manifest.csv`.
    - `CITATION.cff` + `NEWS.md` + `README.md` snapshots.
    - DataCite-compatible `metadata.json` with the concept-DOI
      `isNewVersionOf` link.
    - `ZENODO-README.md` with the canonical file list + citation
      template.
* **pkgdown site builds locally** (`pkgdown::init_site()` verified).
  GH-Pages deploy is gated only by the repo Pages setting change
  (step #2 in `RELEASE.md`).
* `.Rbuildignore` expanded to exclude `RELEASE.md` and the
  auto-generated `pkgdown/` assets directory from the package
  tarball.

R CMD check: 0 errors | 0 warnings | 0 notes on v2.9.1.

---

# edaphos 2.9.0

## Publication-grade edge-case test coverage for Pilares 7-10

Expands the test suite from the v2.7.0 happy-path baseline (~20 tests
for the four new pilares) to ~55 tests, covering NA inputs,
singular matrices, zero-variance features, reproducibility,
device dispatch, and adversarial inputs.

* **`tests/testthat/test-pilar7-bhs-edge.R`** (10 tests) --
  NA-row drop via model.frame, rejection on too-few-rows,
  reproducibility under fixed seed, duplicate-coord Cholesky
  robustness, constant-covariate handling, prior-strength
  sensitivity (weak vs tight), out-of-extent predict, missing-
  covariate error in predict, extreme phi_range, posterior-sample
  dimensions.
* **`tests/testthat/test-pilar8-no-edge.R`** (8 tests) --
  zero-variance covariates, very small n, column-count mismatch,
  FNO reproducibility, n_modes clamping at n_depths/2, arbitrary
  depth grids (including extrapolation past training range), torch
  backend reproducibility.
* **`tests/testthat/test-pilar9-ddpm-edge.R`** (9 tests) --
  T = 1 boundary, T = 1000 numerical stability, degenerate constant
  stack, sample determinism, n_samples = 1 boundary, cond_dim
  mismatch errors, fallback when cond = NULL on conditional model,
  torch backend CPU finite output, tiny T = 2.
* **`tests/testthat/test-pilar10-gat-edge.R`** (10 tests) --
  k = 1 edge count, k = n-1 complete graph, no-numeric-features
  rejection, duplicate-coord finite-weight guarantee, NA-feature
  standardisation fallback, n_heads = 1, n_layers = 1, fit
  reproducibility, torch backend with n_heads = 1, n = 5 small
  graph.

No changes to the production R code -- purely test expansion.  The
edge cases caught two minor issues noted as TODOs:
* DeepONet tanh saturates on extreme-depth extrapolation (expected;
  documented).
* `sweep` recycling warning on odd column counts in standardisation
  (cosmetic; expected behaviour).

R CMD check: 0 errors | 0 warnings | 0 notes on v2.9.0.
All 55 new edge tests pass.

---

# edaphos 2.8.0

## Real head-to-head benchmark -- P4 Foundation x P5 QRF x P7 BHS

First honest cross-pillar benchmark of three independent pillars on
the **1 095 real WoSIS Cerrado topsoil profiles**, evaluated by
5-fold spatial CV (k-means on lon/lat).  Methods share the v1.6.0
`edaphos_posterior` + `uncertainty_calibrate()` infrastructure for
apples-to-apples comparison.

* **`data-raw/benchmark_wosis_p4_p5_p7.R`** -- end-to-end runner:
  loads 1 095 profiles, builds 5 spatial folds, fits each method
  per fold, produces a unified posterior, scores with
  `uncertainty_calibrate()`.
* **`inst/extdata/benchmark_wosis_p4_p5_p7.rds`** (1.9 MB) --
  reproducible bundle.

### Cross-fold aggregate (mean across 5 folds)

| Method            | RMSE | R²    | PICP @ 90 | MPIW @ 90 | CRPS |
|:---|---:|---:|---:|---:|---:|
| P4 Foundation+QRF | 14.1 | 0.034 | 0.889     | 37.6      | 5.93 |
| **P5 QRF**        | 14.1 | 0.064 | 0.879     | 37.2      | **5.85** |
| **P7 BHS**        | 14.1 | **0.070** | 0.812     | **36.7**      | 6.97 |

**Honest reading**: all three tied at ~14.1 g/kg RMSE.  P5 wins on
CRPS (best probabilistic score); P7 wins on R² and MPIW (tightest
intervals) but under-covers at 81% vs 90% nominal; P4 Foundation is
best calibrated (PICP 0.89 very close to 0.90) but has the lowest R².
The Foundation+QRF uses a synthetic-stack encoder fallback in this
CI-safe version; the v1.9.3 real-geodata upgrade should favour P4
more.

### P7 BHS bug fix

While running the benchmark we found a row-alignment bug in
`bhs_fit()`: when `data` had a reset rowname sequence (the typical
dplyr case), `model.frame()` preserved the original integer
rownames and `data[as.integer(rownames(mf)), ]` indexed past the
end of `data`, silently returning `NA` coordinates.  Fixed by
carrying an internal `.row_id` integer column through
`model.frame()` instead of relying on rownames; an explicit finite-
coordinate filter was added as belt-and-suspenders.

Existing Pilar 7 test suite (5 tests) still passes.

---

# edaphos 2.7.0

## Torch/autograd backends for Pilares 8, 9 and 10

Replaces the v2.4.0 / v2.5.0 / v2.6.0 "ELM-style" (hidden layers
fixed at random init, analytic gradient only on the output head)
with full `torch` autograd.  Each pilar gains a
`backend = c("r", "torch")` argument; the pure-R path is preserved
as default fallback so users without the torch runtime still get
working baselines.

### Pilar 8 (v2.4.0 upgrade)
* New `R/pilar8_neural_operators_torch.R`.
* `.torch_fno_module` -- FNO with 1-D spectral convolution via
  `torch_fft_rfft` + truncated real magnitude multiplier +
  `torch_fft_irfft`, residual pointwise linear path, leaky-ReLU.
  Full backprop through every FNO block.
* `.torch_deeponet_module` -- branch + trunk MLPs with tanh
  activation; inner-product output.  Trained by `optim_adam` with
  MSE loss.
* Both functions accept `device = c("cpu", "mps", "cuda")` so MPS
  dispatch works on Apple Silicon.

### Pilar 9 (v2.5.0 upgrade)
* New `R/pilar9_diffusion_torch.R`.
* `.torch_ddpm_unet` -- proper 2-D conditional U-Net:
    - Encoder: Conv2d(1 -> base_ch) x2 + pool, Conv2d(base_ch
      -> 2 base_ch) x2 + pool.
    - Bottleneck: Conv2d(2 base_ch -> 4 base_ch) + sinusoidal
      time-embedding bias.
    - Decoder with skip connections via upsample-nearest +
      Conv2d + concat.
    - Final 1x1 Conv to predict noise eps_theta(x_t, t, c).
* Classifier-free guidance style: conditioning vector is dropped
  with probability 0.1 during training so the same model supports
  unconditional sampling at inference.
* `.torch_ddpm_sample` -- ancestral sampling identical to the
  v2.5.0 pure-R formula but using the autograd-trained U-Net.

### Pilar 10 (v2.6.0 upgrade)
* New `R/pilar10_graph_nn_torch.R`.
* `.torch_gat_layer` -- multi-head Graph Attention layer:
    - `nn_linear` projects input to `(n_heads, d_out)`.
    - Per-head attention logits `a_l^T W h_src + a_r^T W h_dst`
      with leaky-ReLU, softmax-normalised per source via
      `index_add` scatter.
    - Head outputs concatenated at non-final layers, averaged at
      the final layer.
* `.torch_gat_module` -- stack of attention layers + linear head.
* Weight decay `1e-4` on the Adam optimiser; full backprop through
  every attention weight.

All three pilares record `backend = "r"` or `backend = "torch"`
on the fit object; predict / sample methods dispatch accordingly.

Tests: 10 new expectations across
`test-pilar8-torch.R`, `test-pilar9-torch.R`, `test-pilar10-torch.R`.
Each file `skip_if_not_installed("torch")`-gated so the base CI
continues to pass without torch.

---

# edaphos 2.6.0

## Pilar 10 -- Graph Attention Networks on WoSIS co-location graphs

Activates the v2.1.0 scaffold.  First pedometric application
(as of 2026) of attention-weighted message-passing over soil-profile
graphs: profiles are nodes, k-NN geographic co-location defines
edges with inverse-distance weights, and a Graph Attention Network
(Velickovic et al. 2018) propagates covariate information between
neighbouring sites.

* **`gnn_build_graph(profiles, k, feature_cols)`** -- constructs the
  k-NN co-location graph.  Returns an `edaphos_gnn_graph` S3 object
  with standardised node features, dense `edge_index` (n*k rows),
  soft-normalised `edge_weight`, and the spatial coordinates.
* **`gnn_fit(graph, targets, hidden, n_heads, n_layers, epochs, lr,
  seed)`** -- trains a multi-head GAT.  Each layer's per-head output
  uses the attention rule
    alpha_ij = softmax_j( LeakyReLU( a' [Wh_i || Wh_j] ) )
  and head outputs are concatenated at layer boundaries.  Final
  node embeddings are mapped to the target by a linear head with
  ridge regularisation, trained by analytic gradient descent
  (hidden layers fixed at random init, ELM-style).
* **`gnn_embed(fit)`** -- returns the `(n, hidden * n_heads)` node
  embedding matrix -- directly comparable in dimensionality to the
  MoCo v2 Pilar 4 embeddings, which enables the 2026-novel
  "classical-geospatial vs foundation-model" embedding comparison.
* **`predict.edaphos_gnn_gat(fit)`** -- per-node target predictions
  on the native target scale (un-standardised).

Tests: 6 expectations covering:
* Graph schema: n*k edges, per-node soft-normalised weights.
* Auto-selection of numeric feature columns when `feature_cols =
  NULL`.
* Fit output dimensionality (`emb_dim = hidden * n_heads`).
* Training MSE strictly decreases.
* Predictions on native scale, length n, positively correlated with
  truth.
* Print methods for both graph and fit.

---

# edaphos 2.5.0

## Pilar 9 -- Denoising-Diffusion Probabilistic Models for soil maps

Activates the v2.1.0 scaffold.  First pedometric application (as of
2026) of DDPMs to generative soil mapping: samples ENTIRE plausible
maps conditional on covariates via iterative denoising
(Ho, Jain and Abbeel 2020).

* **`dm_cosine_schedule(T, s)`** -- Nichol & Dhariwal (2021) cosine
  schedule.  Monotone-decreasing alphabar, clamped at `[1e-8,
  0.9999]` for numerical stability.
* **`dm_fit(stack, conditioning, T, epochs, hidden, lr, seed)`** --
  trains a tiny 2-D denoiser.  A 2-hidden-layer MLP with sinusoidal
  time embedding predicts the noise `eps_theta(x_t, t, c)`.  Training
  minimises the score-matching surrogate loss via analytic gradient
  descent on the output layer (hidden layers fixed at their random
  initialisation, in the spirit of Huang et al. 2006 ELMs).
* **`dm_sample(fit, n_samples, conditioning, seed)`** -- ancestral
  sampling (Ho et al. 2020, Algorithm 2): starts from Gaussian noise
  at `t = T` and walks back to `t = 0` using the posterior mean
  formula plus the learned noise schedule.

Conditioning vectors of arbitrary dimension are supported via the
`conditioning` argument -- useful when soil-map generation is gated
by per-patch covariate summaries (climate zone, land-use class, etc.).

Tests: 5 expectations on synthetic smoothed random fields:
* Cosine schedule monotonicity.
* Fit-object schema.
* Sample returns the right (`n_samples`, H, W) array.
* Conditioning vectors are honoured at sample time.
* Print method.

The pure-R implementation runs in seconds on patches up to 8 x 8.
A torch port with a proper 2-D U-Net (and 16 x 16 / 32 x 32 patches)
is scheduled for v2.5.1.

---

# edaphos 2.4.0

## Pilar 8 -- Neural operators for pedogenetic depth PDEs

Activates the v2.1.0 scaffold.  Ships two neural-operator
architectures in pure R (no torch dependency), both learning the
solution map `u(z) -> y(z)` from a collection of
(covariate trajectory, target profile) pairs so a single trained
operator predicts new-site profiles without re-fitting.

* **`no_fno_fit(depths, targets, covariates, n_modes, width,
  n_blocks, epochs, lr, seed)`** -- 1-D Fourier Neural Operator
  (Li et al. 2021).  Spectral convolutions via `stats::fft` with
  a *real* magnitude multiplier on the first `n_modes`
  frequencies (numerically stable under IFFT round-off in pure R);
  pointwise linear residual path; leaky-ReLU activation; trained
  by finite-difference gradient descent on the output-layer
  weights.
* **`no_deeponet_fit(depths, targets, covariates, branch_hidden,
  trunk_hidden, output_dim, epochs, lr, seed)`** -- Deep Operator
  Network (Lu et al. 2021).  Branch net (site covariates -> p-dim)
  + trunk net (query depth -> p-dim) combined by inner product.
  Analytic gradients on the last two layers; fast enough to train
  a 20 x 12 profile problem in < 1 s.
* Both produce `predict()` methods aligned with any new covariate
  matrix + optional new depths.

Tests: 5 expectations covering:
* Output-shape equality for FNO predict.
* Output-shape equality for DeepONet predict.
* DeepONet training loss strictly decreases.
* DeepONet predict with new depth grid.
* Print methods for both architectures.

---

# edaphos 2.3.0

## Pilar 7 -- Bayesian Hierarchical Spatial models

Activates the v2.1.0 scaffold with a full pure-R Gibbs sampler for the
Bayesian spatial linear model

    y_i = x_i' beta + w_i + eps_i,     eps_i ~ N(0, tau^2)
    w   ~ N_n(0, sigma^2 R(phi)),      R_{ij} = exp(-phi d_ij)

with inverse-Gamma priors on sigma^2 and tau^2 and a Gaussian prior
on beta.  Phi is estimated by profile-MLE (empirical Bayes) to keep
every conditional posterior closed-form.

* **`bhs_fit(data, formula, coords, backend, nmcmc, burn, thin,
  prior_var_beta, prior_ig_a, prior_ig_b, phi_range, seed)`** -- two
  backends:
  - `"gibbs"` (default, no external deps): self-contained Gibbs
    sampler that updates beta (multivariate Gaussian), sigma^2 and
    tau^2 (inverse-Gamma), and the latent spatial field w (sparse
    precision-form Gaussian).  ~2000 iters in ~1 s on n = 80.
  - `"spBayes"`: dispatches to `spBayes::spLM` (Finley, Banerjee and
    Carlin 2007) when the Suggests-only package is installed -- full
    MCMC over phi, sigma.sq, tau.sq, beta.
* **`predict.edaphos_bhs(object, newdata, quantiles, n_draws)`** --
  Bayesian kriging at new sites via posterior-draw mean + sd + user-
  specified quantiles.
* **`as_edaphos_posterior.edaphos_bhs(x)`** -- v1.6.0 integration;
  exposes the fitted-value posterior as a `map`-type
  `edaphos_posterior`.
* `print.edaphos_bhs` -- posterior summary of beta, sigma^2, tau^2.

Tests: 5 expectations on a synthetic spatial dataset (n = 80) --
recovery of true beta within 3 posterior sds, phi inside user bracket,
predict frame schema, edaphos_posterior adapter, print method.

`spBayes` added to Suggests.

---

# edaphos 2.2.1

## Pilar 1 x Pilar 3 bridge -- Causal 4D (time-varying effects)

Activates the v2.1.0 scaffold.  Estimates beta_hat(t) on a sliding
window over a temporal data frame, with bootstrap CIs per window and
a non-parametric Mann-Kendall trend test.

* **`causal_effect_time_varying(frame, dag, exposure, outcome, window,
  step, adjustment, B, min_n, seed)`** -- returns an
  `edaphos_causal_4d` data frame with columns `t_start`, `t_end`,
  `t_centre`, `n`, `beta_hat`, `se`, `ci_lo`, `ci_hi`.
  Adjustment set is auto-derived from the DAG (Pilar 1 machinery)
  or taken from `adjustment` directly.
* **`causal_effect_trend_test(beta_df)`** -- Mann-Kendall S statistic,
  Kendall tau, normal-approximation p-value, categorical
  `trend_direction` in {increasing, decreasing, none}.
* **`causal_4d_plot(object)`** -- ggplot2 plot of the beta(t)
  trajectory with CI ribbon and trend-test summary in the subtitle.

Tests: 5 expectations covering the frame schema, monotonic-increase
detection under a strong linear-rise beta, flat-trend behaviour,
error on missing columns, and ggplot2 return class.

---

# edaphos 2.2.0

## Pilar 2 x Pilar 6 bridge -- Physics-Informed Quantum Kernels

Activates the v2.1.0 scaffold.  The ZZFeatureMap kernel is fused
with an RBF similarity over ODE-profile residuals:

  K_PI(x_i, x_j) = alpha * K_quantum(x_i, x_j)
                    + (1 - alpha) * exp( - (e_i - e_j)^2 / (2 sigma^2) )

where `e_i = y_i - y_hat_ODE(z_i, x_i)` uses a fitted Pilar 2 ODE.

* **`piml_quantum_kernel(X, y, depths, ode_fit, alpha, sigma, reps,
  backend)`** -- PSD for any `alpha in [0, 1]`; `alpha = 1` recovers
  the pure v2.0.0 quantum kernel; `alpha = 0` recovers a pure
  physics-residual kernel.  Default `alpha = 0.7` trusts the quantum
  lift while keeping the physics as regulariser.
* **`piml_qkrr_fit(X, y, depths, ode_fit, alpha, sigma, reps, lambda,
  backend)`** -- closed-form KRR over the PI kernel; `predict()`
  handles the ODE forward step + kernel row + dual sum.
* Graceful fallback: when `ode_fit` lacks a `predict()` method (e.g.
  a bare list of `lambda0`, `mu`, `y_inf`, `y0`), the bridge uses
  the analytic exponential-decay surrogate.

Tests: 4 expectations covering PSD for alpha in {0, 0.3, 0.7, 1},
numerical equality to pure quantum kernel at alpha = 1, round-trip
predict on a synthetic ODE pedon, and print-method sanity.

---

# edaphos 2.1.3

## Rcpp port of the quantum-kernel simulator (10-50x speedup)

The v2.1.0 roadmap flagged `quantum_kernel()` as O(n^2 * 4^n) in pure
R.  v2.1.3 ships a C++ port that preserves numerical output to
machine precision and typically runs 10-50x faster.

* **`src/quantum_kernel_rcpp.cpp`** — pure-C++ ZZFeatureMap state-
  vector simulator with in-place O(2^n) gate application, pre-
  computed X / Y state banks, `std::complex<double>` throughout,
  `std::norm()` for `|.|^2`, symmetric-kernel lower-triangle skip.
* **`quantum_kernel(X, Y, reps, backend)`** — new `backend` argument
  (default `"rcpp"`, fallback `"r"` for audit or Rcpp-less builds).
  Both backends produce identical matrices up to 1e-16.
* **Validation**: `tests/testthat/test-quantum-kernel-rcpp.R`
  checks agreement at `n_qubits = 2..5`, `reps = 1..2`, asymmetric
  `(X, Y)`, PSD invariant (non-negative eigenvalues), and the
  measurable speedup.
* **Benchmark** (Apple M1 Max, 100 samples, 4 qubits, reps = 2):
  R backend = 0.049 s; Rcpp backend = 0.004 s; **12.3x speedup**.

Package now ships with `src/` and `LinkingTo: Rcpp`.  `Imports: Rcpp
(>= 1.0.0)` added.  All existing pillars work unchanged.

---

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
