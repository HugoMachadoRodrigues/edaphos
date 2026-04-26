# rOpenSci pre-submission inquiry — edaphos v3.10.0

Submission target: <https://github.com/ropensci/software-review>
Issue body to paste into the rOpenSci pre-submission inquiry template
(<https://devguide.ropensci.org/softwarereview_author.html#presubmission>).

---

## Package name, one-line description, and URL

- **Name**: `edaphos`
- **Version**: 3.10.0
- **Description**: Frontier algorithms for Digital Soil Mapping
  organised around **ten research pillars** -- Causal AI + LLM
  knowledge graphs (P1), Physics-Informed depth-profile ODE (P2),
  4D temporal pedometry (P3), Foundation Models (P4), Autonomous
  Active Learning (P5), Quantum ML (P6), Bayesian Hierarchical
  Spatial (P7), Neural Operators (P8), Diffusion Models (P9), and
  Graph Attention Networks (P10) -- with a unified `edaphos_posterior`
  uncertainty API and six v3.0.0 cross-pillar bridges.
- **Repository**: <https://github.com/HugoMachadoRodrigues/edaphos>
- **Zenodo concept DOI**: 10.5281/zenodo.19683708
- **Documentation site**: <https://hugomachadorodrigues.github.io/edaphos>

## Statistical subclasses (rOpenSci policies §1.1.2)

We believe the package fits best under:

1. **Spatial statistics** -- DSM is a geostatistical domain; every
   pillar produces spatially indexed predictions, including a
   proper Bayesian hierarchical kriging (P7) with profile-MLE for
   the GP rate parameter.
2. **Bayesian and Monte Carlo statistics** -- the v1.6.0 unified
   uncertainty API yields `edaphos_posterior` objects across every
   pillar; `uncertainty_calibrate()` implements CRPS, PICP_q,
   MPIW_q.  v3.4.0 added an aleatoric-noise injection step that
   brings P1/P6/P10 PICP from 0.07-0.25 to 0.60-0.95.  v3.5.0
   added a RcppArmadillo Gibbs sampler.
3. **Machine Learning** -- Pilars 2-4, 8-10 are all ML (Neural
   ODEs, ConvLSTM, MoCo v2, DeepONet, FNO, DDPM, GAT).
4. **Statistical estimation and inference** -- Pilar 1's backdoor
   OLS / BART / IV / sensitivity analysis + structure learning
   via bnlearn.

We are not aware of an existing rOpenSci package with overlapping
scope.

## Who is the intended user?

Pedometric / DSM / soil-science researchers who want to go beyond
classical regression-tree pipelines (`ranger`, `gstat`, `caret`).
Secondary: causal-inference and geospatial-ML practitioners who
want a curated research-grade R entry point into these ten
emerging methodology lines.

## Closest analogues on CRAN / rOpenSci

| Package | Overlap | Difference |
|---------|---------|------------|
| `gstat`, `geoR` | Spatial geostatistics | We don't reimplement kriging; we complement it with disruptive non-classical approaches |
| `bnlearn`, `dagitty` | Causal DAGs | We use them as backends; the package adds a domain-specific pipeline + LLM KG ingestion |
| `torch`, `luz` | Deep learning in R | We use `torch` as a backend; edaphos ships domain-specific architectures (ConvLSTM, Neural ODE, MoCo v2, DeepONet, FNO, DDPM, GAT) |
| `CausalImpact`, `CausalQueries` | Causal inference | No overlap -- their domain is time-series / experiments, ours is DSM |
| `SoilProfileCollection`, `aqp` | Soil data structures | We USE `aqp` for horizons; we don't reimplement data classes |
| `spBayes` | BHS MCMC | We use it as an alternative backend; primary backend is our own RcppArmadillo Gibbs |

## Quality-assurance self-report

- **Unit tests**: 50+ test files, **1 345 expectations**.
  Coverage spans every pillar's edge cases (NA inputs, degenerate
  matrices, reproducibility, device dispatch).
  `tests/testthat/test-pilar7-bhs-rcpp.R`,
  `tests/testthat/test-pilar10-gat-sparse.R`,
  `tests/testthat/test-llm-kg-pipeline.R`, etc., validate the
  recent additions.
- **Examples**: every exported function has at least one
  `@examples` block (some are `\dontrun{}` because they need the
  torch runtime, network access, or a live Ollama instance).
