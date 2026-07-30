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
