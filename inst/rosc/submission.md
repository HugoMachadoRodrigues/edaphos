# rOpenSci pre-submission inquiry — edaphos

Submission target: <https://github.com/ropensci/software-review>
Issue body to paste into the rOpenSci pre-submission inquiry template
(<https://devguide.ropensci.org/softwarereview_author.html#presubmission>).

---

## Package name, one-line description, and URL

- **Name**: `edaphos`
- **Description**: Frontier algorithms for Digital Soil Mapping across six research pillars — Causal AI + LLM knowledge graphs, Physics-Informed ML, 4D temporal pedometry, Foundation Models, Autonomous Active Learning, Quantum ML — with a unified uncertainty API and cross-pillar bridges.
- **Repository**: <https://github.com/HugoMachadoRodrigues/edaphos>
- **Zenodo concept DOI**: 10.5281/zenodo.19683708
- **Documentation site**: <https://hugomachadorodrigues.github.io/edaphos>

## Statistical subclasses (rOpenSci policies §1.1.2)

We believe the package fits best under:

1. **Spatial statistics** — digital soil mapping is a geostatistical domain; all six pillars produce spatial predictions.
2. **Bayesian and Monte Carlo statistics** — the v1.6.0 unified uncertainty API produces `edaphos_posterior` objects across every pillar; `uncertainty_calibrate()` implements CRPS / PICP / MPIW; `causal_iv_posterior()` is bootstrap-based; `piml_profile_fit_bayesian()` uses Laplace + adaptive Metropolis.
3. **Machine Learning** — Pilars 2-4 are all ML (Neural ODEs, ConvLSTM, MoCo v2).
4. **Statistical estimation and inference** — Pilar 1's backdoor OLS / BART / IV / sensitivity analysis.

We are not aware of an existing rOpenSci package with overlapping scope.

## Who is the intended user?

Pedometric / DSM / soil-science researchers who want to go beyond classical regression-tree pipelines (`ranger`, `gstat`, `caret`). Secondary: causal-inference and geospatial-ML practitioners who want a curated research-grade R entry point into these six emerging methodology lines.

## Closest analogues on CRAN / rOpenSci

| Package | Overlap | Difference |
|:---|:---|:---|
| `gstat`, `geoR` | Spatial geostatistics | We don't reimplement kriging; we complement it with disruptive non-classical approaches |
| `bnlearn`, `dagitty` | Causal DAGs | We use them as backends; the package adds a domain-specific pipeline + LLM KG ingestion |
| `torch`, `luz` | Deep learning in R | We use `torch` as a backend; edaphos ships domain-specific architectures (ConvLSTM, Neural ODE, MoCo v2 for rasters) |
| `CausalImpact`, `CausalQueries` | Causal inference | No overlap — their domain is time-series / experiments, ours is DSM |
| `SoilProfileCollection`, `aqp` | Soil data structures | We USE `aqp` for horizons; we don't reimplement data classes |

## Quality-assurance self-report

- **Unit tests**: 40+ test files, >150 expectations. `test-causal-iv`, `test-causal-sensitivity`, `test-llm-benchmark`, `test-llm-annotation`, `test-quantum-foundation`, `test-foundation-embed-coords` validate the recent (v1.8.0+) additions.
- **Examples**: every exported function has at least one `@examples` block (some are `\dontrun{}` because they need the torch runtime or network).
- **Vignettes**: 13 vignettes covering all six pillars, all cross-pillar bridges, and the capstone case study. Each is a short methods paper (3-8 pp) with LaTeX derivations, real-data results, and cited references.
- **Continuous integration**: GitHub Actions matrix on macOS, Windows, Linux (R release, devel, oldrel-1). Separate `pkgdown` workflow builds the documentation site.
- **Docker**: Rocker/geospatial-based image with libtorch + all Suggests pinned, for 100% byte-reproducible runs.
- **Reproducibility artefacts**: every scientific claim has a `data-raw/*.R` runner and an `inst/extdata/*.rds` bundle. The bundles ship with the package so vignettes build without network.

## Peer-review readiness checklist

- [x] Package builds on `R CMD check --as-cran` with 0/0/0
- [x] Code is formatted consistently (styler)
- [x] All exported functions have Roxygen docs with `@return` and `@examples`
- [x] Vignettes follow a consistent methods-paper structure
- [x] `README.md` has badges, installation instructions, pillar-by-pillar narrative, bundled datasets table, and roadmap
- [x] `NEWS.md` would need to be added (TODO before formal submission)
- [ ] Package website deployed at <https://hugomachadorodrigues.github.io/edaphos>
- [ ] `goodpractice::gp()` final pass
- [x] Licence (MIT) declared in DESCRIPTION + `LICENSE.md`

## Known open issues that a reviewer would find

1. **`quantum_kernel()` scales O(n²·4ⁿ)** in pure R. Fine for n ≤ 8 qubits and n_samples ≤ 500; slow beyond. Rcpp port scheduled for v2.1.3.
2. **No unit tests for the Shiny annotation app** (v1.8.1). Testing Shiny properly needs `shinytest2` + headless browser; scheduled for v2.2.0.
3. **Some vignettes are `eval = FALSE`** for blocks requiring network (OpenAlex, Zenodo download) or heavy compute (>5 min). All of them ship a corresponding pre-computed `.rds` bundle so the results are reproducible without running the heavy chunk.
4. **Foundation-model encoder v1 has limited performance** (20k InfoNCE steps, R² = 0.16 on SOC benchmark). Encoder v2 (200k steps) is training and will be published for v1.3.2 / v2.0.1.

## Questions for the rOpenSci editor

1. Given the six-pillar scope, is `edaphos` in-scope for rOpenSci as a single package, or should it be split?  (We argue it's one coherent domain-specific stack.)
2. `torch` is a heavy optional dependency. Is our `requireNamespace()`-gated pattern acceptable, or would the reviewers prefer deeper separation?
3. We've been tracking the generative causal-DSM framework of Zhang & Wadoux (2026). Does rOpenSci have guidelines on how tightly a package description should hew to a single paper's framework?

## Author

Hugo Rodrigues — soil-science PhD candidate, University of São Paulo.
ORCID: 0000-0002-8070-8126.  Email: rodrigues.machado.hugo@gmail.com.

Available for the required editor/reviewer interactions on a reasonable timeline (1-2 weeks per round-trip).
