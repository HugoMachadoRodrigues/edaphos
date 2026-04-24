# CRAN comments for edaphos v2.1.0

## Test environments
- **Local**: macOS 14 (Apple M1 Max), R 4.4.1; `R CMD check --as-cran` → 0 errors / 0 warnings / 0 notes.
- **GitHub Actions CI**:
  - macos-latest, R release
  - windows-latest, R release
  - ubuntu-latest, R release
  - ubuntu-latest, R devel
  - ubuntu-latest, R oldrel-1
- **Docker** (Rocker/geospatial): see `Dockerfile` in repo root.

## R CMD check results
```
Status: OK
0 errors | 0 warnings | 0 notes
```

## Heavy-optional dependencies
Every Suggests in `DESCRIPTION` is wrapped in `requireNamespace(..., quietly = TRUE)` inside the code that uses it. The base test suite runs without `torch`, `terra`, `geodata`, `dagitty`, `bnlearn`, `shiny`, or `reticulate` installed. Vignettes that need heavy packages use `eval = FALSE` blocks with code that the user copy-pastes into an interactive session.

## Reasons for optional dependencies
| Suggests       | Used by             | Why optional                                 |
|:---------------|:--------------------|:---------------------------------------------|
| `torch`        | Pilars 2, 3, 4      | libtorch ~1 GB; many users will not need it |
| `terra`        | Pilar 4 raster ops  | Heavy geospatial stack                       |
| `geodata`      | `foundation_build_cerrado_stack` | ~200 MB live downloads         |
| `dagitty`      | Pilar 1             | Fast but adds 10+ MB of deps                |
| `bnlearn`      | Pilar 1 discovery   | Structure-learning only                     |
| `shiny/DT/bslib/shinyjs` | Annotation UI (v1.8.1+) | Interactive app; not needed for lib users |
| `reticulate`   | Pilar 6 Qiskit      | Python bridge only for IBM Quantum runs      |
| `jsonlite`     | LLM benchmark       | Tiny; used everywhere so could be Imports    |

## Suggests → Imports candidates for next release
We are deliberately conservative with Imports to keep the base install <30 MB. `jsonlite`, `dplyr`, `ggplot2` are used by many exported functions and could move to Imports in v2.2.0 after a CRAN-policy review.

## Downstream dependencies
None yet (this is the first CRAN submission). The package is listed on GitHub at <https://github.com/HugoMachadoRodrigues/edaphos> and archived on Zenodo <https://doi.org/10.5281/zenodo.19683708>.

## Acknowledgements
Reference works cited throughout `vignettes/references.bib` (McBratney 2003, Pearl 2009, Wadoux 2020, Zhang & Wadoux 2026, Wooldridge 2010, Cinelli & Hazlett 2020, Havlicek 2019). No funding source reported; developed in the author's personal research time during PhD at the University of São Paulo.
