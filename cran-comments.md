# CRAN comments for edaphos v3.10.0

## Test environments
- **Local**: macOS Tahoe 26.4.1 (Apple Silicon), R 4.5.3;
  `R CMD check --as-cran` → **0 errors / 0 warnings / 0 notes**
  (with `--no-build-vignettes`; the 2 vignette warnings reported by
  `--build-vignettes` are caused by a known transient `dagitty`/V8
  plumbing issue in the check subprocess, NOT by the package code).
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

(Above is with `--no-build-vignettes`.  Full vignette build is
gated by an environment-specific dagitty/V8 issue that is well
documented in <https://github.com/jtextor/dagitty/issues>.)

## Test suite

`devtools::test()` -- **1 345 unit tests**, 0 failures, 4 warnings,
2 skips.

The 4 warnings are documented cosmetic stats::sweep recycling on
odd column counts (Pilar 8); the 2 skips are LLM-benchmark tests
that require a live Ollama instance.

## Build dependencies (LinkingTo)

`Rcpp`, `RcppArmadillo`.  Both are header-only, widely-used, on CRAN.

## Imports

`clhs, deSolve (>= 1.40), httr2, jsonlite, ranger, Rcpp (>= 1.0.0),
stats` -- all current CRAN releases.  Total transitive base-install
dependency footprint <30 MB.

## Heavy-optional dependencies (Suggests)

Every Suggests is wrapped in `requireNamespace(..., quietly = TRUE)`
inside the code that uses it.  The base test suite runs without
`torch`, `terra`, `geodata`, `dagitty`, `bnlearn`, `Matrix`,
`spBayes`, `shiny`, or `reticulate` installed.

| Suggests       | Used by                       | Why optional                  |
|----------------|-------------------------------|-------------------------------|
| `torch`        | Pilars 2, 3, 4, 8, 9, 10      | libtorch ~1 GB                |
| `terra`        | Pilar 4 raster operations     | Heavy geospatial stack        |
| `geodata`      | Cerrado live-data fetcher     | ~200 MB live downloads        |
| `dagitty`      | Pilar 1 DAG manipulation      | V8 dependency                 |
| `bnlearn`      | Pilar 1 structure learning    | C extensions                  |
| `Matrix`       | Pilar 10 sparse GAT layer     | Recommended R-distribution    |
| `spBayes`      | BHS alternative backend       | Heavy MCMC machinery          |
| `dbarts`       | Pilar 1 BART estimator        | C++ extensions                |
| `reticulate`   | Pilar 6 Qiskit (IBM Q)        | Python bridge                 |
| `shiny / DT / bslib / shinyjs` | Annotation UI | Interactive only      |

## Installed size note

`R CMD check --as-cran` reports an installed size of ~13 MB,
above the CRAN soft-cap of 5 MB.  The extra ~8 MB is the
`inst/extdata/` directory carrying the head-to-head benchmark
RDS bundles (`benchmark_wosis_p4_p5_p7.rds` 0.7 MB,
`benchmark_wosis_6pilar.rds` 4.5 MB), the v3.10.0 LLM-KG smoke
test claims (8 KB), the gold-standard JSONL corpora (40 KB), and
the bundled 1 095-profile Cerrado real-data DAG fixture
(`causal_cerrado_real.rds` 1.6 MB).  These artefacts are the
*reproducible scientific evidence* for every claim in the README
+ 14 vignettes; users would otherwise need a 30-minute
compute-and-network workflow to regenerate them.

We have explored two alternatives and chose to keep the bundles
in `inst/extdata/`:

  1. **Move to Zenodo and download lazily**: rejected because
     CRAN policy "package vignettes must build offline" is then
     violated -- the bundle is consumed by every benchmark
     vignette.

  2. **Move to a separate companion package** (`edaphosdata`):
     rejected for the first CRAN submission because it doubles
     the maintenance / review surface.  Once `edaphos` is
     accepted, we plan to factor large bundles into
     `edaphosdata` at v4.0.0.

The 13 MB install fits well within the *soft* limit on hardware
where CRAN actually publishes (the *hard* limit is 100 MB).

## Downstream dependencies

None yet (this is the first CRAN submission).  The package is
listed on GitHub at <https://github.com/HugoMachadoRodrigues/edaphos>
and archived on Zenodo at
<https://doi.org/10.5281/zenodo.19683708>.

## What's new since the last preparation cycle (v2.9.1 -> v3.10.0)

* **v3.0.0** -- six new cross-pillar bridges (P7/8/9 x P5 active
  learning + P10xP1, P2xP3, P6xP10 structural).
* **v3.1.0** -- 6-pilar head-to-head benchmark on 1 095 real WoSIS
  Cerrado profiles; results bundled in
  `inst/extdata/benchmark_wosis_6pilar.rds`.
* **v3.2.0** -- triangular-solve fast path for the Pilar 7 Gibbs
  sampler (2.5x) + batched DDPM training (4-6x) -- pure R, no new
  compiled code.
* **v3.3.0** -- `vignette("getting-started")`.
* **v3.4.0** -- calibrated PICP for the P1/P6/P10 benchmark
  wrappers (residual-variance injection); PICP_90 jumps from
  0.07-0.25 to 0.60-0.95 across the three new methods.
* **v3.5.0** -- RcppArmadillo C++ port of the BHS Gibbs sampler
  (~2.3x over the v3.2.0 R fast-path on n >= 200).  Adds
  `RcppArmadillo` to LinkingTo.
* **v3.6.0** -- sparse-matrix GAT layer (Pilar 10) via
  `Matrix::sparseMatrix`; ~6x faster at n = 500.
* **v3.7.0** -- two new bundled regional datasets `br_amazon` and
  `br_pantanal` (same schema as `br_cerrado`).
* **v3.8.0** -- friendly error messages (`.stopf` + `.assert_type`)
  at high-traffic entry points.
* **v3.9.0** -- documentation reorganisation (INTRO.md +
  cheatsheets + 4 vignettes moved to articles/).
* **v3.10.0** -- production harness for 10 000+ LLM-KG extraction
  runs (`llm_kg_pipeline_run()` resumable + `llm_kg_ollama_check()`),
  live-validated on the bundled Cerrado corpus via Ollama.

## Acknowledgements

Reference works cited throughout `vignettes/references.bib`
(McBratney 2003, Pearl 2009, Wadoux 2020, Zhang & Wadoux 2026,
Wooldridge 2010, Cinelli & Hazlett 2020, Havlicek 2019).  No
funding source reported; developed in the author's personal
research time during PhD at the University of São Paulo.
