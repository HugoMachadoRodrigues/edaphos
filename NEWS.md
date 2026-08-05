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
  `y(Inf) = y_inf + (y0 - y_inf) exp(-kappa)`. Across the 1,105 shipped WoSIS
  profiles the median `kappa` is 1.6, so the median profile closes 80% of its
  gap and stops; on shallow profiles the two quantities routinely differ in
  sign. `print()` now labels `y_inf` as an ODE coordinate and reports `y(Inf)`
  and `kappa` alongside it.
- **The model is estimated in the identified, positive coordinates**
  `(y0, A, kappa, mu)` with `A = y(Inf)`, all exponentiated; `lambda0` and
  `y_inf` are recovered unchanged for the public interface. Refitting 207
  multi-horizon WoSIS profiles under both parameterisations: the old one
  returned a physically inadmissible fit for 116 of them (56%) — 113 with
  `mu < 0`, a decay rate growing exponentially with depth, and two with negative
  surface carbon — against none under the new one. Genuinely ascending profiles
  (argillic clay) are still fitted as such.
- **The posterior now identifies what matters.** On the shipped pedon the 95%
  interval for the attainable deep value is [0.95, 4.48] g/kg, against
  [−20.5, 3.2] for the quantity previously reported as the asymptote: 6.7
  times narrower and no longer reaching into impossible values. `summary()` gains
  `kappa` and `y_asym` rows, and the Bayesian priors are placed on the
  identified coordinates rather than on `y_inf`.
- **`al_physics_gate_piml()` no longer certifies negative carbon as plausible.**
  Its envelope was built from `y_inf`; it is now the range the solution actually
  spans, floored at zero. See the section below for the measured effect on 300
  real pedons.
- **Horizon-average observation operator.** `piml_profile_fit()` and
  `piml_profile_fit_bayesian()` accept `top`/`bottom` horizon boundaries and
  compare each datum to the model's depth-average over its horizon (8-node
  Gauss–Legendre on the closed form) rather than to a point evaluation at the
  mid-depth. Across 207 profiles this moves the fitted `y0` by a median
  0.28 g/kg and the deep value by 0.03 -- the correction is concentrated in the
  thick, strongly curved surface horizons.
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
  `aqp::sp4` pedons, and neither of those two beats a straight line. Two
  companion diagnostics, `surface_ratio` and `in_scope`, were added later.
- A non-positive observed value is now an error rather than a silent fit, and
  the fitter uses several starting points instead of one.
- Evaluating the closed form is ~281x faster than integrating with `deSolve`
  and agrees with it to 4e-5 g/kg; the equivalence is pinned in
  `tests/testthat/test-piml-closed-form.R`.
- The Pillar-2 parameter table in `inst/extdata/capstone_campaign_results.rds`
  was regenerated from a real Laplace fit under the new parameterisation, and
  again after the pedon was replaced with a real WoSIS profile (below).

## Pillar 2 refitted to real data, and its domain declared

A panel of five specialist pedometric reviewers read this pillar. Four of
the five gave the same worst problem, and it was not the parameterisation:
the pillar was calibrated on seven numbers typed into
`data-raw/capstone_campaign_run.R` while 1,105 real multi-horizon WoSIS
Cerrado profiles sat unused in `tools/case_cerrado/`, downloaded by this
repository's own scripts, which then kept only the shallowest horizon of each.

- **Real data.** `data-raw/piml_wosis_multihorizon.R` keeps every horizon:
  1,105 profiles, 5,853 horizons, median 150 cm and maximum 740 cm, shipped as
  `inst/extdata/piml_wosis_cerrado.rds`. The capstone pedon is now WoSIS
  profile 1115679 — nine horizons to 550 cm — selected by a criterion fixed
  before any fit was inspected.
- **A derivable alternative.** `piml_profile_fit_mechanistic()` implements the
  advection-reaction limit of the standard soil-carbon depth balance,
  `v dC/dz = I(z) - kC` with root input `I(z) = I0 exp(-z/z_r)`: constant rate,
  depth-varying target. Closed form, analytic layer averages, every parameter
  positive with a literature prior. It fits the shipped pedon markedly better
  (RMSE 0.44 vs 2.52), but across the profiles in the model's domain the two
  are statistically indistinguishable once both are fitted with a correct
  likelihood — see the likelihood section below, which cost this entry its
  original claim.
- **A benchmark, reported whatever it says.** `data-raw/piml_depth_benchmark.R`
  runs two pre-declared tasks over all 1,105 profiles against six competitors,
  including an equal-area spline and a pooled depth-as-covariate random forest.
  On mean absolute error the mechanism helps -- 1.82 g/kg for the ODE against
  2.06 for copying the nearest measured horizon and 2.67 for the random forest,
  winning the paired comparison against every baseline. On RMSE every method
  lands near 14 g/kg, because ten profiles carry 99% of the squared error; the
  gap between the two statistics is itself the finding. The equal-area spline
  does not extrapolate and abstains from the second task, which is reported
  rather than papered over. The restriction to the model's domain was
  originally computed in a way that leaked the held-out horizon; see the
  method-defects section below.
