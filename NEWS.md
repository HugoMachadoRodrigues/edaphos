# edaphos 0.9.0 (development version — not yet released)

edaphos is a research package for digital soil mapping beyond regression-tree
models, organised around ten methodological pillars: (1) causal inference —
backdoor adjustment on pedogenetic DAGs, instrumental variables, Cinelli–Hazlett
sensitivity, and LLM knowledge-graph extraction; (2) physics-informed ML — a
parametric pedogenetic ODE and a differentiable Neural ODE; (3) 4D pedometry —
stacked ConvLSTM with an Ensemble Kalman Filter; (4) foundation models —
SimCLR / MoCo-v2 contrastive pre-training on raster patches; (5) autonomous
active learning; (6) quantum ML — a ZZFeatureMap state-vector simulator and
quantum kernel ridge regression; (7) Bayesian hierarchical spatial models
(Gibbs / RcppArmadillo); (8) neural operators (DeepONet, Fourier Neural
Operator); (9) diffusion models (DDPM) for soil-map patches; and (10) graph
attention networks. A unified `edaphos_posterior` class lets every method be
scored with the same calibration diagnostics. The deep-learning pillars default
to `backend = "auto"` — the trained torch model when a working libtorch is
present, otherwise a pure-R reference path.

This is the first development version being prepared for submission; the API is
not yet stable.

## Development status

The package has never been released. Earlier `NEWS.md` carried 43+
version-numbered sections (0.8.0 → 4.1.0) written within a single development
sprint; those were internal labels, not releases — the git tags run only to
`v1.6.0` and then jump to `v3.10.0` / `v4.0.0`, and nothing named edaphos is on
CRAN. Those sections are preserved in the git history; `NEWS.md` is reset here to
a single honest development entry. Live, measured status (test counts, check
result, install size) is generated into `STATUS.md` and `cran-comments.md` by the
scripts in `tools/status/`, not written by hand.

## Pillar 2 reworked around the equation's closed-form solution

The depth-profile ODE `dy/dz = -lambda0 * exp(-mu*z) * (y - y_inf)` is separable
and has an analytic solution. Using it instead of a numerical integrator exposed
a mislabelling and a mis-parameterisation that had propagated into the shipped
results, the active-learning gate and the manuscript.

- **`y_inf` is not the deep asymptote and is no longer reported as one.** Since
  the rate decays with depth, the profile traverses only `1 - exp(-kappa)` of
  the `y0 -> y_inf` gap, with `kappa = lambda0/mu`, and settles at
  `y(Inf) = y_inf + (y0 - y_inf) exp(-kappa)`. On the pedon shipped with the
  package `y_inf` is −5.9 g/kg — an impossible negative carbon concentration —
  while the profile actually approaches +0.70. `print()` now labels `y_inf` as
  an ODE coordinate and reports `y(Inf)` and `kappa` alongside it.
- **The model is estimated in the identified, positive coordinates**
  `(y0, A, kappa, mu)` with `A = y(Inf)`, all exponentiated; `lambda0` and
  `y_inf` are recovered unchanged for the public interface. Refitting 207
  multi-horizon WoSIS profiles under both parameterisations: the old one
  returned a physically inadmissible fit for 116 of them (56%) — 113 with
  `mu < 0`, a decay rate growing exponentially with depth, and two with negative
  surface carbon — against none under the new one. Genuinely ascending profiles
  (argillic clay) are still fitted as such.
- **The posterior now identifies what matters.** On the shipped pedon the 95%
  interval for the attainable deep value is [0.50, 3.78] g/kg, against
  [−11.93, 6.03] for the quantity previously reported as the asymptote: 5.5
  times narrower and no longer covering impossible values. `summary()` gains
  `kappa` and `y_asym` rows, and the Bayesian priors are placed on the
  identified coordinates rather than on `y_inf`.
- **`al_physics_gate_piml()` no longer certifies negative carbon as plausible.**
  Its envelope was built from `y_inf`; it is now the range the solution actually
  spans. The gate previously accepted an SOC of −10 g/kg while rejecting 178 of
  399 legitimate candidates; it now rejects the negative value and 89 of 399.
- **Horizon-average observation operator.** `piml_profile_fit()` and
  `piml_profile_fit_bayesian()` accept `top`/`bottom` horizon boundaries and
  compare each datum to the model's depth-average over its horizon (8-node
  Gauss–Legendre on the closed form) rather than to a point evaluation at the
  mid-depth. Across the 207 profiles this moves the fitted `y0` by a median
  0.25 g/kg and the deep value by 0.03.
- **The L2 regulariser is centred on the data-driven start.** It previously
  penalised the raw `y_inf`, so it scaled with the square of the property's
  units and silently did part of the fitting: on the `aqp::sp4` colusa pedon it
  pinned `y_inf` at 61.9% clay, which the README reported as the
  argillic-horizon asymptote. The same four horizons with the penalty removed
  give 533%. The number was imposed, not estimated.
- **`piml_profile_fit()` reports an extrapolation diagnostic.** The new
  `progress` component is the fraction of the `y0 -> y(Inf)` journey the
  deepest horizon actually travelled; below 0.5 `print()` states that the deep
  value is an extrapolation rather than an estimate. It flags two of the ten
  `aqp::sp4` pedons, and neither of those two beats a straight line.
- A non-positive observed value is now an error rather than a silent fit, and
  the fitter uses several starting points instead of one.
- Evaluating the closed form is ~281x faster than integrating with `deSolve`
  and agrees with it to 4e-5 g/kg; the equivalence is pinned in
  `tests/testthat/test-piml-closed-form.R`.
- The Pillar-2 parameter table in `inst/extdata/capstone_campaign_results.rds`
  was regenerated from a real Laplace fit under the new parameterisation.

## Corrections to withdrawn pre-release notes

The withdrawn version-numbered notes contained claims that were never verified.
They are corrected here rather than merely deleted:

- **"R CMD check: 0 errors / 0 notes"** was never checked against a log; a real
  `R CMD check --as-cran` on the v3.10.0 tree produced 2 ERRORs, 1 WARNING and
  6 NOTEs. All are fixed, and the current status is generated into
  `cran-comments.md`.
- **Test counts** ("1 345 tests pass", "1 308", …) were quoted without their
  environment and did not always reconcile between sections. Current figures are
  measured into `STATUS.md` with platform and dependency context.
- **Pillar 1 × Pillar 4 (instrumental variables).** Earlier notes and the README
  reported Sargan p = 0.343 / 0.283 / 0.424 and concluded that foundation-model
  embeddings are valid instruments. That run used placeholder normalisation
  (`means = 0`, `sds = 1`) over synthetic (noise) covariates. Re-run with a real
  MoCo-v2 encoder on real WoSIS Cerrado profiles, the embedding-PC instruments
  are strong (stage-1 F ≈ 1955) but **fail** the Sargan over-identification test
  (p ≈ 3×10⁻¹³): a learned representation does not manufacture a valid
  instrument. The README and the `pilar1-pilar4-iv` vignette now report this
  negative result, and `tests/testthat/test-causal-real-bundle.R` binds the
  figures to the shipped bundle so they cannot drift again.
- **Multi-backend LLM benchmark** (Gemma 4 / GPT-4o-mini / Claude). The shipped
  bundle carried `mode = "simulated"` — a deterministic noise model, not
  measurements, with no API called. The vendor-attributed table was withdrawn.
  The causal-discovery "LLM-augmented" DAG, once six hand-typed edges, is now a
  real Gemma-4 extraction over the shipped Cerrado abstracts.

Nothing here changes what the code does; it changes what the project claims about
what the code showed.
