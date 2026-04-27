# Contributing to edaphos

Thanks for your interest in contributing to **edaphos** – a
research-grade R package for Digital Soil Mapping. This document
captures the conventions of the project so a contributor can submit a
useful pull request without round-tripping with the maintainer.

## Code of conduct

By participating in this project you agree to abide by the [Code of
Conduct](https://hugomachadorodrigues.github.io/edaphos/CODE_OF_CONDUCT.md).

## Quick path: I just want to file an issue

- **Bug**: open
  <https://github.com/HugoMachadoRodrigues/edaphos/issues/new?template=bug_report.md>
  and follow the template (minimal reproducible example, expected vs
  observed behaviour, R version + platform).
- **Feature request**: open
  <https://github.com/HugoMachadoRodrigues/edaphos/issues/new?template=feature_request.md>
  and motivate the feature against one of the 10 research pillars
  (`cheatsheets/pilarN.md`).
- **Security disclosure**: see
  [SECURITY.md](https://hugomachadorodrigues.github.io/edaphos/SECURITY.md)
  – do NOT file public issues.

## Quick path: I want to send a PR

1.  **Fork** the repo and create a feature branch off `main`.

2.  **Discuss first** for non-trivial changes (architectural,
    public-API-breaking). Open an issue and tag it `discussion`.

3.  **Code style**: 2-space indent, no tabs, ~80 char lines. Use the
    existing pillar’s idiom (look at any `R/pilar*` file).

4.  **Tests**: add `testthat` tests covering the new behaviour. See
    `tests/testthat/helper-torch.R` for the torch-skip pattern.

5.  **Documentation**: every exported function gets `@export`, `@param`
    for every argument, `@return`, and at least one `@examples` block.
    Run
    [`devtools::document()`](https://devtools.r-lib.org/reference/document.html)
    before committing.

6.  **Run locally** before pushing:

    ``` r
    devtools::load_all()
    devtools::test()                                            # all green
    devtools::check(args = c("--no-manual",
                             "--no-build-vignettes"))           # 0/0/0
    devtools::spell_check()                                     # ideally empty
    urlchecker::url_check()                                     # ideally empty
    ```

7.  **Commit messages**: use the [Conventional
    Commits](https://www.conventionalcommits.org/) prefixes (`feat`,
    `fix`, `perf`, `docs`, `test`, `refactor`, `chore`). Bullet-list the
    substantive changes in the body.

8.  **NEWS.md**: prepend a versioned entry under the next planned
    release.

9.  **Send PR** against `main`. CI must be green on all five matrix legs
    (Ubuntu oldrel-1 / devel / release + macOS + Windows).

## Architectural conventions

- Every “pillar” (1-10) lives in `R/pilarN_*.R`. Cross-pillar bridges
  live in `R/bridges_*.R`.
- Heavy optional dependencies (`torch`, `terra`, `geodata`, `dagitty`,
  …) go in **Suggests**, NOT Imports. Code that uses them MUST be
  wrapped in
  [`requireNamespace("foo", quietly = TRUE)`](https://rdrr.io/r/base/ns-load.html).
- Every predictive output should be wrappable as
  `as_edaphos_posterior(...)` so cross-pillar benchmarks score on the
  same scale.
- Compiled code (`src/*.cpp`) requires a corresponding
  `tests/testthat/test-*-rcpp.R` validating numerical equivalence with
  the pure-R reference.
- Vignettes follow a “methods paper” structure: abstract, derivation,
  code, results, references. See `vignettes/pilar2-piml-profile.Rmd` for
  the canonical template.

## Branch / release flow

- `main` is the integration branch. All PRs target `main`.
- `gh-pages` holds the rendered pkgdown site (auto-managed by
  `.github/workflows/pkgdown.yaml`).
- Releases follow [SemVer](https://semver.org/):
  - `MAJOR` for breaking public-API changes,
  - `MINOR` for additions (new pillars, bridges, exported functions),
  - `PATCH` for bugfixes. Every release gets a git tag (`vX.Y.Z`) and a
    NEWS.md entry.

## Reproducing the benchmarks

Heavy artefacts are under `data-raw/`. The pattern is:

data-raw/.R -\> inst/extdata/.rds

A re-run is a one-liner:

Rscript data-raw/benchmark_wosis_6pilar.R

Some scripts require a network (OpenAlex, SoilGrids, MoCo download from
Zenodo) and explicit env vars (e.g. `EDAPHOS_IV_REAL_STACK=1`,
`EDAPHOS_CORPUS_MAILTO=...`). See the script header for details.

## Asking for help

- GitHub Discussions:
  <https://github.com/HugoMachadoRodrigues/edaphos/discussions>
- Maintainer: <rodrigues.machado.hugo@gmail.com> (slow async reply
  expected; tag GitHub for faster turn-around).