- **The domain is now declared and enforced.** `lambda0 > 0` with a first-order
  relaxation makes the solution monotone, so an argillic bulge, an E horizon
  under an A or a buried A cannot be represented. 15.4% of the shipped profiles
  are not monotone even in their training horizons, and those that break
  monotonicity only at the horizon being predicted cannot be excluded in
  advance at all. `piml_profile_fit()` records `in_scope`, `progress` (how
  far the deepest horizon travelled toward `y(Inf)`) and `surface_ratio` (`y0`
  reached 775 g/kg on one real profile), and `print()` says so.

## The parameters were confronted with something outside the fit

Pillar 2 claimed its parameters were identified and interpretable. Identified
it demonstrated; interpretable it asserted. `data-raw/piml_external_anchors.R`
tests two directional predictions the mechanism makes and a curve-fitting
device does not. They come out differently, and both are reported.

- **Hassink (1997) saturation: passes, weakly.** If `y(Inf)` is a
  mineral-associated floor it must rise with clay + silt. Across 812 monotone
  profiles with a texture estimate within 5 km it does — slope +0.0067 per
  percentage point, p = 0.03, Spearman rho = 0.10 — and the attained value of
  the attenuating-rate form gives the same sign more strongly (p = 0.002).
  Texture explains 0.5% of the variance, though, and it is a SoilGrids
  prediction from a product trained partly on the same WoSIS archive. Reported
  as consistent with the mechanism and much weaker than a confirmation.
- **Jobbagy & Jackson (2000) beta: fails, and is withdrawn as an anchor.** The
  implied beta is plausible in level (median 0.971, 5-95% 0.957-0.980) but
  moves with nothing outside the fit: tree cover R^2 = 0.00003, clay
  R^2 < 0.0001, precipitation R^2 = 0.0005. The one external variable it tracks
  is how deep the profile happened to be dug (R^2 = 0.024), a property of the
  survey. Meanwhile 63% of its variance is explained by our own fitted surface
  concentration. A statistic two-thirds determined by a parameter of the model
  it is meant to validate is not external evidence.

The constant-density assumption behind the beta calculation was measured
rather than asserted: on the eight profiles carrying bulk density, computing
the cumulative from mass rather than concentration moves the median beta by
less than 0.0001.

## Three method defects that invalidated published numbers

A full verification sweep of the specialist panel's 266 findings -- deduplicated
to 190 unique defects and each re-checked against the current tree -- surfaced
three defects of method, not of implementation. Each one had produced a number
that appears in the manuscript.

**The benchmark's skill column was scored against an oracle.**
`edaphos_r2(truth, pred)` divides by the variance of the test values about
*their own* mean, which is computed from the very rows being scored. The
manuscript's Table 4 described that column as "measured against each fold's
training mean", and its introduction states in as many words that scoring
against the mean of the rows being scored is an oracle rather than a baseline.
The roxygen of `edaphos_r2()` carried the same warning. The benchmark called it
anyway. New `edaphos_nse(observed, predicted, null_prediction)` takes the null
as a **required** argument and errors without it. Against the achievable null
two methods score below zero, not three.

**Spatially blocked folds had no buffer.** The training set was the exact
complement of the test block, with a measured minimum training-to-test distance
of 12.3 km -- well inside the 55-68 km range at which the fitted depth-function
parameters are still correlated. New `spatial_block_folds(coords, k,
buffer_km, seed)` discards training rows within the buffer, reports how many,
and returns the realised minimum distance. At 68 km it costs 88 of 3,077 rows.
Only one method moved: P10 GAT went from RMSE 0.617 to 0.679 and from +0.112 to
-0.067 skill, fifth place to last. A network built on a graph of spatial
neighbours is exactly the method that gains from training points immediately
across a block boundary, which is what the buffer exists to remove.

**The depth benchmark's validity-domain stratifier read the held-out horizon.**
It judged a profile monotone from its *complete* record, including the deepest
horizon that the extrapolation task holds out -- so it excluded precisely the
profiles whose held-out horizon jumps. Computed from training horizons only, as
it must be, the subset grows from 875 to 935 profiles and the ODE's RMSE goes
from 1.51 to 14.74. The manuscript's claim that declaring the validity domain
moved the RMSE from 14.04 to 1.51 was an artefact of the leak; the largest jump
in the held-out horizon is 17 g/kg among the profiles the leaking criterion
admitted and 427 g/kg among those the honest one admits.

What replaced it is a better result. Ten profiles out of 935 -- 1.1% -- carry
99% of the squared error, and removing them takes the RMSE to 1.54. The median
absolute error is 0.76 g/kg. The extreme case is a buried organic horizon,
430 g/kg at 125 cm with 3.0 g/kg immediately above it, and nothing available at
fit time predicts it: the correlation between the size of the jump and the
number of training horizons, the prediction depth, or the model's own
extrapolation diagnostic is below 0.03 in absolute value. A depth function
fitted to the horizons above cannot know a buried horizon is coming, and no
scope statement made from the same information can either.

