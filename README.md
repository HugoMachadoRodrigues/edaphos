# edaphos

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/HugoMachadoRodrigues/edaphos/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/HugoMachadoRodrigues/edaphos/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.19683708.svg)](https://doi.org/10.5281/zenodo.19683708)
[![GitHub release](https://img.shields.io/github/v/release/HugoMachadoRodrigues/edaphos?color=blue)](https://github.com/HugoMachadoRodrigues/edaphos/releases/latest)

[![ORCID](https://img.shields.io/badge/ORCID-0000--0002--8070--8126-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0000-0002-8070-8126)
[![Google Scholar](https://img.shields.io/badge/Google%20Scholar-profile-4285F4?logo=google-scholar&logoColor=white)](https://scholar.google.com/citations?hl=en&user=vu-Ka7wAAAAJ)
[![ResearchGate](https://img.shields.io/badge/ResearchGate-profile-00CCBB?logo=researchgate&logoColor=white)](https://www.researchgate.net/profile/Hugo-Rodrigues-12)
[![X / Twitter](https://img.shields.io/badge/X-@Hugo__MRodrigues-000000?logo=x&logoColor=white)](https://x.com/Hugo_MRodrigues)
<!-- badges: end -->

*From Greek ἔδαφος — “soil, ground.”*

**edaphos** is a research-grade R package that implements frontier
algorithms for Digital Soil Mapping (DSM) beyond the current
state-of-the-art regression/random-forest toolbox
(McBratney et al. 2003; Wadoux, Minasny & McBratney 2020). Instead of
one more tabular predictor, **edaphos** organises its contributions as
**six research pillars** — each of them confronts a specific
methodological gap of the literature.

## 1. Research pillars

| Nº  | Pillar                        | Namespace      | Governing object / equation                                                                                                           | Status (0.0.5) |
|---- |------------------------------ |--------------- |---------------------------------------------------------------------------------------------------------------------------------------|----------------|
| 1   | Causal AI                     | `causal_*`     | Structural causal model $G = (V, E)$; backdoor-adjusted estimand $\beta_{x \to y}^{\text{do}}$ (Pearl 2009)                           | scaffold       |
| 2   | Physics-Informed ML (PIML)    | `piml_*`       | Pedogenetic ODE $\dfrac{dy}{dz} = -\lambda_0 e^{-\mu z}(y - y_\infty)$ and Neural-ODE $\dfrac{dy}{dz} = f_\theta(z,y,\mathbf{x})$     | implemented    |
| 3   | 4D Pedometry                  | `temporal_*`   | Stacked ConvLSTM (Shi et al. 2015) with sequence-to-sequence training, multi-step rollout and a mass-balance physics loss             | implemented    |
| 4   | Foundation Models             | `foundation_*` | SimCLR contrastive objective $\mathcal{L}_{\text{NT-Xent}}$ on unlabelled raster patches (Chen et al. 2020)                           | scaffold       |
| 5   | Autonomous Active Learning    | `al_*`         | Closed-loop policy $\pi(\mathbf{x}) = \alpha\,\tilde u(\mathbf{x}) + (1 - \alpha)\,\tilde d(\mathbf{x})$ with PIML-backed physics gate | implemented    |
| 6   | Quantum ML                    | `quantum_*`    | Variational quantum circuits for organo-mineral simulation                                                                             | roadmap        |

Every pillar links (i) a mathematically explicit governing object, (ii)
an R function family (namespace column) and (iii) a vignette that
derives the object from first principles and demonstrates it on real
or reproducible synthetic data.

## 2. Installation

```r
# Core package
remotes::install_github("HugoMachadoRodrigues/edaphos",
                       build_vignettes = TRUE)

# Optional heavy dependencies (Pillars 2 Neural ODE, 3 ConvLSTM, 4 SimCLR)
install.packages("torch");       torch::install_torch()
# Optional Pillar 1
install.packages("dagitty")
# Optional Pillar 5 live data
install.packages("geodata")
```

`edaphos` itself imports only **clhs**, **deSolve**, **ranger** and
**stats**, so the base install is light; the heavier stacks are opt-in
through `Suggests` and are required only by their respective pillars.

## 3. Minimum working example — Pillar 5

```r
library(edaphos)
data(meuse, package = "sp")

d <- na.omit(meuse[, c("x","y","dist","elev","ffreq","soil","lead")])
d$ffreq <- as.numeric(d$ffreq); d$soil <- as.numeric(d$soil)

set.seed(1)
seed <- al_initial_design(d, c("dist","elev","ffreq","soil"),
                          n = 15, iter = 500)
m <- al_loop(
  labeled    = d[ seed, ],  candidates = d[-seed, ],
  target     = "lead",      covariates = c("dist","elev","ffreq","soil"),
  coords     = c("x","y"),
  budget     = 20, batch = 5, strategy = "hybrid", verbose = FALSE
)
al_history(m)
```

## 4. Vignettes

After installation with `build_vignettes = TRUE`:

```r
browseVignettes("edaphos")
```

* **pilar1-causal** — Backdoor adjustment in pedogenetic DAGs, with a
  side-by-side comparison of naive vs. causal estimators on the
  bundled `br_cerrado` dataset.
* **pilar2-piml-profile** — Pedogenetic ODE and Neural ODE of the
  depth profile, fit on `aqp::sp4`; introduction of the physics gate
  that bridges Pillar 2 with Pillar 5.
* **pilar3-4d-soc** — Stacked ConvLSTM sequence-to-sequence training
  and multi-step rollout forecasting on a reproducible synthetic SOC
  cube; optional physics-informed mass-balance regulariser.
* **pilar4-simclr-embeddings** — Contrastive pre-training on raw
  covariate patches; per-pixel embeddings as auxiliary covariates in
  the Pillar 5 loop.
* **pilar5-active-learning** — Formal derivation of the hybrid
  query policy and its `cost`-aware variant on the benchmark
  `meuse` dataset.
* **pilar5-soilgrids-br** — The same loop on a Cerrado recorte with
  synthesised SoilGrids-like inputs; ready to switch to live
  SoilGrids 250 m via `geodata`.

## 5. Reproducibility and testing

`edaphos` 0.0.5 ships with 120+ unit and integration tests
(`testthat`), covering every public function across the six pillars.
Tests that require optional runtime dependencies (`torch`, `dagitty`,
`sp`, `aqp`, `geodata`) are guarded by `skip_if_not_installed()` so
the base suite runs without libtorch.

Continuous integration on GitHub Actions checks the package on
`macos-latest`, `windows-latest` and three Ubuntu configurations
(release, devel, oldrel-1). A successful workflow run corresponds to
**0 errors / 0 warnings / 0 notes** under `R CMD check`.

## 6. Citation

Every release has a permanent DOI minted by Zenodo. The **concept DOI**
below resolves to the latest version and is the identifier to cite in
publications:

> Rodrigues Machado, H. (2026). *edaphos: Disruptive Algorithms for
> Digital Soil Mapping* (Version 0.1.0) [Software]. Zenodo.
> <https://doi.org/10.5281/zenodo.19683708>

```bibtex
@software{RodriguesMachado_edaphos_2026,
  author    = {Rodrigues Machado, Hugo},
  title     = {edaphos: Disruptive Algorithms for Digital Soil Mapping},
  year      = {2026},
  version   = {0.1.0},
  publisher = {Zenodo},
  doi       = {10.5281/zenodo.19683708},
  url       = {https://github.com/HugoMachadoRodrigues/edaphos}
}
```

Alternatively, an auto-generated citation is available in R:

```r
citation("edaphos")
```

## 7. Selected references

- Bishop, T. F. A., McBratney, A. B. & Laslett, G. M. (1999).
  Modelling soil attribute depth functions with equal-area quadratic
  smoothing splines. *Geoderma* **91** (1-2), 27-45.
- Chen, R. T. Q., Rubanova, Y., Bettencourt, J. & Duvenaud, D. K.
  (2018). Neural Ordinary Differential Equations. *NeurIPS 2018*.
- Chen, T., Kornblith, S., Norouzi, M. & Hinton, G. (2020). A Simple
  Framework for Contrastive Learning of Visual Representations.
  *ICML 2020*.
- Heuvelink, G. B. M. & Webster, R. (2001). Modelling soil variation:
  past, present, and future. *Geoderma* **100** (3-4), 269-301.
- Jenny, H. (1941). *Factors of Soil Formation: A System of
  Quantitative Pedology.* McGraw-Hill.
- Karniadakis, G. E. *et al.* (2021). Physics-informed machine
  learning. *Nature Reviews Physics* **3**, 422-440.
- McBratney, A. B., Mendonça Santos, M. L. & Minasny, B. (2003). On
  digital soil mapping. *Geoderma* **117** (1-2), 3-52.
- Meinshausen, N. (2006). Quantile Regression Forests. *JMLR* **7**,
  983-999.
- Minasny, B. & McBratney, A. B. (2006). A conditioned Latin
  hypercube method for sampling in the presence of ancillary
  information. *Computers & Geosciences* **32** (9), 1378-1388.
- Pearl, J. (2009). *Causality: Models, Reasoning, and Inference.*
  2nd ed., Cambridge University Press.
- Shi, X. *et al.* (2015). Convolutional LSTM network: a machine
  learning approach for precipitation nowcasting. *NeurIPS 2015*,
  802-810.
- Textor, J. *et al.* (2016). Robust causal inference using directed
  acyclic graphs: the R package 'dagitty'. *International Journal of
  Epidemiology* **45** (6), 1887-1894.
- Wadoux, A. M. J.-C., Minasny, B. & McBratney, A. B. (2020). Machine
  learning for digital soil mapping. *Earth-Science Reviews*
  **210**, 103359.

A complete bibliography ships with the package vignettes at
`vignettes/references.bib`.

## 8. License

MIT © Hugo Rodrigues Machado. See [`LICENSE.md`](LICENSE.md).