- **Vignettes**: 14 vignettes covering all 10 pillars, all
  cross-pillar bridges, and the capstone case study.  Each is a
  short methods paper (3-8 pp) with LaTeX derivations, real-data
  results, and cited references.  4 additional articles in
  `articles/` (case studies; `.Rbuildignore`-d to keep the
  vignette build fast).
- **Continuous integration**: GitHub Actions matrix on macOS,
  Windows, Linux (R release, devel, oldrel-1).  Separate `pkgdown`
  workflow builds the documentation site.
- **Docker**: Rocker/geospatial-based image with libtorch + all
  Suggests pinned, for byte-reproducible runs.
- **Reproducibility artefacts**: every scientific claim has a
  `data-raw/*.R` runner and an `inst/extdata/*.rds` bundle.  The
  bundles ship with the package so vignettes build without
  network.
- **Honest benchmarks**: `inst/extdata/benchmark_wosis_6pilar.rds`
  contains the v3.4.0 calibrated 6-pillar head-to-head on 1 095
  real WoSIS Cerrado profiles, scored with the unified
  `uncertainty_calibrate()`.

## Peer-review readiness checklist

- [x] Package builds on `R CMD check --as-cran` with 0 errors / 0
      notes.
- [x] Code is formatted consistently (styler).
- [x] All exported functions have Roxygen docs with `@return` and
      `@examples`.
- [x] Vignettes follow a consistent methods-paper structure.
- [x] `README.md` has badges, install instructions, pillar-by-pillar
      narrative, bundled datasets table, and roadmap.
- [x] `INTRO.md` (v3.9.0) provides a high-density narrative
      complement to README.
- [x] `cheatsheets/` (v3.9.0) one-page references per pillar.
- [x] `NEWS.md` is current (v3.10.0).
- [x] Licence (MIT) declared in DESCRIPTION + `LICENSE.md`.
- [ ] Package website deployed at
      <https://hugomachadorodrigues.github.io/edaphos> (gated only
      by enabling GH Pages in the repo settings; pkgdown builds
      cleanly locally).
- [ ] `goodpractice::gp()` final pass before formal submission.

## Known open issues that a reviewer would find

1. **`quantum_kernel()` scales O(n^2 * 4^n_qubits)** in pure R.
   v2.1.3 ships a Rcpp port that is ~12x faster on
   n_samples >= 100 (`quantum_kernel_rcpp()`).  Beyond
   n_qubits = 12 the state-vector simulation is intrinsically
   exponential in n_qubits.
2. **Some vignettes are `eval = FALSE`** for blocks requiring
   network (OpenAlex, Zenodo download) or heavy compute (>5 min).
   All ship a corresponding pre-computed `.rds` bundle so the
   results are reproducible without running the heavy chunk.
3. **P6 Quantum KRR PICP_90 is 0.60** (vs 0.81-0.95 for the other
   five methods) at the 1 095-profile Cerrado benchmark with
   `n_pcs = 6, reps = 1` (the n_pcs ceiling for tractable
   classical simulation).  Documented in v3.4.0 NEWS as a
   modelling limit, not a software bug.
4. **Some Suggests are pinned** (`bnlearn`, `dagitty`) because
   downstream changes in their public API would break Pilar 1.
   Tracked in our CI matrix.

## Questions for the rOpenSci editor

1. Given the 10-pillar scope, is `edaphos` in-scope for rOpenSci
   as a single package, or should it be split?  (We argue it's
   one coherent domain-specific stack with a unified
   `edaphos_posterior` API.)
2. `torch` is a heavy optional dependency.  Is our
   `requireNamespace()`-gated pattern acceptable, or would the
   reviewers prefer deeper separation?
3. The benchmark in `inst/extdata/benchmark_wosis_6pilar.rds`
   takes ~30 minutes to regenerate.  Would the editors prefer
   this bundle to be downloaded from Zenodo at runtime instead of
   shipped with the package?

## Author

Hugo Rodrigues -- soil-science PhD candidate, University of São
Paulo.
ORCID: 0000-0002-8070-8126.  Email: rodrigues.machado.hugo@gmail.com.

Available for the required editor/reviewer interactions on a
reasonable timeline (1-2 weeks per round-trip).