## The likelihood was wrong for a soil concentration

`piml_profile_fit()`, `piml_profile_fit_bayesian()` and
`piml_profile_fit_mechanistic()` gain a `family` argument, and the default
is now `"lognormal"` rather than Gaussian on g/kg.

A Gaussian likelihood on a concentration makes three errors. It places
predictive mass below zero; it assumes additive error where laboratory
error is multiplicative; and — the one that costs accuracy — it weights
every horizon by the same *absolute* discrepancy, so a profile running from
29 g/kg at the surface to 2.3 g/kg at 5 m is fitted almost entirely by its
topsoil while the deep horizons that carry the asymptote contribute almost
nothing.

- Both alternatives are parameterised so that the model's prediction is the
  **mean** of the observation, and `sigma` is a coefficient of variation. Mean-
  preserving matters because the prediction is a horizon average, a mass-
  preserving quantity; a median-preserving lognormal would bias every layer
  down by `exp(sigma^2/2)`.
- On the shipped pedon the Gaussian fit misses the deepest horizon by 90% of
  its value; the lognormal caps its worst relative residual at 23%.
- On leave-the-deepest-horizon-out prediction across all 1,105 WoSIS profiles
  the lognormal wins on 720 of them (paired Wilcoxon p = 2e-30), improving mean
  absolute error from 2.20 to 2.00 g/kg, and wins on RMSE too — even though
  RMSE is the criterion the Gaussian optimises by construction, because
  over-weighting the topsoil is what makes a profile extrapolate its deepest
  horizon badly. (These figures were first measured on a subset selected by the
  leaking stratifier described below and have been remeasured without it.)
- `predict()` draws observation noise from the family the model was fitted
  with. Adding Gaussian noise to a positive fit would reintroduce the defect
  the argument exists to remove.

**This changed a published conclusion.** Under the Gaussian, the derived
advection-reaction model appeared to beat the attenuating-rate ODE decisively
on held-out prediction (p = 2e-6). Fitting both with a correctly specified
likelihood removes the difference: MAE 1.76 against 1.82 g/kg, winning on 486
of 935 profiles against 449, p = 0.25. The Gaussian had been penalising the
attenuating-rate form more, because over-weighting the topsoil hurts the model
whose flexibility lies in the deep tail. The derived model is now recommended
on the grounds that it can be derived, not on grounds of accuracy, where the
honest answer is a tie.

Two related corrections to the native calibration table. Its predictive
interval excluded observation noise while being scored against measured
values, which a mean-function interval structurally cannot cover: restoring it
takes the Pillar-2 PICP from 0.44 to 0.67, and the lognormal takes it to 0.78
while eliminating negative predictive draws entirely.

## Inference and unit-consistency fixes

- **`sigma` is sampled, not plugged in.** It was estimated once from the MAP
  residuals and held fixed through the whole MCMC — empirical Bayes that
  guarantees under-wide intervals. It now carries a half-t(3) prior; the
  predictive interval on the shipped pedon widens from 3.6 to 7.1 g/kg.
- **MCMC convergence is now reported.** The sampler ran one chain and reported
  only an acceptance rate, so R-hat could not be computed even in principle.
  It now runs `n_chains` from dispersed starts and reports rank-normalised
  split-R-hat and bulk ESS (Vehtari et al. 2021), and `print()` says
  NOT CONVERGED when they fail. That immediately caught the old defaults:
  5000/2000 gives max R-hat 1.015 and min ESS 361, against 1.004 and 1113 at
  20000 iterations. The default is now the converging one.
- **The default prior is empirical Bayes and says so.** Three of its
  hyperparameters are functions of the response. `piml_prior_literature()`
  provides a non-circular alternative built from published values, so the
  dependence can be measured rather than assumed harmless: on the shipped
  pedon it moves the attainable deep value from 2.22 [0.95, 4.48] to
  2.45 [1.18, 4.56], so the circularity is not load-bearing here — but that is
  now a measurement rather than an assumption.
- **`al_physics_gate_piml()` no longer certifies negative carbon.** Rebuilding
  its envelope from the attained value closed one route to a negative floor;
  the `(safety_factor - 1) * span` widening was the other. On 300 real WoSIS
  pedons the documented default gave a negative floor on 247 and accepted an
  SOC of -5 g/kg on 73. It now floors at zero for the parametric branch, which
  is by construction a fit to a positive property.
- **Pillar 3's mass-balance loss divided by a z-scored mean.** That mean is
  zero to machine precision, so the `1e-6` guard turned the outflow term into a
  1e6 amplification: the physics residual arrived 2.6e7 times heavier than the
  data term, its sign flipped with the seed, and it destroyed the fit it was
  meant to regularise (fit loss 1.007 at `physics_lambda = 1` against 0.085 at
  0). `temporal_convlstm_fit()` now takes `physics_scaling` and forms the
  residual in the raw units the rate constants are written in. The same run now
  gives 0.072 against 0.085: the physics term helps for the first time. Without
  the scaling constants it errors rather than evaluating on the wrong scale.

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
