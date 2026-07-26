<!-- GENERATED FILE -- DO NOT EDIT BY HAND.
     Regenerate:  Rscript tools/status/facts.R [--check-log=LOG]
                  Rscript tools/status/render.R                     -->

# edaphos — development status

**Commit** `7abe507` (`Hugo/edaphos-dev-status-222f14`) — **DESCRIPTION version** `3.10.0` — **measured** 2026-07-26T15:29:25Z

Every quantity in this document is measured at render time by
[`tools/status/facts.R`](tools/status/facts.R) and rendered by
[`tools/status/render.R`](tools/status/render.R). Nothing is typed by hand.
A quantity that could not be measured prints `_not measured_` rather than a
plausible-looking value. The findings register comes from
[`tools/status/findings.json`](tools/status/findings.json), the frozen output of an
adversarial audit of commit `272b378`.

## 1. Headline

| Measure | Value |
| --- | --- |
| Commits | 83 |
| First → last commit | 2026-04-20 → 2026-07-26 (96.5 calendar days, 9 with commits) |
| Days since last commit | 0 |
| NEWS release sections | 43 |
| Git tags | 18 |
| NEWS versions with no tag | 32 |
| R/ source lines | 19 750 |
| Exported functions | 169 |
| Test blocks | 461 |
| Tests passing | 1 123 |
| Tests skipped | 75 |
| Test failures + errors | 0 |
| R CMD check status | Status: 3 NOTEs |
| Shipped bytes | 14.00 MB |
| Findings open (blocker/high) | 27 |

### Stage assessment

From the audit's completeness critic (editorial, not measured):

> Late-stage prototype dressed as a release candidate — call it prototype-to-alpha, not beta and
> nowhere near release-candidate. The eight audits read the artefact as a mature project that had
> drifted; the git clock says the opposite: this is a single 8-day build (2026-04-20 → 2026-04-27, 82
> commits) that emitted 43 NEWS "releases", 19,700 lines of R, 10 "research pillars", 185 man pages,
> 14 vignettes, a Dockerfile, a Zenodo dossier and an rOpenSci submission draft, and has had no
> commit in the 90 days since. That single fact explains nearly every finding the other auditors
> reported as independent drift: metadata "9 minor versions stale", 32 untagged releases, four
> contradictory citation versions, four contradictory test counts, a README frozen at v2.8.0 and a
> homepage that still says six pillars — none of these are decay, they are the natural state of
> version labels that were minted faster than any of them could be verified, because no version was
> ever cut, installed or consumed by a third party. The structural tell is that the project's own
> roadmap agrees with me: README's terminal milestone is still `| v3.0.0 | CRAN + rOpenSci submission
> | 📝 |` — unstarted — while DESCRIPTION reads 3.10.0, so the package shipped ten minor versions
> past its own submission gate without submitting. The code itself is genuinely substantial and much
> of it works (the pkgdown site does build and deploy at HEAD, 184 reference pages, 1022 passing
> expectations), which is why this is alpha rather than a sketch; but the outer shell is
> systematically unverified. Documentation artefacts fail the cheapest possible check —
> cheatsheets/pilar4.md's entire "Core API" block calls four functions that exist nowhere in R/; the
> README's vignette table advertises four vignettes that are not in the tarball or on the site while
> omitting `getting-started`, whose name appears nowhere in the 84 KB README; pillars 8-10 cite their
> source papers only in `#` comments and have no bibliography entries at all; and the two
> deep-learning pillars render as empty stubs on the live public site. A beta means the outside of
> the box has been checked once against the inside; here it demonstrably never has.

**Strongest single piece of evidence:**

> `git log --reverse --format="%ci %s" | head -1` → `2026-04-20 23:44:43 Initial release of edaphos
> 0.1.0`, and `git log -1` → `2026-04-27 17:49:50` (272b378) — the whole package, from 0.1.0 to
> 3.10.0, is 82 commits spanning 8 calendar days (1/10/10/22/15/7/9/8 per day), carrying 43 `^#
> edaphos` sections in NEWS.md: 5.4 "releases" and ~2,460 lines of R per day, with tags contiguous
> only through v1.6.0 and then a single v3.10.0. Zero commits in the 90 days since. The version
> number is not a release history; it is a labelling convention applied inside one continuous build
> sprint — which is why README's own roadmap still shows `| v3.0.0 | CRAN + rOpenSci submission | 📝
> |` as not started while DESCRIPTION says 3.10.0.

## 2. Measurement provenance

| Field | Value |
| --- | --- |
| R version | 4.6.1 (Happy Hop) |
| Platform | aarch64-apple-darwin23 |
| OS | Darwin 25.5.0 |
| Worktree clean | no |
| Local vs origin/main | `0 / 0` (ahead / behind) |
| Optional deps missing | 10 |

Suggests **not installed** in the measuring environment: `DiagrammeR`, `ecmwfr`, `fmsb`, `geobr`, `geodata`, `ggdag`, `ggridges`, `ontologyIndex`, `spBayes`, `torch`.
Every test and vignette gated on these is skipped, so the pass counts below
are a floor, not a total.

## 3. The git clock

`7abe507` — 83 commits across 9 active days.

| Date | Commits |
| --- | --: |
| 2026-04-20 | 1 |
| 2026-04-21 | 10 |
| 2026-04-22 | 10 |
| 2026-04-23 | 22 |
| 2026-04-24 | 15 |
| 2026-04-25 | 7 |
| 2026-04-26 | 9 |
| 2026-04-27 | 8 |
| 2026-07-26 | 1 |

Releases declared in `NEWS.md`: **43**. Git tags: **18**.
Tags present: `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.4.0`, `v0.5.0`, `v0.6.0`, `v0.7.0`, `v0.8.0`, `v0.9.0`, `v1.0.0`, `v1.1.0`, `v1.2.0`, `v1.3.0`, `v1.3.1`, `v1.4.0`, `v1.5.0`, `v1.6.0`, `v3.10.0`.
Commits since the newest tag (`v3.10.0`): **17**.

`NEWS.md` versions with **no git tag** (32): `3.9.0`, `3.8.0`, `3.7.0`, `3.6.0`, `3.5.0`, `3.4.0`, `3.3.0`, `3.2.0`, `3.1.0`, `3.0.0`, `2.9.1`, `2.9.0`, `2.8.0`, `2.7.0`, `2.6.0`, `2.5.0`, `2.4.0`, `2.3.0`, `2.2.1`, `2.2.0`, `2.1.3`, `2.1.0`, `2.0.0`, `1.9.2`, `1.9.1`, `1.9.0`, `1.8.2`, `1.8.1`, `1.8.0`, `1.7.2`, `1.7.1`, `1.7.0`.

## 4. Version coherence

| Check | Result |
| --- | --- |
| DESCRIPTION version equals newest NEWS section | ✅ (DESCRIPTION `3.10.0`, NEWS `3.10.0`) |
| DESCRIPTION version has a git tag | ✅ (`v3.10.0`) |
| HEAD is the tagged release commit | ❌ (17 commits past `v3.10.0`) |
| Every NEWS release is tagged | ❌ (32 of 43 untagged) |

Version strings each artefact claims for the package:

| Artefact | Claims |
| --- | --- |
| DESCRIPTION | `3.10.0` |
| NEWS.md | `3.10.0` |
| README.md | `2.8.0` |
| CITATION.cff | `2.1.0`, `1.6.0` |
| .zenodo.json | **no version field at all** |

Version strings asserted inside shipped `R/` or `man/` that **neither a `NEWS.md` section nor a git tag declares** (7): `2.1.1`, `3.11.0`, `1.3.2`, `2.3.1`, `2.4.1`, `2.5.1`, `2.1.2`. Each names a release that never existed.

| File | Line | Version |
| --- | --: | --- |
| `R/bridges_active_learning_v3.R` | 12 | `2.1.1` |
| `R/causal_active_learning.R` | 1 | `2.1.1` |
| `R/foundation_embed_coords.R` | 186 | `3.11.0` |
| `R/foundation_embed_coords.R` | 204 | `3.11.0` |
| `R/foundation_embed_coords.R` | 220 | `3.11.0` |
| `R/foundation_weights.R` | 55 | `1.3.2` |
| `R/foundation_weights.R` | 82 | `1.2.0,3.11.0` |
| `R/pilar7_bayesian_hierarchical.R` | 44 | `2.3.1` |
| `R/pilar8_neural_operators.R` | 28 | `2.4.1` |
| `R/pilar8_neural_operators.R` | 216 | `2.4.1` |
| `R/pilar9_diffusion_models.R` | 77 | `2.5.1` |
| `R/temporal_active_learning.R` | 2 | `2.1.2` |
| `man/foundation_build_cerrado_stack.Rd` | 31 | `3.11.0` |
| `man/foundation_build_cerrado_stack.Rd` | 39 | `3.11.0` |
| `man/foundation_build_cerrado_stack.Rd` | 58 | `3.11.0` |

Conversely, git tags with **no `NEWS.md` section**: `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.4.0`, `v0.5.0`, `v0.6.0`, `v0.7.0`.

Git refs the README tells users to install:

| Ref | Resolves |
| --- | --- |
| `v2.8.0` | ❌ |

## 5. `R CMD build` / `R CMD check --as-cran`

| Result | Value |
| --- | --- |
| Status | Status: 3 NOTEs |
| ERRORs | 0 |
| WARNINGs | 0 |
| NOTEs | 3 |

Counts are taken from R's own `Status:` line; an independent walk of the log agrees.

**NOTES:**

- `checking CRAN incoming feasibility`
- `checking HTML version of manual`
- `checking for detritus in the temp directory`

**INFOS:**

- `checking package dependencies`
- `checking installed package size`

#### `checking CRAN incoming feasibility`

| Field | Value |
| --- | --- |
| Maintainer | `Hugo Rodrigues <rodrigues.machado.hugo@gmail.com>` |
| CRAN status | **New submission** — R's own confirmation that nothing named `edaphos` exists on CRAN |
| Tarball size | 15.02 MB (CRAN guidance: 5.00 MB) |
| URLs flagged as invalid | 0 |

Suggests unavailable to the check (so their tests and vignette chunks were skipped): 'DiagrammeR', 'ecmwfr', 'fmsb', 'geobr', 'geodata', 'ggdag', 'ggridges', 'ontologyIndex', 'spBayes', 'torch'.

Installed size, verbatim from the log:

```
  installed size is 18.5Mb
  sub-directories of 1Mb or more:
    doc       4.7Mb
    extdata   9.6Mb
    help      2.9Mb
```

Log: `/Users/rodrigues.h/Library/CloudStorage/OneDrive-Personal/edaphos/.claude/worktrees/edaphos-dev-status-222f14/tools/status/check.log` (124 lines, sha256 `fbfd37b75cfad09e`). Verbatim tail:

```
 [49s/31s] OK
* checking for unstated dependencies in vignettes ... OK
* checking package vignettes ... OK
* checking re-building of vignette outputs ... [50s/37s] OK
* checking PDF version of manual ... OK
* checking HTML version of manual ... NOTE
Skipping checking HTML validation: 'tidy' doesn't look like recent enough HTML Tidy.
Please obtain a recent version of HTML Tidy by downloading a binary
release or compiling the source code from <https://www.html-tidy.org/>.
* checking for non-standard things in the check directory ... OK
* checking for detritus in the temp directory ... NOTE
Found the following files/directories:
  tmpspsyky6e
* DONE
Status: 3 NOTEs
See
  <CHECKDIR>/check4/edaphos.Rcheck/00check.log
for details.
```

#### Each reported item: package defect or measuring environment?

Item names and levels come from the log above; the classification and
source attribution are editorial and live in [`tools/status/check-classification.json`](tools/status/check-classification.json).

| Item | Level | Class | Blocks CRAN | Source |
| --- | --- | --- | --- | --- |
| `checking CRAN incoming feasibility` | NOTE | environment | no | README.md (https://hugomachadorodrigues.github.io/edaphos needs a trailing slash) and inst/doc/case-cerrado-end-to-end.html (https://github.com/ipeaGIT/geobr moved to https://github.com/ipea/geobr). Tarball is 15734027 bytes. |
| `checking tests` | ERROR | **defect** | yes | tests/testthat/test-foundation-weights.R:33 and tests/testthat/test-active-quantum-posterior.R:34 |
| `checking PDF version of manual` | WARNING | **defect** | yes | R/foundation_finetune.R:165 (U+2265 GREATER-THAN OR EQUAL) and R/foundation_finetune.R:436 (U+2208 ELEMENT OF); man/*.Rd is roxygen-generated so the fix must land in R/ and be re-documented. |
| `checking PDF version of manual without index` | ERROR | **defect** | yes | R/foundation_finetune.R:165,436 |
| `checking Rd files` | NOTE | **defect** | no | R/foundation_embed_coords.R:207 |
| `checking installed package size` | INFO | **defect** | no | inst/extdata (result bundles) and man/figures/logo.png |
| `checking for hidden files and directories` | NOTE | **defect** | no | .Rbuildignore |
| `checking top-level files` | NOTE | environment | no | removed from the worktree before the clean baseline run |
| `checking HTML version of manual` | NOTE | environment | no | measuring machine |
| `checking for non-standard things in the check directory` | NOTE | environment | no | consequence of the PDF-manual failure above |
| `checking for detritus in the temp directory` | NOTE | **defect** | no | Not the LaTeX run, as first assumed: the NOTE persists after the PDF manual builds cleanly. The directory is named tmp<8 chars> and differs on every run (tmph7u64pdz, tmpl_pg5ehe, tmpspsyky6e), which is Python's tempfile.mkdtemp() pattern, not R's file<hex>. It comes from the optional qiskit / PySCF bridge reached through reticulate in R/quantum_vqe.R, R/quantum_nature.R and R/quantum_ibmq.R. |
| `R CMD build (vignettes)` | ERROR | **defect** | no | vignettes/pilar1-causal.Rmd:58-65 |
| `checking package dependencies` | INFO | environment | no | measuring machine; see the Test environments section |

Of 13 reported items, **8 are package defects** and 4 are artefacts of this measuring environment. 3 block CRAN acceptance.

Fixes, per item:

- `checking CRAN incoming feasibility` — Nothing to fix: 'New submission' is accurate. Recorded because it is R's own confirmation that nothing named edaphos exists on CRAN, which contradicts every artefact implying the package is released.
- `checking tests` — See findings FC68E1D (move .moco_require_torch below the argument validation in R/foundation_weights.R) and FAEC54C (validate num.trees in R/active_fit.R, seed the test).
- `checking PDF version of manual` — Replace with \eqn{\ge} / \eqn{\in} or ASCII, then roxygen2::roxygenise(). The 165 em-dashes and 18 en-dashes in Rd are safe -- R's Rd-to-LaTeX pass maps them.
- `checking PDF version of manual without index` — Resolved by the same change.
- `checking Rd files` — Use \eqn{\sim} or the word 'about'.
- `checking installed package size` — See finding FDE7C43. The single cheapest win is re-encoding man/figures/logo.png.
- `checking for hidden files and directories` — Add ^\.git$. Note this surfaces here because the build ran from a git worktree, where .git is a plain file rather than a directory; adding the pattern makes the build correct from either layout.
- `checking top-level files` — None. Absent from the clean baseline.
- `checking HTML version of manual` — None needed in the package.
- `checking for non-standard things in the check directory` — Disappears once the Unicode fix lands.
- `checking for detritus in the temp directory` — Have the Python bridge clean up the directories it creates (or create them under tempdir() and remove them on.exit). Only appears on machines where the optional Python stack is installed, so it would not fire on CRAN, where reticulate-gated tests skip.
- `R CMD build (vignettes)` — Guard the chunk with requireNamespace('dagitty') (the pattern the R/ code already uses via .causal_require_dagitty), or set eval=FALSE with a precomputed result, as the other heavy vignettes do.
- `checking package dependencies` — None needed in the package. CRAN installs Suggests, so this INFO does not appear there.

> **checking CRAN incoming feasibility**: 'New submission' is R's own confirmation that nothing named edaphos exists on CRAN, at version 3.10.0 with 43 NEWS releases behind it.

> **R CMD build (vignettes)**: CRAN installs Suggests, so this would not block CRAN itself -- but it does block every contributor and any reproduction attempt on a lean machine, and it falsifies the offline claim.

### Rd portability (the source of the PDF-manual check items)

`man/*.Rd` files containing characters outside latin1: **58** of 182. Most are cosmetic — R's Rd-to-LaTeX pass maps dashes and ellipses. Distinct characters found:

| Character | Codepoint | Occurrences | Breaks LaTeX |
| --- | --- | --: | :-: |
| <U+2014> | `U+2014` | 165 | ❌ |
| <U+2013> | `U+2013` | 18 | ❌ |
| <U+2026> | `U+2026` | 1 | ❌ |

## 6. Test suite

| Measure | Value |
| --- | --- |
| Test files | 68 |
| `test_that` blocks | 461 |
| `expect_*` calls | 1 088 |
| `skip_if_not_installed` gates | 74 |
| `skip_on_cran` gates | 1 |
| `set.seed` calls | 114 |

Live run in this environment:

| Outcome | Count |
| --- | --- |
| Passed | 1 123 |
| Skipped | 75 |
| Failed | 0 |
| Errored | 0 |
| Warnings | 2 |
| Wall clock (s) | 29.8 |

Conditional skipping by dependency (static gate count):

| Dependency | Gate sites | Installed here |
| --- | --: | :-: |
| torch | 16 | ❌ |
| igraph | 11 | ✅ |
| dagitty | 8 | ✅ |
| terra | 5 | ✅ |
| bnlearn | 4 | ✅ |
| reticulate | 2 | ✅ |
| dbarts | 1 | ✅ |

Result bundles in `inst/extdata/`: **13**. Test files that read `inst/extdata`: `test-llm-annotation.R`.

Exported functions never named in any test (**12**): `causal_ontology_agrovoc`, `causal_ontology_envo`, `edaphos_zenodo_release`, `foundation_build_cerrado_stack`, `foundation_tile_source_era5`, `foundation_tile_source_modis`, `foundation_tile_source_soilgrids`, `foundation_tile_source_srtm`, `foundation_tile_source_worldclim`, `llm_annotation_launch`, `piml_neural_ode_predict`, `temporal_convlstm_predict`.

## 7. Documentation coverage

| Measure | Value |
| --- | --- |
| `man/*.Rd` files | 182 |
| Rd with `\examples` | 36 |
| — wrapping `\dontrun` | 18 |
| — wrapping `\donttest` | 8 |
| — with an example `R CMD check` runs | 10 |
| Exports with no example anywhere | 134 |
| Exports with no `.Rd` | 0 |
| Rd with `\references` | 25 |
| Vignettes | 14 |
| Root `articles/` | 4 |
| Cheatsheets | 11 |
| README size | 83 KB |

"six pillars" vs "ten pillars", counted per file:

| File | says "six" | says "ten" |
| --- | --: | --: |
| DESCRIPTION | 0 | 1 |
| R/pillars_roadmap.R | 1 | 0 |
| R/edaphos-package.R | 2 | 0 |
| README.md | 11 | 0 |

Occurrences of `getting-started` in README.md: **0**.

Function names called in `pilar1.md`, `pilar10.md`, `pilar2.md`, `pilar3.md`, `pilar4.md`, `pilar5.md`, `pilar6.md`, `pilar7.md`, `pilar8.md`, `pilar9.md`, `README.md`, `INTRO.md` that are **defined nowhere** in `R/` (**9** of 43 referenced): `al_batchbald`, `foundation_finetune`, `foundation_moco_fit`, `foundation_simclr_fit`, `foundation_tile_raster`, `gnn_gat_layer`, `piml_default_prior`, `temporal_convlstm_forecast`, `temporal_cube_build`.

## 8. Install size

| Directory | Size | Ships in tarball |
| --- | --: | :-: |
| `inst` | 9.57 MB | ✅ |
| `man` | 2.58 MB | ✅ |
| `R` | 791 KB | ✅ |
| `tools` | 618 KB | ❌ |
| `<root>` | 463 KB | ✅ |
| `tests` | 300 KB | ✅ |
| `data-raw` | 289 KB | ❌ |
| `vignettes` | 264 KB | ✅ |
| `data` | 64 KB | ✅ |
| `articles` | 42 KB | ❌ |
| `cheatsheets` | 16 KB | ❌ |
| `src` | 15 KB | ✅ |
| `.github` | 8 KB | ❌ |

Total shipped: **14.00 MB** against the CRAN 5 MB soft cap (5.00 MB) — **over, so an installed-size NOTE is unavoidable**.

Largest shipped files:

| File | Size |
| --- | --: |
| `inst/extdata/benchmark_wosis_6pilar.rds` | 4.43 MB |
| `inst/extdata/benchmark_wosis_p4_p5_p7.rds` | 1.87 MB |
| `man/figures/logo.png` | 1.83 MB |
| `inst/extdata/case_cerrado_results.rds` | 1.40 MB |
| `inst/extdata/capstone_native_calibration.rds` | 741 KB |
| `inst/extdata/capstone_campaign_results.rds` | 543 KB |
| `tools/status/findings.json` | 439 KB |
| `STATUS.md` | 227 KB |
| `inst/extdata/temporal_cerrado_results.rds` | 194 KB |
| `inst/extdata/causal_sensitivity_cerrado.rds` | 142 KB |

## 9. CI and infrastructure

Workflows (3): `pkgdown.yaml`, `R-CMD-check.yaml`, `test-coverage.yaml`.

`R-CMD-check` matrix legs:

- `- {os: macos-latest,   r: 'release'}`
- `- {os: windows-latest, r: 'release'}`
- `- {os: ubuntu-latest,  r: 'devel',   http-user-agent: 'release'}`
- `- {os: ubuntu-latest,  r: 'release'}`
- `- {os: ubuntu-latest,  r: 'oldrel-1'}`

`TORCH_INSTALL` setting found in the workflows: `TORCH_INSTALL: 0` — with `0`, libtorch is never installed, so every torch-gated test skips on every leg.

| Check | Result |
| --- | --- |
| Dependabot config | no |
| `inst/WORDLIST` has a consumer | no |
| Absent workflows a project at this stage wants | `lint`, `spelling`, `urlcheck`, `release`, `revdep`, `dependabot` |

## 10. Shipped artefacts vs published claims

Loaded from `inst/extdata/` at render time. These are the values the package
actually ships, independent of what the README says about them.

### `causal_iv_cerrado_real.rds`

| Field | Value |
| --- | --- |
| Bundle version | `3.10.0` |
| Computed | 2026-04-27 12:02:24 |
| Used real stack | yes |
| Stack layers | 31 |
| Resolution (deg) | 0.05 |
| Profiles | 1 081 |

Health of the stored embedding sample (measured, not characterised):

| Statistic | Value |
| --- | --: |
| Values stored | 30 |
| Exactly zero | 16 |
| Share exactly zero | 53% |
| Min | 0 |
| Max | 466 |
| SD | 193 |

A healthy standardised embedding contains no exact zeros. A large share of exact zeros indicates channels that were never populated, or normalisation statistics left at their placeholder values.

Estimates as shipped, all rows:

| Exposure | Estimator | beta | Stage-1 F | Sargan p |
| --- | --- | --: | --: | --: |
| MAP (mm/a) | Backdoor OLS | 0.007777 |  |  |
| MAP (mm/a) | 2SLS (real MoCo v1) | 0.007566 | 1495.000 | 3.22e-08 |
| Tree cover (%) | Backdoor OLS | 7.200000 |  |  |
| Tree cover (%) | 2SLS (real MoCo v1) | 56.710000 | 14.800 | 7.47e-04 |
| Clay (%) | Backdoor OLS | 0.194900 |  |  |
| Clay (%) | 2SLS (real MoCo v1) | -4.464000 | 2.686 | 8.86e-02 |

What `README.md` publishes at the same place, verbatim:

```
| Exposure | v1.9.0 Sargan p (proxy) | **v1.9.1 Sargan p (real MoCo)** |
|:---|---:|---:|
| MAP <e2><86><92> SOC | < 10<e2><81><bb><c2><b9><c2><b2> <e2><9d><8c> | **0.343** <e2><9c><85> |
| Tree cover <e2><86><92> SOC | < 10<e2><81><bb><e2><81><b9> <e2><9d><8c> | **0.283** <e2><9c><85> |
| Clay <e2><86><92> SOC | < 10<e2><81><bb><c2><b9><c2><b2> <e2><9d><8c> | **0.424** <e2><9c><85> |
```

### `llm_benchmark_results.rds`

`mode = "simulated"`, bundle version `1.7.2`, computed 2026-04-23 16:52:56. **No API was called; the published vendor comparison reports its own simulator inputs.**

### `quantum_foundation_cerrado.rds`

| method | rmse_mean | rmse_sd | mae_mean | r2_mean | n_folds |
| --- | --- | --- | --- | --- | --- |
| Quantum KRR on foundation PCs | 14.29 | 5.900 | 8.728 | 0.00000 | 5 |
| Quantum KRR on raw covariates | 14.18 | 5.907 | 8.447 | 0.00000 | 5 |
| RBF-KRR on foundation PCs | 14.76 | 4.600 | 9.765 | 0.00000 | 5 |
| ranger (raw covariates) | 14.34 | 4.039 | 8.972 | 0.08066 | 5 |

Methods reporting R² of exactly zero: **3** — a consequence of the clamp sites below.

R² clamped with `max(0, 1 - ...)` at: `R/quantum_foundation.R:279`, `data-raw/benchmark_wosis_6pilar.R:157`, `data-raw/benchmark_wosis_p4_p5_p7.R:244`.

Benchmark covariate rasters filled with `rnorm()` at: `data-raw/benchmark_wosis_p4_p5_p7.R:166`, `data-raw/benchmark_wosis_p4_p5_p7.R:169`, `data-raw/causal_iv_benchmark_real.R:127`, `data-raw/quantum_foundation_benchmark.R:53`.

## 11. Findings register

123 findings from the audit of `272b378`, each passed through an adversarial verification lens.
Severity below is the **verified** severity, which may differ from what the
original auditor reported.

| Verdict | Count |
| --- | --: |
| CONFIRMED | 78 |
| PARTIALLY_TRUE | 29 |
| REFUTED | 2 |
| UNVERIFIABLE | 0 |
| NOT_VERIFIED | 14 |

| Severity | Freq |
| --- | --: |
| blocker | 4 |
| high | 23 |
| medium | 56 |
| low | 39 |
| non-issue | 1 |

### Refuted by verification (retained for the record, excluded from the plan)

- **F363935** — pkgdown reference index selects on `has_concept("pilar1")` but no Rd file has a `\concept{}` tag
  - Why it does not hold: The premise checks out (\_pkgdown.yml:123 `- has_concept("pilar1")`; 0 of 182 man/*.Rd contain `\concept{`; 0 `@concept`/`@family` in R/) but the conclusion is false. I read the installed pkgdown: `section_topics()` calls `select_topics(match_strings, topics, error_pkg=, error_path=, error_call=)` WITHOUT `check = TRUE`, and `select_topics` only aborts when `check` is TRUE; it aborts on an all-empty section (`purrr::every(indexes, is_empty)`) and otherwise runs `indexes <- purrr::discard(indexes, is_empty)`. The Pilar-1 section also has `starts_with("causal_")` etc., which match, so the zero-match selector is silently dropped. No abort. Sub-claim 2 is also refuted: man/edaphos-package.Rd carries `\keyword{internal}` at line 189, and `check_missing_topics()` computes `missing <- !in_index & !pkg$topics$internal`, so it is exempt from the index requirement (edaphos-roadmap.Rd is internal too). I simulated the full reference index against all 182 topics: ZERO non-internal topics are unmatched, so `check_missing_topics()` will not fire either. What survives is minor: a dead selector, `news: releases:` stale at v2.0.0 (cosmetic navbar list), and articles/ being unrendered — which inst/rosc/submission.md:82-84 itself discloses as "`.Rbuildignore`-d to keep the vignette build fast". `pkgdown::build_site_github_pages()` is not blocked.

- **F0EEC2D** — .batchbald_aleatoric_var() silently falls back to in-sample random-forest residuals whenever any OOB prediction is NA
  - Why it does not hold: The code reads exactly as quoted (R/active_batchbald.R:67-77) and the silent two-branch design is real, but the fallback is unreachable for any model `al_fit()` can produce, so the impact does not exist. `al_fit` -> `.fit_core` always calls `ranger::ranger(..., quantreg = TRUE, keep.inbag = TRUE)`, and ranger itself enforces `minoob <- min(rowSums(inbag.counts == 0)); if (minoob < 10) stop("Error: Too few trees for out-of-bag quantile regression.")` — I read this in the installed ranger 0.18.0 source. That guarantees every observation has >= 10 OOB trees, hence zero NAs in `rg$predictions`, hence `length(na.omit(oob)) == length(y_train)` always holds and the OOB branch always wins. Verified empirically on ranger 0.18.0: n = 40 with num.trees = 50 and 500 both give length-40 predictions with 0 NAs. The claimed trigger regime ("small-n / small-num.trees") is precisely the regime where ranger refuses to fit at all rather than emitting NA OOB predictions — the two failure modes are mutually exclusive, not co-located.

### All open findings

| ID | Sev | Verdict | Area | Kind | Effort | Finding |
| --- | --- | --- | --- | --- | --- | --- |
| F0BC16C | blocker | confirmed | CI & infra | inconsistency | hours | "CI green" and "0 errors \| 0 warnings \| 0 notes" are asserted in release docs while a dependency-independent test error would redden all 5 matrix legs |
| FF20A54 | blocker | partial | Release consistency | incomplete-implementation | hours | "R CMD check: 0 errors / 0 notes" is false: two test errors reproduce in this tree, and one of them fires specifically in the torch-less CRAN environment that cran-comments.md swears is clean |
| F2A0EC5 | blocker | confirmed | Scientific reproducibility | inconsistency | days | Shipped IV bundle refutes the README's "decisive test passes" headline: Sargan p = 3.2e-08, not 0.343 |
| F862881 | blocker | confirmed | Scientific reproducibility | inconsistency | hours | Every β in the README's real-data causal table disagrees with the shipped bundle, and the confounding correction has the wrong sign for tree cover |
| FE42047 | high | confirmed | CI & infra | bug | hours | pkgdown workflow cannot succeed: `has_concept("pilar1")` matches zero topics and 4 navbar links point at pages never built |
| FAC0043 | high | confirmed | Code quality | bug | minutes | foundation_weights_load() gates on torch before validating its own arguments — the live ERROR 2 |
| F52C0B8 | high | partial | CRAN readiness | inconsistency | hours | cran-comments.md is self-contradictory and every quantitative claim in it is stale or wrong |
| FA81F77 | high | confirmed | CRAN readiness | bug | minutes | Undeclared `utils` and `tools` namespaces — guaranteed R CMD check WARNING that cran-comments.md denies |
| FCBA23B | high | confirmed | CRAN readiness | missing-work | days | 134 of 169 exported functions have no examples; only 10 have an example R CMD check executes |
| FDE7C43 | high | confirmed | CRAN readiness | tech-debt | hours | Installed size will NOTE: inst/extdata 9.98 MB + man/figures 2.3 MB, of which a 1.9 MB PNG logo |
| F36D2FE | high | confirmed | Release consistency | process-gap | hours | The "v3.11.0" work is committed and self-referenced in shipped code, but no version exists: no DESCRIPTION bump, no NEWS section, no tag |
| F5EF8F6 | high | confirmed | Release consistency | inconsistency | hours | Four mutually exclusive citation versions: DESCRIPTION 3.10.0, README 2.8.0, CITATION.cff 2.1.0, CITATION.cff preferred-citation 1.6.0 |
| F5F7D9A | high | confirmed | Release consistency | doc-gap | hours | The "1 345 tests" figure is unreproducible, mis-attributed, and the NEWS test-count chain contains two arithmetic breaks |
| F7DC6A4 | high | confirmed | Release consistency | bug | minutes | The README's only install command pins a git ref that does not exist (`@v2.8.0`) |
| FA01BFB | high | confirmed | Release consistency | bug | minutes | CITATION.cff assigns the identical DOI 10.5281/zenodo.19710162 to twelve different "Version DOI" entries |
| FBAF1FD | high | confirmed | Roadmap promises | doc-gap | days | DESCRIPTION promises ten research pillars; every document shipped in the CRAN tarball documents six, and pillars 7-10 have no roadmap row, no README section and no vignette |
| F1CD43E | high | confirmed | Scientific reproducibility | bug | hours | R² is floored at zero in three benchmark code paths, censoring negative values and turning them into a "statistically indistinguishable" conclusion |
| F30D53B | high | confirmed | Scientific reproducibility | bug | hours | The v1.8.0 multi-backend LLM benchmark is entirely simulated and its headline F1/latency values are hard-coded function arguments |
| F485937 | high | partial | Scientific reproducibility | process-gap | days | No test validates any headline number or any of the twelve committed result bundles |
| F623876 | high | confirmed | Scientific reproducibility | bug | days | `.bench_inject_aleatoric()` manufactures the published PICP with author-chosen noise and silently degrades the published RMSE |
| FF375C1 | high | confirmed | Scientific reproducibility | bug | days | The P4 "Foundation" row of the headline "first honest cross-pillar comparison" is computed on a pure Gaussian-noise raster |
| F10D9DC | high | confirmed | Incomplete implementations | incomplete-implementation | minutes | edaphos-cerrado-moco-v2 ships as an all-NA placeholder row in the exported public registry, keyed to a nonexistent package version 3.11.0 |
| F873468 | high | confirmed | Incomplete implementations | bug | hours | foundation_build_cerrado_stack() silently writes a truncated stack to the cache when any geodata fetch fails, then reuses it forever |
| F9E2C74 | high | confirmed | Incomplete implementations | inconsistency | minutes | qf_krr_benchmark() clamps R-squared at zero, contradicting the package's own edaphos_r2() and hiding worse-than-mean quantum models |
| F60AE85 | high | partial | Test coverage | bug | hours | bhs_fit has no rank check on the model matrix: a constant covariate yields NA rgamma rates (the 2 live WARNINGs) then a cryptic Cholesky death |
| F64B0F0 | high | confirmed | Test coverage | bug | minutes | R/foundation_finetune.R:41 makes the whole Pillar-4 fine-tuning API require `reticulate`, which it never uses |
| F8EC452 | high | partial | Test coverage | process-gap | hours | No CI leg has ever executed the torch code paths: 74 test blocks / 223 expectations / ~3,140 LOC unexercised |
| F29E750 | medium | confirmed | CI & infra | doc-gap | hours | Two competing release checklists contradict each other and describe a deploy action the pkgdown workflow does not use; referenced artefacts do not exist |
| F3D7BED | medium | partial | CI & infra | process-gap | days | 33 of 43 NEWS.md releases have no git tag and there is no release-automation workflow, contradicting CONTRIBUTING's tagging promise |
| F5E91CE | medium | partial | CI & infra | tech-debt | days | Dockerfile is not a reproducibility artefact: builds from GitHub main, unpinned libtorch, R 4.4.1 in no CI leg, v2.1.0 metadata, missing Suggests |
| F6F101E | medium | partial | CI & infra | process-gap | hours | CI builds vignettes, but 3 of 14 self-truncate to a one-line stub without libtorch -- and CONTRIBUTING tells contributors to skip vignette building entirely |
| F9C6DD9 | medium | confirmed | CI & infra | inconsistency | hours | Distribution metadata is 9 minor versions stale: CITATION.cff says 2.1.0, README says 2.8.0, .zenodo.json has no version at all |
| FD3C0C1 | medium | confirmed | CI & infra | bug | minutes | Chunk option in pilar4-simclr vignette calls `reticulate::` unguarded with broken `&&`/`\|\|` precedence -- hard error in exactly the Docker configuration |
| FD941E5 | medium | confirmed | CI & infra | inconsistency | hours | cran-comments.md test-suite and install-size figures are contradicted by the tree they describe |
| FDC9573 | medium | confirmed | CI & infra | process-gap | hours | No CI leg ever installs libtorch: 25% of R/ and 70 of 460 test blocks are unreachable in all three workflows |
| F0E4DC1 | medium | partial | Code quality | incomplete-implementation | hours | Pillars 8/9/10 default backend="r" never trains the architecture it is named after, while DESCRIPTION/README mark them "implemented" |
| F215985 | medium | confirmed | Code quality | bug | minutes | Off-by-one in the RcppArmadillo BHS backend biases w_post_mean, silently corrupting every predict.edaphos_bhs() for backend="rcpp" |
| F3E0E05 | medium | confirmed | Code quality | inconsistency | hours | gnn_embed() returns a different column count per backend and its documented @return is wrong for backend="torch" |
| F4ED689 | medium | confirmed | Code quality | bug | hours | Rank-deficient design matrix poisons the entire BHS Gibbs chain to NA on iteration 1, then hard-errors — and the test's own comment about it is wrong |
| F7EC076 | medium | confirmed | Code quality | tech-debt | hours | Twelve copies of skip_if_no_torch() in three divergent flavours, orphaning the helper-torch.R that was added to replace them |
| FBDE0E9 | medium | partial | Code quality | bug | minutes | al_fit(num.trees=) has no lower bound against ranger's undocumented OOB-quantile minimum, and the test that breaks is unseeded — a ~25% flaky ERROR |
| FC841F7 | medium | confirmed | Code quality | bug | minutes | Same loop-invariant matrix product recomputed n_draws times, copy-pasted into two files |
| FCF64DC | medium | confirmed | Code quality | inconsistency | days | Naming schism: pilar/pillar, ordinal/domain module names, al_* vs active_*, and five undocumented cryptic export prefixes |
| FD27999 | medium | confirmed | Code quality | missing-work | days | Twelve exported functions are never referenced anywhere in tests/, including the entire advertised tile-source pipeline |
| F00A9C3 | medium | confirmed | CRAN readiness | bug | minutes | `Depends: R (>= 3.5)` is falsified by two features requiring R 4.0.0 and R 3.6.0 |
| F4484D7 | medium | partial | CRAN readiness | inconsistency | days | 5 of 14 vignettes are written in Portuguese while DESCRIPTION declares `Language: en-US` |
| F4BEBBD | medium | confirmed | CRAN readiness | process-gap | hours | DESCRIPTION Title/Description violate CRAN style: marketing adjectives, unquoted software names, zero method references |
| F4EC093 | medium | confirmed | CRAN readiness | incomplete-implementation | minutes | `src/Makevars.win` documents a Unix `src/Makevars` that does not exist |
| F83F26A | medium | confirmed | CRAN readiness | inconsistency | hours | RELEASE-CHECKLIST-v3.10.0.md instructs the maintainer to upload two artefacts that do not exist, and asserts a green state contradicted by the live test run |
| F00AF5C | medium | confirmed | Release consistency | tech-debt | hours | Two overlapping release checklists disagree with each other and both claim to be the authoritative list of remaining steps |
| F545DD7 | medium | confirmed | Release consistency | inconsistency | days | The "ten pillars" identity exists only in the unreleased HEAD; every other metadata artefact still says six |
| FB9DA9E | medium | confirmed | Release consistency | doc-gap | days | The 84 KB README documents nothing after v2.8.0; its only 3.x reference is the version badge |
| FBB414A | medium | confirmed | Release consistency | missing-work | hours | .zenodo.json carries no version field at all and its description is frozen at v1.8.0 |
| FC9610C | medium | partial | Release consistency | missing-work | hours | The only DOI badge is a concept DOI the repo itself says resolves to v0.2.0, and nothing after v1.5.0 was ever deposited |
| FF84B54 | medium | confirmed | Release consistency | inconsistency | hours | Two parallel version schemes collide inside a single README table: "v1.x roadmap lines" are interleaved with package 3.x versions, and v3.0.0 means two different things |
| F1E1D2B | medium | confirmed | Roadmap promises | doc-gap | hours | Archival metadata (.zenodo.json, CITATION.cff) still describes a six-pillar package that stops at v1.8.0 |
| F2E57CE | medium | confirmed | Roadmap promises | bug | minutes | Step 4 of the v1.3.2 hand-off (wire_up_v2_doi.R) matches nothing and silently writes the timestamp into the `url` field |
| F492008 | medium | confirmed | Roadmap promises | bug | hours | Four pkgdown navbar links point at articles pkgdown never builds, and man/edaphos-package.Rd tells users to open a vignette that is not in the package |
| FD3DBCB | medium | confirmed | Roadmap promises | process-gap | hours | Two competing release checklists, one stale, pointing at a tarball path that does not exist |
| FD528FC | medium | confirmed | Roadmap promises | incomplete-implementation | days | Three exported functions with .Rd pages and pkgdown entries are permanent stop() stubs |
| FF7221D | medium | partial | Roadmap promises | missing-work | hours | v1.3.2 (MoCo v2 200k-step encoder) is 43 % short of target and the checkpoint exists nowhere in the repository |
| F0F5D47 | medium | confirmed | Scientific reproducibility | inconsistency | hours | Pretrained-weight DOI is real but the v2 registry row is all-NA while claiming a nonexistent version; CITATION.cff and .zenodo.json are many releases stale and assign one DOI to ten releases |
| F2F16E8 | medium | confirmed | Scientific reproducibility | inconsistency | hours | cran-comments.md misstates both the check status and the extdata sizes it uses to justify the install-size NOTE |
| F3467DC | medium | partial | Scientific reproducibility | inconsistency | hours | Four mutually incompatible definitions of the headline benchmark's target variable across README, vignette and runner |
| F366B1F | medium | confirmed | Scientific reproducibility | doc-gap | hours | README's headline benchmark tables are two to four release cycles stale, and the current 6-method result exists only in NEWS.md |
| F54856E | medium | confirmed | Scientific reproducibility | bug | hours | The "LLM-augmented (Gemma 4)" DAG in the causal-discovery trio is six hand-typed edges, not an LLM output |
| F5672C5 | medium | confirmed | Scientific reproducibility | doc-gap | hours | DESCRIPTION's "every vignette runs offline" is false: four advertised vignettes are not vignettes, and the Pilar 4 × Pilar 6 vignette evaluates nothing |
| F884A23 | medium | confirmed | Scientific reproducibility | process-gap | days | The flagship case-study benchmark cannot be re-run by anyone: its input is .gitignore'd and its output path is not the shipped artefact |
| FDA80DD | medium | confirmed | Scientific reproducibility | bug | hours | Residual kriging (B2) is fit to in-bag rather than OOB forest residuals, manufacturing the README's PICP conclusion |
| F71D795 | medium | confirmed | Incomplete implementations | incomplete-implementation | hours | The spBayes backend is advertised as an equal peer in README/NEWS/man but predict(), as_edaphos_posterior() and al_query_bhs() all fail on it |
| F9046AE | medium | confirmed | Incomplete implementations | doc-gap | minutes | bhs_fit()'s rcpp backend is absent from its own @param documentation, and al_query_bhs() rejects it despite the fit being complete |
| FAEC54C | medium | partial | Incomplete implementations | bug | hours | al_fit() performs no validation of num.trees against nrow(labeled), producing an opaque ranger error; the guarding test is unseeded and fails ~12% of runs |
| FC68E1D | medium | confirmed | Incomplete implementations | bug | minutes | foundation_weights_load() requires torch BEFORE resolving the registry, so the placeholder v2 entry reports the wrong reason for failing |
| FD825FD | medium | confirmed | Incomplete implementations | bug | hours | bhs_fit() returns an all-NaN posterior for a rank-deficient design matrix, and the edge-case test is written to accept it |
| FFFC52E | medium | confirmed | Incomplete implementations | bug | minutes | causal_iv bootstrap silently discards failed 2SLS replicates and rewrites B to the survivor count |
| F21DBBA | medium | confirmed | Test coverage | bug | minutes | test-foundation-weights.R:29-36 asserts an error message that is unreachable without torch (live ERROR 2) -- green on CI, red on CRAN |
| F2C0D91 | medium | partial | Test coverage | bug | minutes | al_fit is ~14.5%-flaky by construction: test-active-quantum-posterior.R:30-35 has no set.seed and passes num.trees=50 for OOB quantile regression (live ERROR 1) |
| F86487C | medium | confirmed | Test coverage | doc-gap | hours | R/pilar7_bayesian_hierarchical.R:270-272 cites a test that does not perform the verification it claims |
| FA6ECC8 | medium | confirmed | Test coverage | missing-work | hours | The RcppArmadillo BHS Gibbs backend has no real numerical-agreement test: one scalar mean at 0.2 tolerance, w_post_mean never compared, no edge cases |
| FB609A4 | medium | partial | Test coverage | doc-gap | minutes | NEWS.md v3.10.0 test and check claims are not reproducible in any environment the project automates |
| FB6D884 | medium | confirmed | Test coverage | missing-work | days | 12 exported functions are never called by any test, including the entire tile-download layer and a function that recursively deletes a directory |
| FBCB1E4 | medium | confirmed | Test coverage | incomplete-implementation | days | The v3.8.0 friendly-error work covers 4 of 169 exports; .assert_type/.stopf adopted in 6 of 70 R/ files |
| FC5841E | medium | confirmed | Test coverage | process-gap | minutes | Three of four wall-clock assertions run on CRAN: only 1 skip_on_cran() exists in the whole 460-block suite |
| F0CBFC4 | low | confirmed | CI & infra | process-gap | hours | test-coverage has no threshold gate, no codecov.yml, and diverges from R-CMD-check on TORCH_INSTALL; reported coverage has an invisible ~75% ceiling |
| F6330AE | low | partial | CI & infra | tech-debt | minutes | pkgdown site loads mermaid from a third-party CDN with no integrity attribute, on a surface SECURITY.md declares in scope |
| FA46190 | low | partial | CI & infra | process-gap | days | Documented quality gates (spell check, URL check, lint) exist in prose and templates but in no workflow; `_R_CHECK_FORCE_SUGGESTS_` is never relaxed across 40 Suggests |
| FAACA6C | low | partial | CI & infra | incomplete-implementation | minutes | `needs: website` and `needs: coverage` are no-ops: DESCRIPTION declares no Config/Needs/* fields |
| FAF9367 | low | partial | CI & infra | tech-debt | minutes | .Rbuildignore hygiene: version-pinned checklist pattern, duplicated entry, dead README.Rmd rule |
| FDA19FA | low | partial | CI & infra | tech-debt | hours | No dependency pinning outside the Dockerfile; floating action tags in a job granted `contents: write` |
| F434C69 | low | confirmed | Code quality | tech-debt | minutes | %\|\|% is copy-pasted into 7 files; the definition that actually wins is decided by alphabetical collation, not by design |
| F503F9C | low | confirmed | Code quality | bug | hours | quantum_kernel_rcpp allocates nX * 2^n complex states but its only guard is a warning keyed on n alone |
| F594BF7 | low | partial | Code quality | tech-debt | hours | Dead code, an undocumented non-dotted internal, and three comment/code contradictions in the pillar 7-10 modules |
| FA36407 | low | partial | Code quality | process-gap | days | The v3.8.0 friendly-error system covers ~5% of failure sites and exactly the 6 files that got a test; 136 raw stop() and 13 divergent torch gates bypass it |
| FB51F5F | low | confirmed | Code quality | bug | minutes | history[history > 0] injects NA into fit$history; the fix exists in all four torch files and none of the three pure-R files |
| FFAFBF2 | low | partial | Code quality | tech-debt | days | 169 exports + 73 S3 methods is an exceptionally wide public API for 19.7k LOC, with several internal-looking primitives promoted to the surface |
| F4516A9 | low | partial | CRAN readiness | doc-gap | hours | Maintainer-only files install into the user's library; CITATION metadata is stale and there is no inst/CITATION |
| F5825EA | low | partial | CRAN readiness | tech-debt | minutes | 6 of 40 Suggests are never used anywhere in the package |
| FEC2806 | low | confirmed | CRAN readiness | bug | minutes | `MASS::ginv()` called unguarded at 5 sites while MASS is Suggests-only |
| FEDA31F | low | partial | CRAN readiness | bug | hours | Two network entry points call `httr2::req_perform()` with no error handling, against CRAN's graceful-failure policy |
| FF58F4E | low | partial | CRAN readiness | incomplete-implementation | hours | Two exported functions are unconditional `stop()` stubs, documented and counted as shipped features |
| F63C7AD | low | partial | Release consistency | incomplete-implementation | hours | Placeholder and NA DOIs are committed: the exported weights registry advertises an encoder with no URL, DOI or checksum |
| F6C4FB9 | low | partial | Release consistency | doc-gap | hours | _pkgdown.yml's release list stops at v2.0.0 and its site description still says six pillars |
| FA7F096 | low | partial | Release consistency | bug | minutes | RELEASE-CHECKLIST-v3.10.0.md instructs the maintainer to upload artefacts that do not exist and names the wrong deploy action |
| FEA55C5 | low | confirmed | Release consistency | process-gap | hours | 32 of the last 33 NEWS releases have no git tag, violating the project's own documented release policy |
| FFBBEBB | low | partial | Release consistency | inconsistency | hours | Dockerfile self-identifies as v2.1.0 and pins a 2026-04-23 CRAN snapshot, but installs HEAD |
| F1A720B | low | confirmed | Roadmap promises | missing-work | weeks | v1.8.3 (expand LLM gold standard from 72 to 300 claims) is untouched — still 30 abstracts / 72 claims |
| F2FC8F9 | low | partial | Roadmap promises | doc-gap | minutes | V1_3_2_HANDOFF.md instructs the maintainer to cd into a directory named after a different project |
| F3E4CA6 | low | partial | Roadmap promises | doc-gap | hours | Documentation promises that point at content which does not exist: cheatsheets "on the pkgdown site", P8/P9 benchmarks "in vignettes/" |
| F4BEE44 | low | confirmed | Roadmap promises | bug | minutes | package_v2_for_zenodo.R fails with a cryptic stopifnot before its own step-count guard, and drops the resume hint from its error message |
| F4EE43C | low | partial | Roadmap promises | inconsistency | hours | Roadmap table and NEWS were never updated for the last two feature commits; DESCRIPTION 3.10.0 conflicts with the 3.11.0 baked into the weights registry |
| F66D149 | low | partial | Roadmap promises | tech-debt | minutes | Stale dead-end in data-raw/causal_iv_benchmark.R blocks a path that v1.9.1 already delivered |
| F9EDEBA | low | partial | Roadmap promises | inconsistency | minutes | Pilar 7 was promised as INLA/Stan and delivered as a hand-rolled Gibbs sampler; the substitution is never disclosed |
| FCC0D53 | low | partial | Roadmap promises | missing-work | days | Promised production-scale outputs never produced: the 10k-abstract LLM-KG run and the 6-pillar benchmark wrapper set |
| F37E56E | low | confirmed | Incomplete implementations | bug | hours | foundation_embed_at_coords() converts a failed raster block read into an all-zero patch that is indistinguishable from a real embedding |
| F3A34C0 | low | confirmed | Incomplete implementations | bug | minutes | foundation_build_cerrado_stack() calls digest::digest() unguarded, but digest is Suggests-only -- the exported function dies on a clean install |
| F3CACF8 | low | partial | Incomplete implementations | bug | minutes | Off-by-one in the RcppArmadillo Gibbs sampler's w_post_mean accumulation makes the rcpp backend disagree with the R backend it claims to reproduce |
| F52B874 | low | partial | Incomplete implementations | doc-gap | minutes | Two exported functions ship without \value in man/, contradicting the NEWS claim of 0 R CMD check notes |
| F649AF8 | low | partial | Incomplete implementations | tech-debt | minutes | Stale forward-looking version markers and dead code left in shipped R/ sources |
| FBDF515 | low | confirmed | Incomplete implementations | bug | hours | quantum_kernel() with the default rcpp backend has only a warning where it needs a hard cap, and silently returns an all-ones kernel for reps <= 0 |
| F1A5FC0 | low | partial | Test coverage | inconsistency | hours | 12 duplicated, semantically divergent torch skip helpers shadow the canonical helper-torch.R; the package's own runtime guards never check torch_is_installed() |
| F3CED48 | low | confirmed | Test coverage | missing-work | hours | 44 print/summary S3 methods, zero snapshot tests, 15 expect_output calls -- half of them behind torch/qiskit gates |

### Detail — blocker and high severity

#### F0BC16C — "CI green" and "0 errors | 0 warnings | 0 notes" are asserted in release docs while a dependency-independent test error would redden all 5 matrix legs

`CI & infra` · inconsistency · blocker · effort: hours · verdict: **CONFIRMED**

**Evidence**

> RELEASE-CHECKLIST-v3.10.0.md:3-4 "Status as of this commit: code 100 % ready, CI green, all artefacts regenerated." cran-comments.md:5 and :19-22 "`R CMD check --as-cran` -> 0 errors / 0 warnings / 0 notes" / "Status: OK". But the live failure at tests/testthat/test-active-quantum-posterior.R:34 -- `fit <- al_fit(df, target = "y", covariates = "x", num.trees = 50L)` -- routes through R/active_fit.R:1-10 `.fit_core()`, which calls `ranger::ranger(..., quantreg = TRUE, keep.inbag = TRUE)`. `ranger` is an **Imports** dependency with no version floor (DESCRIPTION:83 is bare `ranger,`), so it is installed on every CI leg; locally it is 0.18.0. The error "Too few trees for out-of-bag quantile regression" is therefore reproducible on CI, not a local dependency artifact. `r-lib/actions/check-r-package@v2` (R-CMD-check.yaml:53-56) defaults `error-on` to `"warning"`, so a test error is a hard check FAILURE on all five legs. By contrast the second live error, tests/testthat/test-foundation-weights.R:33 (expects `regexp = "requires.*n_channels"`, gets the torch gate message), is genuinely local-only: `.moco_require_torch()` at R/foundation_moco.R:28-34 checks only `requireNamespace("torch")`, never `torch_is_installed()`, so with the R torch package present on CI the gate passes and the n_channels validation at R/foundation_weights.R:312-316 fires as the test expects.

**Impact**

> The release documentation's central claim is unverifiable and most likely false. A CRAN submission driven by RELEASE-CHECKLIST-v3.10.0.md:19-21 (`devtools::submit_cran()`) would be rejected on the first auto-check. Worse, test-foundation-weights.R:29-37 is a test that is green only on CI and red locally, and 70 torch tests are green only locally and skipped on CI -- neither environment ever runs the full suite, so "the suite passes" has no single meaning in this project.

**Verification correction**

> none — and my own work strengthens it. RELEASE-CHECKLIST-v3.10.0.md:3-4 ("code 100 % ready, CI green, all artefacts regenerated") and cran-comments.md:5/:20-21 verified verbatim. The dependency argument holds: DESCRIPTION:83 is a bare `ranger,` under Imports, so ranger is on all five legs (R-CMD-check.yaml:23-27), and `r-lib/actions/check-r-package@v2` (:53-56) defaults `error-on` to "warning", making a test error a hard check failure. Critically, the failure is not merely "reproducible on CI" as the finding says — it is DETERMINISTIC, because test-active-quantum-posterior.R:7 seeds the file at set.seed(1L); I reproduced it 3/3 by replaying that stream on ranger 0.18.0. The second-error analysis is also correct: R/foundation_moco.R:28-34 `.moco_require_torch()` checks only `requireNamespace("torch")` and never `torch_is_installed()`, so with the torch R package installed on CI the gate passes and the n_channels validation at R/foundation_weights.R:310-316 fires as test-foundation-weights.R:29-36 expects — a test that is green only on CI and red only locally. Severity blocker is honest: submitting under RELEASE-CHECKLIST:19-21 would fail CRAN's incoming test run.

**Action**

> Fix the underlying defect: either raise `num.trees` in tests/testthat/test-active-quantum-posterior.R:34 (and any sibling call) above ranger's OOB-quantile threshold, or have `.fit_core()` in R/active_fit.R:1-10 validate `num.trees` against `nrow(labeled)` and emit an edaphos-level error. Add `ranger (>= 0.18.0)` to DESCRIPTION Imports. Then stop asserting CI state in prose: replace RELEASE-CHECKLIST-v3.10.0.md:3 and cran-comments.md:19-22 with a pasted, dated run log, and make the release checklist's first step "confirm the R-CMD-check badge is green for this SHA".

#### FF20A54 — "R CMD check: 0 errors / 0 notes" is false: two test errors reproduce in this tree, and one of them fires specifically in the torch-less CRAN environment that cran-comments.md swears is clean

`Release consistency` · incomplete-implementation · blocker · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> Claims: NEWS.md:71 "R CMD check: 0 errors / 0 notes."; cran-comments.md:19-22 "Status: OK / 0 errors | 0 warnings | 0 notes"; cran-comments.md:49-52 "The base test suite runs without `torch`, `terra`, `geodata`, `dagitty`, `bnlearn`, `Matrix`, `spBayes`, `shiny`, or `reticulate` installed." Live devtools::test() in this worktree (R 4.6.1, aarch64-darwin): 1022 pass / 109 skip / 2 ERRORS / 2 warnings. ERROR 2 falsifies cran-comments.md:49-52 directly: tests/testthat/test-foundation-weights.R:29-36 is the only test in that file with NO torch gate (the file defines `skip_if_no_torch()` at :3-8 and uses it at :38 and below, but not at :29); it does `expect_error(foundation_weights_load(f), regexp = "requires.*n_channels")`, and `foundation_weights_load()` calls `.moco_require_torch()` as its very first statement (R/foundation_weights.R:294), so without torch the error message is "Install the `torch` package to use foundation_moco_*()" and the expectation fails. ERROR 1 needs no optional package at all: tests/testthat/test-active-quantum-posterior.R:31-36 calls `al_fit(df, target = "y", covariates = "x", num.trees = 50L)` on n=40; R/active_fit.R:1-13 `.fit_core()` passes `quantreg = TRUE` unconditionally, and installed ranger 0.18.0 hard-errors "Too few trees for out-of-bag quantile regression". R/active_fit.R has not changed since f907388 ("Initial release of edaphos 0.1.0") -- the break came from ranger drifting, and DESCRIPTION:83 lists `ranger,` with NO version bound (contrast DESCRIPTION:80 `deSolve (>= 1.40)` and :84 `Rcpp (>= 1.0.0)`). R CMD check reports a testthat failure as an ERROR, so `R CMD check --as-cran` on a stock CRAN machine (no torch, current ranger) yields >=1 ERROR, not 0.

**Impact**

> cran-comments.md is the document a CRAN volunteer reads first. Submitting it as written asserts a check status that the submitting tarball cannot produce, which is the fastest possible route to an archived submission and a damaged maintainer reputation. The unbounded `ranger` import means the failure will also hit every user who installs today, not just CRAN.

**Verification correction**

> Headline CONFIRMED: NEWS.md:71 "R CMD check: 0 errors / 0 notes.", cran-comments.md:5/:20-21 "0 errors | 0 warnings | 0 notes", cran-comments.md:49-52 "base test suite runs without torch"; R/active_fit.R:7 quantreg=TRUE unconditional, al_fit at :52 / .fit_core call at :56, test call at test-active-quantum-posterior.R:34, ranger 0.18.0 installed, DESCRIPTION:83 `ranger,` unbounded vs :80 `deSolve (>= 1.40)` / :84 `Rcpp (>= 1.0.0)`, and R/active_fit.R last touched by f907388. Two sub-claims are wrong: (a) test-foundation-weights.R:29-36 is NOT "the only test in that file with NO torch gate" -- the blocks at :10 and :22 are also ungated (they pass); (b) skip_if_no_torch() is first used at :40, not :38.

**Action**

> Fix both tests: add `skip_if_no_torch()` to tests/testthat/test-foundation-weights.R:29 (or reorder R/foundation_weights.R:294 so argument validation precedes `.moco_require_torch()`), and raise `num.trees` at tests/testthat/test-active-quantum-posterior.R:34 to a value ranger accepts for OOB quantile regression (>=100, matching the sibling test at :17). Add a `ranger (>= x.y.z)` floor to DESCRIPTION:83. Then re-run `R CMD check --as-cran` in a container WITHOUT torch/dagitty/bnlearn/dbarts and paste the real output into cran-comments.md:19-22 instead of a remembered one.

#### F2A0EC5 — Shipped IV bundle refutes the README's "decisive test passes" headline: Sargan p = 3.2e-08, not 0.343

`Scientific reproducibility` · inconsistency · blocker · effort: days · verdict: **CONFIRMED**

**Evidence**

> `README.md:850-859` publishes a table titled "v1.9.1 — Real MoCo v2 patch extraction passes the Sargan test" with `MAP → SOC | 0.343 ✅`, `Tree cover → SOC | 0.283 ✅`, `Clay → SOC | 0.424 ✅`, and concludes "**The decisive test passes.** ... This is the central empirical contribution of v1.9.1."
> 
> The artefact shipped in the package, `inst/extdata/causal_iv_cerrado_real.rds` (stamped `version = 3.10.0`, `date_computed = 2026-04-27`, `used_real_stack = TRUE`), contains `benchmark_table` with the opposite result:
> 
> ```
> 2     MAP (mm/a) 2SLS (real MoCo v1)  beta=0.00757  stage1_F=1494.9  sargan_p=3.22e-08
> 4 Tree cover (%) 2SLS (real MoCo v1)  beta=56.7053  stage1_F=  14.8  sargan_p=7.47e-04
> 6       Clay (%) 2SLS (real MoCo v1)  beta=-4.4644  stage1_F=   2.69 sargan_p=8.86e-02
> ```
> 
> The over-identification test now **rejects** on 2 of 3 exposures. Three corroborating signs that the instruments are degenerate:
> (a) `r$embedding_sample_first5_64` is 53.3% exactly zero, with non-zero entries in the 300-470 range — a saturated/dead-ReLU encoder. Cause is visible at `data-raw/causal_iv_benchmark_real.R:66-71`, which feeds the real SoilGrids/WorldClim/SRTM stack through `dataset_meta` with `means = rep(0, moco$n_channels), sds = rep(1, moco$n_channels)` — i.e. **unnormalised**, against an encoder trained on z-scored tiles.
> (b) Tree-cover 2SLS β = 56.7 g/kg per 1% tree cover (CI 29.7–83.7) implies 5670 g/kg SOC across 0→100% cover — physically impossible.
> (c) Clay 2SLS β sign-flips vs OLS (−4.46 vs +0.195) at stage-1 F = 2.69, far below the Staiger–Stock threshold of 10.
> 
> The installed vignette carries the stale numbers as a hand-pasted, never-executed console transcript: `vignettes/pilar1-pilar4-iv.Rmd:424-428` inside an `eval = FALSE` chunk reads `#   2   MAP (mm/a) 2SLS (real MoCo v1) 0.01694  10.30  0.343  <- passa!`. The same vignette at line 316 states "**Todos os três estimadores 2SLS têm Sargan p ≈ 10⁻⁹**" and at line 346 "Sargan p permanece ≈ 0 para todos os k. Isso é uma assinatura clara de que os instrumentos são estruturalmente inválidos" — self-contradictory within one document.
> 
> Git history shows `05cb516 feat(v1.9.3): close roadmap promise -- IV refit with real 31-channel SoilGrids+WorldClim+SRTM stack` refreshed the bundle without updating the claim it refutes.

**Impact**

> The package's self-declared "central empirical contribution" is asserted in the README and in a pkgdown-rendered vignette while the data shipped in the same tarball demonstrates the opposite. Any reviewer, rOpenSci editor, or citing author who opens `causal_iv_cerrado_real.rds` finds a refutation of the headline. Because the embeddings are saturated garbage from an unnormalised forward pass, neither the old "passes" nor the new "fails" number is scientifically meaningful — the entire Pillar 1 × Pillar 4 IV result is unsupported.

**Verification correction**

> none on the core — I opened the bundle. inst/extdata/causal_iv_cerrado_real.rds carries version 3.10.0, date_computed "2026-04-27", used_real_stack TRUE, and benchmark_table rows: MAP 2SLS beta=0.007566, stage1_F=1494.93, sargan_p=3.2158e-08; Tree cover 2SLS beta=56.7052, F=14.80, sargan_p=7.468e-04; Clay 2SLS beta=-4.4644, F=2.686, sargan_p=8.857e-02 — over-identification rejects on 2 of 3. README.md:850-853 does publish 0.343/0.283/0.424 with ✅ under the header "v1.9.1 Sargan p (real MoCo)" and README.md:856-859 does declare "**The decisive test passes.** … the central empirical contribution of v1.9.1." data-raw/causal_iv_benchmark_real.R:66-71 confirms `means = rep(0, moco$n_channels), sds = rep(1, moco$n_channels)` fed to the real 31-channel stack, and its own comment concedes these stats are synthetic-mode values pending v1.9.2. Corroborators (b) β=56.7 g/kg per 1% tree cover and (c) the clay sign flip at F=2.69 hold. TWO WEAKENINGS: (a) the "53.3% exactly zero ⇒ saturated/dead-ReLU" inference is weak — ~50% zeros is textbook-normal for any ReLU embedding (the informative signal is the 3.29–465.86 magnitude range, not the cited "300-470"); and the vignette is less self-contradictory than claimed — vignettes/pilar1-pilar4-iv.Rmd:316/:346 ("Sargan p ≈ 10⁻⁹") is explicitly about the 27 *proxy* embeddings, a different instrument set, while the :419-428 transcript labels itself "no modo synthetic-stack". The undisputed fact remains: 05cb516 refreshed the bundle to a refutation and README.md:850-859 plus README.md:1626 and README.md:1700 ("Sargan passes empirically ✅") were never updated; README.md:1713 still marks v1.9.3 as 📝.

**Action**

> 1. Fix the normalisation: persist the real per-channel training means/sds alongside the Zenodo encoder and pass them in `data-raw/causal_iv_benchmark_real.R:66-71` instead of `rep(0)`/`rep(1)`. Assert `mean(emb == 0) < 0.1` and `max(abs(emb)) < 50` before proceeding. 2. Re-run at `target_res = 0.01` to match the encoder's training grid (the bundle records `stack_res_deg = 0.05`, and `vignettes/pilar1-pilar4-iv.Rmd:391` itself uses 0.01). 3. Rewrite `README.md:850-865` and `vignettes/pilar1-pilar4-iv.Rmd:416-428` to report whatever the re-run actually yields, and replace the pasted comment transcript with an evaluated chunk that reads the shipped bundle. 4. Add a test asserting the README's Sargan values against `inst/extdata/causal_iv_cerrado_real.rds`.

#### F862881 — Every β in the README's real-data causal table disagrees with the shipped bundle, and the confounding correction has the wrong sign for tree cover

`Scientific reproducibility` · inconsistency · blocker · effort: hours · verdict: **CONFIRMED**

**Evidence**

> `README.md:626-641` "### Real-data results: 1095 Cerrado profiles" publishes:
> ```
> | MAP (mm/a)     | naive 0.013 | adjusted 0.009 | confounding factor 1.5× |
> | Tree cover (%) | naive 0.42  | adjusted 0.31  | confounding factor 1.4× |
> | Clay (%)       | naive 0.38  | adjusted 0.25  | confounding factor 1.5× |
> ```
> plus "a block-bootstrap sample (**B = 500**)".
> 
> Extracted from the shipped `inst/extdata/causal_cerrado_real.rds` (`edaphos_ver = 1.3.1`), `$effects[[x]]$lm`:
> ```
> wc_bio_12           naive=0.00720039  adjusted=0.00709411  ratio=1.015  n_boot=200
> wc_landcover_trees  naive=0.89786     adjusted=2.04791     ratio=0.438  n_boot=200
> soilgrids_clay      naive=0.525729    adjusted=0.194894    ratio=2.698  n_boot=200
> ```
> Not one of the six β values matches. The "confounding factor" column (1.5 / 1.4 / 1.5) versus actual (1.02 / 0.44 / 2.70) is wrong by 32x in the worst case. Critically, for tree cover the backdoor adjustment **more than doubles** the effect (0.898 → 2.048), whereas the README presents adjustment as uniformly shrinking an upward-confounded naive estimate. `B = 500` is contradicted by `length(effect_boot) == 200`.
> 
> The adjustment *sets* do match the bundle (MAP: 5 covariates, tree cover: 2, clay: 3), which rules out "different DAG" as an explanation — the numbers were simply never refreshed from the artefact.
> 
> A third value for the same MAP quantity appears at `README.md:877` (`effect = 0.00769`) and a fourth in `inst/extdata/causal_iv_cerrado_real.rds` row 1 (`Backdoor OLS beta = 0.0077766`).

**Impact**

> The section that demonstrates the package's flagship Pillar 1 capability on real data reports numbers that exist nowhere in the repository, and reverses the sign of the scientific conclusion for one of three exposures. A reader who reproduces the analysis from `causal_cerrado_real.rds` — the documented way to do so — gets different answers with a different qualitative story. The uniform "≈1.5× confounding" pattern reads as fitted to the narrative rather than read off the data.

**Action**

> Regenerate the `README.md:632-636` table programmatically from `inst/extdata/causal_cerrado_real.rds$effects` (via `README.Rmd` or an extension of `tools/make-readme-figures.R`) so it cannot drift again. Correct `B = 500` to 200 at `README.md:639` or re-run with B = 500. Reconcile the four different MAP β values across `README.md:634`, `README.md:877`, `causal_cerrado_real.rds`, and `causal_iv_cerrado_real.rds`. Rewrite the narrative to state that adjustment increases the tree-cover effect, which is a more interesting finding than the one currently claimed.

#### FE42047 — pkgdown workflow cannot succeed: `has_concept("pilar1")` matches zero topics and 4 navbar links point at pages never built

`CI & infra` · bug · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> _pkgdown.yml:120-128 declares the Pilar 1 reference section with selector `- has_concept("pilar1")` (line 124). There are zero `\concept{}` tags across all 182 `man/*.Rd` topics (`grep -rln 'concept{pilar1}' man/` -> 0; `grep -rn '@family\|@concept' R/` -> 0 matches). pkgdown's `select_topics()` aborts when a reference-index selector matches no topics. Separately, `man/edaphos-package.Rd` is the one topic matched by none of the 19 prefix selectors or 16 exact names in _pkgdown.yml:119-217, which pkgdown reports as a missing-from-index diagnostic. Navbar menu links at _pkgdown.yml:75, 79, 91, 101 point to `articles/pilar1-causal-real.html`, `articles/llm-kg-benchmark.html`, `articles/pilar3-4d-real.html`, `articles/pilar5-soilgrids-br.html` -- but those four sources live in the root `articles/` directory (articles/llm-kg-benchmark.Rmd, articles/pilar1-causal-real.Rmd, articles/pilar3-4d-real.Rmd, articles/pilar5-soilgrids-br.Rmd), not in `vignettes/`, and no build step renders them (grep for `articles/` across *.R/*.yml/*.sh finds only the _pkgdown.yml hrefs). `.Rbuildignore:21` also excludes `^articles$` from the tarball.

**Impact**

> `pkgdown::build_site_github_pages()` (pkgdown.yaml:56) fails on the reference index, so the documentation site has never deployed -- corroborated by RELEASE-CHECKLIST-v3.10.0.md:75-98 and RELEASE.md:57-72 both still listing "enable GitHub Pages" as pending. The `url:` in _pkgdown.yml:1 and the site link in SECURITY.md:37 both advertise a site that does not exist. Even if the reference index were fixed, 4 of 18 navbar entries would 404.

**Action**

> Either add `@concept pilar1` (or `@family pilar1`) to the Pilar 1 roxygen blocks in R/causal_*.R and re-document, or delete _pkgdown.yml:124 (the `starts_with("causal_")` selector on line 125 already covers the section). Add `edaphos-package` to a reference section. For the four root `articles/*.Rmd`, either move them into `vignettes/` (and add to the `articles:` index at _pkgdown.yml:219-248, plus `.Rbuildignore` them individually if they must not ship) or delete the four navbar hrefs. Add a `pkgdown` job on pull_request that fails the build so this is caught next time.

#### FAC0043 — foundation_weights_load() gates on torch before validating its own arguments — the live ERROR 2

`Code quality` · bug · high · effort: minutes · verdict: **CONFIRMED**

**Evidence**

> R/foundation_weights.R:294 `.moco_require_torch()` is the FIRST statement of `foundation_weights_load()` (signature at :287-293). The pure-R argument validation that does not need torch at all is 15 lines later, :309-315: `if (is.null(n_channels) || is.null(feature_dim) || is.null(proj_dim)) stop("Loading from a local path requires `n_channels`, `feature_dim` and `proj_dim` to be supplied explicitly.", call. = FALSE)`.
> `.moco_require_torch()` is defined at R/foundation_moco.R:28-34 and raises "Install the `torch` package to use foundation_moco_*()".
> tests/testthat/test-foundation-weights.R:28-37 asserts `expect_error(foundation_weights_load(f), regexp = "requires.*n_channels")` with NO skip gate — while the very next test at :39-40 does call `skip_if_no_torch()`. So the test author knew about the gate and missed this one block.

**Impact**

> Two separate defects in one call: (1) a user who forgot `n_channels` is told to install a 1 GB dependency instead of being told which argument is missing — the opposite of the v3.8.0 friendly-error goal; (2) the test suite cannot go green on a torch-less machine, so the NEWS.md v3.10.0 claim of "R CMD check: 0 errors" cannot be reproduced by a reviewer without torch.

**Action**

> Move `.moco_require_torch()` from R/foundation_weights.R:294 down to just before the first torch call, i.e. immediately above `EncCtor <- .moco_build_encoder()` at :326. That makes the argument validation at :309-315 reachable without torch and fixes the test with no test change. Independently, convert :311-315 to `.stopf(..., hint = "Read them from foundation_weights_list() or pass n_channels/feature_dim/proj_dim explicitly.")` for consistency with the other v3.8.0 entry points.

#### F52C0B8 — cran-comments.md is self-contradictory and every quantitative claim in it is stale or wrong

`CRAN readiness` · inconsistency · high · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> Within one file:
> - `cran-comments.md:17-22` — `Status: OK / 0 errors | 0 warnings | 0 notes`.
> - `cran-comments.md:69-70` — "`R CMD check --as-cran` reports an installed size of ~13 MB, above the CRAN soft-cap of 5 MB." An installed size over 5 MB *is* the `checking installed package size ... NOTE`, so "0 notes" and "~13 MB installed" cannot both hold.
> 
> Stale/incorrect numbers:
> - `:30` — "`devtools::test()` -- **1 345 unit tests**, 0 failures, 4 warnings, 2 skips." Live run: 1022 passing expectations, **109 skips**, **2 errors**, 2 warnings.
> - `:33-35` — attributes the 4 warnings to "stats::sweep recycling on odd column counts (Pilar 8)" and the 2 skips to "LLM-benchmark tests that require a live Ollama instance." Actual skips are 74x `{torch}`, 22x `{dagitty}`, 9x `{bnlearn}`, 3x `{dbarts}`; actual warnings are `NAs produced` x2 in `bhs_fit` (`tests/testthat/test-pilar7-bhs-edge.R:61`).
> - `:74-76` — claims `benchmark_wosis_p4_p5_p7.rds` is `0.7 MB` (actual **1,959,632 B = 1.9 MB**) and `causal_cerrado_real.rds` is `1.6 MB` (actual **63,521 B = 62 KB**).
> - `:71-72` — "The extra ~8 MB is the `inst/extdata/` directory": `inst/extdata` is **9.98 MB**, and the itemised list omits `case_cerrado_results.rds` (1.47 MB), `capstone_native_calibration.rds` (0.76 MB), `capstone_campaign_results.rds` (0.56 MB), `temporal_cerrado_results.rds` (0.20 MB) — ~3 MB unaccounted. `man/figures` (2.3 MB) is not mentioned at all.
> - `:4-5` claims the local check ran on "R 4.5.3"; the local R is 4.6.1.
> - `:52` claims the base test suite runs without `Matrix` — but `Matrix::` is reached at 2 sites with only 1 `requireNamespace` guard.

**Impact**

> cran-comments.md is the first thing a CRAN volunteer reads. A file that contradicts itself in two adjacent sections and misstates file sizes by 26x invites a hostile review of everything else, and the claimed clean check will be trivially disproven by CRAN's own log.

**Verification correction**

> Almost everything holds, but the title's "every quantitative claim" is false and one sub-claim is REFUTED. Verified true: :20-21 "Status: OK / 0 errors | 0 warnings | 0 notes" vs :69-70 "~13 MB" installed above the 5 MB soft cap (that IS the installed-size NOTE, so the two cannot both hold); :30-31 and :33-35 test/skip/warning claims all wrong; `causal_cerrado_real.rds` is 63,521 B = 62 KB vs the claimed 1.6 MB (26x); `du -sk inst/extdata` = 9780 KB vs "~8 MB"; the itemised list omits case_cerrado_results.rds (1,469,189 B), capstone_native_calibration.rds (758,948 B), capstone_campaign_results.rds (556,352 B), temporal_cerrado_results.rds (198,786 B); man/figures is 2364 KB and unmentioned; :4 R 4.5.3 vs local 4.6.1. NOT true: `benchmark_wosis_p4_p5_p7.rds` is 1,959,632 B = 1.87 MB vs claimed 0.7 MB — that is 2.7x, not 26x (the 26x applies only to causal_cerrado_real.rds), and `benchmark_wosis_6pilar.rds` at 4,640,252 B genuinely is ~4.5 MB as claimed. REFUTED: ":52 claims the base test suite runs without `Matrix` — but `Matrix::` is reached at 2 sites with only 1 `requireNamespace` guard." There is exactly one `Matrix::` *call* (R/pilar10_graph_nn.R:148) and it sits inside `if (requireNamespace("Matrix", quietly = TRUE))` at :147; :120 is a comment. cran-comments is correct about Matrix. Severity deflated from blocker: this is a ~20-minute prose/arithmetic fix in an .Rbuildignore'd file, embarrassing but code-neutral.

**Action**

> Delete the hand-written numbers. Run `R CMD check --as-cran` once, paste the verbatim tail of the log into `cran-comments.md`, and generate the size table with `du -b inst/extdata/* man/figures/*` rather than from memory. Drop the "0 notes" line and instead explain the (unavoidable) size NOTE.

#### FA81F77 — Undeclared `utils` and `tools` namespaces — guaranteed R CMD check WARNING that cran-comments.md denies

`CRAN readiness` · bug · high · effort: minutes · verdict: **CONFIRMED**

**Evidence**

> `DESCRIPTION:78-85` declares `Imports: clhs, deSolve (>= 1.40), httr2, jsonlite, ranger, Rcpp (>= 1.0.0), stats` — no `utils`, no `tools`. `NAMESPACE` imports nothing beyond `importFrom(Rcpp,evalCpp)` and `useDynLib(edaphos, .registration = TRUE)`.
> 
> R/ reaches into both via `::` anyway — 35 `utils::` sites and 8 `tools::` sites:
> - `R/causal_corpus.R:227`  `collected <- utils::head(collected, max_results)`
> - `R/causal_kg_io.R:80`, `:370`  `as.character(utils::packageVersion("edaphos"))`
> - `R/causal_dag.R:316`  `utils::modifyList(bart_defaults, bart_kwargs)`
> - `R/causal_llm.R:378`, `:444`  `utils::txtProgressBar` / `utils::setTxtProgressBar`
> - `R/causal_ontology.R:194`  `utils::adist(...)`
> - `R/bridges_active_learning_v3.R:131`, `:220`, `:318` and `R/causal_active_learning.R:157`  `utils::head`
> - `R/foundation_weights.R:111`  `tools::R_user_dir("edaphos", which = "cache")`
> - `R/foundation_embed_coords.R:226`  `cache_dir = tools::R_user_dir("edaphos", which = "cache")`
> - `R/causal_llm.R:320`  `as.character(tools::md5sum(tf))`
> 
> `R CMD check` emits `* checking dependencies in R code ... WARNING / '::' or ':::' import not declared from: 'tools', 'utils'`. `cran-comments.md:19-22` asserts `Status: OK / 0 errors | 0 warnings | 0 notes`.

**Impact**

> A WARNING (not a NOTE) on the CRAN incoming pipeline. Submissions with an unexplained WARNING are auto-rejected before a human reviewer sees them, and the cran-comments claim of a clean check is demonstrably false on the very first check section.

**Verification correction**

> Substance confirmed: DESCRIPTION:78-85 Imports = clhs, deSolve, httr2, jsonlite, ranger, Rcpp, stats (no utils, no tools); NAMESPACE's only import line is 245 `importFrom(Rcpp,evalCpp)`; every cited call site exists (causal_corpus.R:227, causal_kg_io.R:80/:370, causal_dag.R:316, causal_llm.R:378/:444/:320, causal_ontology.R:194, bridges_active_learning_v3.R:131/:220/:318, causal_active_learning.R:157, foundation_weights.R:111, foundation_embed_coords.R:226). `R CMD check` reports undeclared `::` imports as a WARNING, and cran-comments.md:19-22 asserts 0 warnings. Minor overcount: the raw greps return 35 utils:: / 11 tools:: lines, but several are roxygen or comments — the real *code* call sites are ~31 utils:: and 3 tools:: (foundation_weights.R:111, foundation_embed_coords.R:226, causal_llm.R:320). The WARNING fires regardless.

**Action**

> Add `utils` and `tools` to `Imports` in DESCRIPTION (they are base-distribution packages, so this adds no install cost), then regenerate `cran-comments.md` from an actual `R CMD check --as-cran` log rather than from prose.

#### FCBA23B — 134 of 169 exported functions have no examples; only 10 have an example R CMD check executes

`CRAN readiness` · missing-work · high · effort: days · verdict: **CONFIRMED**

**Evidence**

> Cross-referencing `NAMESPACE` (169 `export()` lines) against `man/*.Rd` `\alias{}` blocks: **134 exports have no `\examples` section at all**. 146 of 182 Rd files have no `\examples`. Of the 36 files that do, 18 wrap the whole block in `\dontrun{}` and 8 in `\donttest{}` — leaving **10 exported functions with an example `R CMD check` actually runs**: `causal_sensitivity_summary`, `edaphos_posterior`, `foundation_weights_list`, `piml_profile_fit`, `piml_profile_fit_bayesian`, `predict.edaphos_piml_bayes`, `quantum_feature_map`, `quantum_kernel`, `temporal_synth_soc_cube`, `llm_annotation_vocabulary`.
> 
> The undocumented set includes every flagship entry point: `bhs_fit` (man/bhs_fit.Rd — has `\value`, `\description`, `\references`, no `\examples`), `uncertainty_calibrate` (man/uncertainty_calibrate.Rd — same), `dm_fit`, `dm_sample`, `gnn_fit`, `no_fno_fit`, `no_deeponet_fit`, `al_query`, `al_update`, `causal_estimate_effect`, `causal_adjustment_set`, `temporal_convlstm_fit`, `foundation_moco_pretrain`, `quantum_krr_posterior`, and all 10 `edaphos_*` metric helpers (`edaphos_rmse`, `edaphos_r2`, `edaphos_picp`, ...) which are pure numeric functions with no dependency excuse.
> 
> This is asserted false twice in the submission material: `inst/rosc/submission.md:76-78` — "**Examples**: every exported function has at least one `@examples` block" — and `:104` — "[x] All exported functions have Roxygen docs with `@return` and `@examples`."

**Impact**

> "Please add small executable examples to your Rd files" is one of the most common CRAN first-round rejections, and rOpenSci review will not pass a package where 79% of the public API is unexercised by examples. The false self-report in inst/rosc/submission.md means the rOpenSci editor is misled in the pre-submission inquiry itself.

**Verification correction**

> none — reproduced exactly by cross-referencing NAMESPACE's 169 `export()` lines against `\alias{}`/`\examples` in all 182 man/*.Rd: 134 exports have no `\examples`; 36 of 182 Rd files have one; the 10 with a block R CMD check runs are exactly the named set (edaphos_posterior, causal_sensitivity_summary, piml_profile_fit, quantum_feature_map, predict.edaphos_piml_bayes, foundation_weights_list, llm_annotation_vocabulary, quantum_kernel, piml_profile_fit_bayesian, temporal_synth_soc_cube). bhs_fit, uncertainty_calibrate, dm_fit, dm_sample, gnn_fit, no_fno_fit, no_deeponet_fit, al_query, al_update, causal_estimate_effect, causal_adjustment_set, temporal_convlstm_fit, foundation_moco_pretrain, quantum_krr_posterior, edaphos_rmse/r2/picp all verified as exported with an Rd page and no examples. inst/rosc/submission.md:76-78 and :104 assert the opposite.

**Action**

> Start with the ~40 exports that are pure and cheap (`edaphos_rmse/r2/mae/bias/picp/ece/interval_score/metrics_summary`, `dm_cosine_schedule`, `quantum_scale`, `quantum_hamiltonian*`, `causal_kg_*`, `gnn_build_graph`, `temporal_cube_to_tensor`) — these need 2-4 line examples on `br_cerrado` or synthetic data with no Suggests at all. Then add `\donttest{}` examples for `bhs_fit` and `uncertainty_calibrate` on a 50-row subset. Correct the two false claims in `inst/rosc/submission.md:76-78,104` before filing.

#### FDE7C43 — Installed size will NOTE: inst/extdata 9.98 MB + man/figures 2.3 MB, of which a 1.9 MB PNG logo

`CRAN readiness` · tech-debt · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> Measured: `inst/` **9.6 MB** (`inst/extdata` = 9.98 MB by byte sum across 19 files), `man/` **3.1 MB** of which `man/figures/` is **2.3 MB**, `data/` 72 KB, `R/` 948 KB, `tests/` 424 KB, `vignettes/` 296 KB. Repo total excluding `.git`: 19 MB.
> 
> Largest single offender is `man/figures/logo.png` at **1,919,230 B (1.9 MB)** — a package hex logo, 15x larger than the next biggest figure (`pillar6-quantum.png`, 124 KB) and larger than every `.rda` in `data/` combined.
> 
> `inst/extdata` heavy hitters: `benchmark_wosis_6pilar.rds` 4.64 MB, `benchmark_wosis_p4_p5_p7.rds` 1.96 MB, `case_cerrado_results.rds` 1.47 MB, `capstone_native_calibration.rds` 0.76 MB, `capstone_campaign_results.rds` 0.56 MB.
> 
> Dead payload that ships for nothing: `inst/extdata/llm_kg_smoke_claims.jsonl` (8,051 B) has **zero** references anywhere in `R/`, `tests/`, `vignettes/`, `articles/`, `data-raw/`, `README.md`; `man/figures/pillar4-foundation.png` (59,278 B) is referenced by no Rd file and no README line.
> 
> `RELEASE-CHECKLIST-v3.10.0.md:15` states the built source tarball is **17 MB** — against CRAN's 5 MB guidance for data + docs.

**Impact**

> `* checking installed package size ... NOTE` is unavoidable and will be the first thing quoted back. CRAN routinely rejects >10 MB first submissions outright pending justification, and the justification currently on file (cran-comments.md:67-96) misstates the sizes it is justifying.

**Action**

> Three mechanical wins before touching the benchmark bundles: (1) re-encode `man/figures/logo.png` at 240px with `optipng`/`pngquant` — 1.9 MB to ~40 KB; (2) delete unreferenced `inst/extdata/llm_kg_smoke_claims.jsonl` and `man/figures/pillar4-foundation.png`; (3) re-save the five largest `.rds` with `saveRDS(..., compress = "xz")`. Then re-measure and rewrite the cran-comments size section from `du -b` output.

#### F36D2FE — The "v3.11.0" work is committed and self-referenced in shipped code, but no version exists: no DESCRIPTION bump, no NEWS section, no tag

`Release consistency` · process-gap · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> DESCRIPTION:3 `Version: 3.10.0`. NEWS.md:1 `# edaphos 3.10.0` -- `grep '^# ' NEWS.md` shows no 3.11.0 section anywhere. `git rev-list --count v3.10.0..HEAD` = 16. `git log --oneline v3.10.0..HEAD -- DESCRIPTION NEWS.md` returns only 797adc5, which edited the Description *text* field (6->10 pillars), never the Version field; `git log -L 3,3:DESCRIPTION` shows the Version line last changed at 46df3d8 (v3.10.0). Commit 7400a2c "feat(v3.11.0): hand-off package for the v1.3.2 MoCo v2 publish pipeline" touched exactly 5 files (R/foundation_weights.R, data-raw/pretrain_cerrado_train_v2.R, tools/pretrain/{V1_3_2_HANDOFF.md,package_v2_for_zenodo.R,wire_up_v2_doi.R}) -- neither DESCRIPTION nor NEWS.md. Yet the tree now asserts v3.11.0 in FOUR places, three of them user-visible: R/foundation_weights.R:82 `edaphos_version = c("1.2.0", "3.11.0")` (returned by the exported `foundation_weights_list()`); R/foundation_embed_coords.R:186 "As of v3.11.0", :204 "the v3.11.0 rewrite closes that gap", :220 "pre-v3.11.0"; and the roxygen-generated help page man/foundation_build_cerrado_stack.Rd:31,39,58. `git log -S 'v3.11.0'` shows the v3.11.0 doc strings were actually introduced one commit EARLIER, by 05cb516, which is titled "feat(v1.9.3)".

**Impact**

> `foundation_weights_list()` tells a user of edaphos 3.10.0 that a registry row requires edaphos 3.11.0, and `?foundation_build_cerrado_stack` documents behaviour "as of v3.11.0" -- a version that does not and may never exist. Anyone bisecting, citing, or reproducing HEAD has no version handle at all: HEAD is 16 commits of unnamed work, two of which (05cb516, 7400a2c) announce version numbers in their subject lines that appear nowhere in the package metadata. The v3.11.0 changes are therefore unreleasable as-is and unciteable.

**Action**

> Decide the number once, then make it consistent in one commit: set DESCRIPTION:3 to `Version: 3.11.0`, prepend a `# edaphos 3.11.0` section to NEWS.md covering 05cb516 (31-channel IV refit), 7400a2c (MoCo v2 hand-off), 272b378 (MPS/CUDA resume fix), 01b7836 (covr workflow), 0adabef (governance docs), fd4ab0b (301-claim corpus), and tag it `git tag -a v3.11.0`. If v3.11.0 is not to be released, revert the v3.11.0 strings in R/foundation_weights.R:82, R/foundation_embed_coords.R:186,204,220 and re-roxygenise so man/ stops claiming a nonexistent version.

#### F5EF8F6 — Four mutually exclusive citation versions: DESCRIPTION 3.10.0, README 2.8.0, CITATION.cff 2.1.0, CITATION.cff preferred-citation 1.6.0

`Release consistency` · inconsistency · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> DESCRIPTION:3 `Version: 3.10.0`. README.md:1727 "Rodrigues, H. (2026). *edaphos ...* (Version 2.8.0) [Software]. Zenodo." and README.md:1734 bibtex `version   = {2.8.0}`. CITATION.cff:109 `version: "2.1.0"` with CITATION.cff:110 `date-released: "2026-04-23"`. CITATION.cff:184 `preferred-citation: ... version: "1.6.0"` -- i.e. the block CFF consumers prefer names a fifth-oldest release. `ls inst/CITATION` -> ABSENT, so `citation("edaphos")` falls back to DESCRIPTION and returns yet another answer (3.10.0), which README.md:1745-1747 actively directs users to ("An auto-generated citation is also available in R: `citation("edaphos")`"). CITATION.cff's abstract is also frozen: CITATION.cff:7 "It is organised across six research pillars" and the narrative stops at v2.1.0 (CITATION.cff:97-107), so the .cff describes a 6-pillar package while DESCRIPTION:8-9 describes a 10-pillar one.

**Impact**

> GitHub renders the "Cite this repository" widget from CITATION.cff, so the repo's most prominent citation surface advertises v2.1.0 released 2026-04-23. Zenodo, Zotero, and rOpenSci tooling ingest the same file. A reader who cites via GitHub gets 2.1.0, via README gets 2.8.0, via `citation()` gets 3.10.0, via a CFF parser honouring preferred-citation gets 1.6.0. None of 2.8.0, 2.1.0 or 1.6.0 corresponds to a resolvable git ref except 1.6.0. This is unfixable after publication -- wrong versions propagate into other people's bibliographies.

**Verification correction**

> none — all four verified: DESCRIPTION:3 `Version: 3.10.0`; README.md:1727 "(Version 2.8.0)" and README.md:1734 `version = {2.8.0}`; CITATION.cff:109 `version: "2.1.0"` with :110 `date-released: "2026-04-23"`; preferred-citation `version: "1.6.0"`. `ls inst/CITATION` -> No such file. CITATION.cff:7 "organised across six research pillars" vs DESCRIPTION:8-9 "ten research pillars". Of 2.8.0 / 2.1.0 / 1.6.0 only v1.6.0 is a real tag (tag list ends v1.6.0 then jumps to v3.10.0).

**Action**

> Make CITATION.cff the single source and derive it: set CITATION.cff:109 `version` and :110 `date-released` to the real release, delete or sync the redundant :184 `version` inside preferred-citation, refresh the :4-107 abstract to the 10-pillar description from DESCRIPTION:8-28, and update README.md:1727 and :1734 to the same number. Add a release-checklist step (or a CI job running `cffconvert --validate` plus a version-equality assertion against DESCRIPTION) so the four never drift again.

#### F5F7D9A — The "1 345 tests" figure is unreproducible, mis-attributed, and the NEWS test-count chain contains two arithmetic breaks

`Release consistency` · doc-gap · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> Claims: README.md:12 badge `tests-1345%20pass`; NEWS.md:72 "1 345 tests pass (+17 vs v3.9.0)."; cran-comments.md:30-35 "`devtools::test()` -- **1 345 unit tests**, 0 failures, 4 warnings, 2 skips. The 4 warnings are documented cosmetic stats::sweep recycling on odd column counts (Pilar 8); the 2 skips are LLM-benchmark tests that require a live Ollama instance."; inst/rosc/submission.md:69 "**Unit tests**: 50+ test files, **1 345 expectations**." Measured in this tree: 68 test-*.R files, 460 `test_that(` blocks, 1089 `expect_` calls, 75 `skip_if_not_installed(` calls. Live run: 1022 pass, 109 skip, 2 errors, 2 warnings. Every sub-claim of cran-comments.md:30-35 is wrong: the skip count is 109 not 2; the skip REASONS are 74x torch, 22x dagitty, 9x bnlearn, 3x dbarts, 1 other -- zero Ollama-related; and the sweep warning it blames was already suppressed by commit 4b15fb7 "fix(ci/windows): suppress cosmetic sweep() warning in test-pilar8-no-edge.R:42", while the actual 2 live warnings are "NAs produced" from `bhs_fit` at tests/testthat/test-pilar7-bhs-edge.R:61 (Pilar 7, not 8). The NEWS chain also does not add up: NEWS.md:299 (3.6.0) 1274, NEWS.md:242 (3.7.0) "1 282 (+7 vs v3.6.0)" -> 1274+7=1281, off by 1; NEWS.md:195 (3.8.0) "1 308 (+20 vs v3.7.0)" -> 1282+20=1302, off by 6. The rest of the chain is internally consistent (3.0.0=1177 -> 3.1.0=1213 -> 3.2.0=1239 -> 3.3.0=1239 -> 3.4.0=1256 -> 3.5.0=1269 -> 3.6.0=1274; 3.9.0=1328 -> 3.10.0=1345), so 7 tests were introduced by arithmetic rather than by code. README is additionally self-contradictory: the badge says 1345 while README.md:1672 in the same file says "**109+ unit and integration tests**".

**Impact**

> 1345 is defensible ONLY on a machine with torch, dagitty, bnlearn and dbarts installed (the 109 gated blocks would then execute and multiply into expectations) -- but that is nowhere stated, and no environment in the repo reproduces it. As published, the number is unverifiable by any reader and demonstrably wrong in the environment cran-comments.md itself designates as the base case. inst/rosc/submission.md:69's "50+ test files" understates 68, and calling 1345 "expectations" in one file and "unit tests" in another means the project does not know which quantity it is quoting.

**Verification correction**

> none — independently measured: 68 `test-*.R` files, 460 `test_that(` blocks, 1089 `expect_` calls, 75 `skip_if_not_installed(`. README.md:12 badge `tests-1345%20pass`, NEWS.md:72, cran-comments.md:30-35, inst/rosc/submission.md:69 all verified verbatim. Arithmetic breaks verified: NEWS.md:299 (3.6.0)=1274, NEWS.md:242 (3.7.0)=1282 but 1274+7=1281 (off by 1); NEWS.md:195 (3.8.0)=1308 but 1282+20=1302 (off by 6). The Ollama attribution is verified impossible: `grep -rn 'skip_on_cran|skip_if_offline|skip_on_ci' tests/testthat/` returns exactly one hit (test-quantum-kernel-rcpp.R:46). Commit 4b15fb7 "fix(ci/windows): suppress cosmetic sweep() warning in test-pilar8-no-edge.R:42" exists in `git rev-list v3.10.0..HEAD`, confirming the blamed warning was already suppressed. README.md:1672 "**109+ unit and integration tests**" confirmed self-contradictory with the 1345 badge.

**Action**

> Pick one measured quantity and state the environment with it, e.g. "460 test_that blocks / 1089 expectations; 1022 pass + 109 skipped without torch/dagitty/bnlearn/dbarts (R 4.6.1 aarch64-darwin)". Regenerate the README.md:12 badge from that number, delete or correct the contradictory README.md:1672 "109+", fix the +7/+20 arithmetic at NEWS.md:242 and NEWS.md:195, and rewrite cran-comments.md:30-35 to report the true skip count and the true warning source (test-pilar7-bhs-edge.R:61, not Pilar 8 sweep).

#### F7DC6A4 — The README's only install command pins a git ref that does not exist (`@v2.8.0`)

`Release consistency` · bug · high · effort: minutes · verdict: **CONFIRMED**

**Evidence**

> README.md:339-340: `remotes::install_github("HugoMachadoRodrigues/edaphos@v2.8.0", build_vignettes = TRUE)`. `git rev-parse -q --verify v2.8.0` -> not found (see the tag list: tags stop at v1.6.0 then jump to v3.10.0). This is the sole install instruction in the 84 KB README (`grep -rn install_github` over the repo returns only README.md:339 and Dockerfile:67). Cross-check: NEWS.md:805 documents a `# edaphos 2.8.0` release and the roadmap row README.md:1713 marks v2.8.0 as shipped -- so the pin is not a typo, it points at a release the project believes it made but never tagged.

**Impact**

> Every new user's first command fails with `Error: Failed to install 'edaphos' from GitHub: reference 'v2.8.0' not found`. The package is effectively uninstallable by its documented path. It also silently pins users two major-minor arcs behind (2.8.0 vs 3.10.0) even if the tag were created.

**Action**

> Change README.md:339 to install the current release (`edaphos@v3.10.0`, once #2 is resolved) or drop the pin entirely (`install_github("HugoMachadoRodrigues/edaphos", build_vignettes = TRUE)`). Add a CI step or a pre-release checklist item that greps README.md for `@v[0-9]` and verifies the ref resolves.

#### FA01BFB — CITATION.cff assigns the identical DOI 10.5281/zenodo.19710162 to twelve different "Version DOI" entries

`Release consistency` · bug · high · effort: minutes · verdict: **CONFIRMED**

**Evidence**

> CITATION.cff:122-157 declares `type: doi, value: "10.5281/zenodo.19710162"` twelve times, labelled "Version DOI (v1.6.0)", "(v1.7.0)", "(v1.7.1)", "(v1.7.2)", "(v1.8.0)", "(v1.8.1)", "(v1.8.2)", "(v1.9.0)", "(v1.9.1)", "(v1.9.2)", "(v2.0.0)", "(v2.1.0)". Only two distinct DOIs appear besides it: :118 concept DOI 10.5281/zenodo.19683708 and :121 "Version DOI (v1.5.0)" 10.5281/zenodo.19709560. Zenodo mints a unique version DOI per deposit, so a single id cannot be the version DOI of twelve versions -- meaning eleven of these entries are fabricated, and (consistent with #2) no Zenodo deposit was ever made for v1.7.0 onward.

**Impact**

> Anyone resolving 10.5281/zenodo.19710162 expecting v2.1.0 lands on whatever single record it actually is (v1.6.0/v1.7.0-era at best). The identifiers block makes the archival record look complete when eleven of thirteen versions were never archived. This is exactly the kind of provenance defect an rOpenSci reviewer or a journal data-availability check catches.

**Action**

> Delete the eleven duplicate entries at CITATION.cff:125-157, keeping only DOIs that resolve (:118 concept, :121 v1.5.0, and whichever single record 19710162 really is, correctly labelled). Add real version DOIs only after each Zenodo deposit is actually published -- which per RELEASE-CHECKLIST-v3.10.0.md:51-71 has not happened for v3.10.0.

#### FBAF1FD — DESCRIPTION promises ten research pillars; every document shipped in the CRAN tarball documents six, and pillars 7-10 have no roadmap row, no README section and no vignette

`Roadmap promises` · doc-gap · high · effort: days · verdict: **CONFIRMED**

**Evidence**

> DESCRIPTION:8-25 enumerates ten pillars. Against that: `R/pillars_roadmap.R:1` is titled "Roadmap and status of the six pillars of edaphos" and its table (lines 8-15) has exactly 6 rows; the generated `man/edaphos-roadmap.Rd:5` inherits that title. `R/edaphos-package.R:10,14` say "**six research pillars**" / `@section Six research pillars:`, rendered into `man/edaphos-package.Rd:13,20`. README.md:371 heading is `## The six pillars at a glance` and its table has 6 pillar rows plus 2 non-pillar rows; there is no `## Pillar 7/8/9/10` section (README pillar headings stop at :1288 `## Pillar 6 — Quantum ML`). `vignettes/` contains pilar1..pilar6 Rmd files only — no pilar7/8/9/10 vignette. README.md:10 badge reads `pillars-10%2F10%20shipped` and links to `#the-six-pillars-at-a-glance`. What DOES cover 7-10: `_pkgdown.yml:161-180` (four reference groups), `cheatsheets/pilar7.md`..`pilar10.md`, `vignettes/getting-started.Rmd:135-183`, `INTRO.md:42-59`, and man pages `bhs_fit.Rd`, `no_fno_fit.Rd`, `no_deeponet_fit.Rd`, `dm_fit.Rd`, `dm_sample.Rd`, `gnn_build_graph.Rd`, `gnn_fit.Rd`. Note `.Rbuildignore` excludes `^cheatsheets$`, `^INTRO\.md$`, `^_pkgdown\.yml$` — so of the artifacts covering 7-10, only getting-started.Rmd and the .Rd pages reach a CRAN user.

**Impact**

> A CRAN reviewer reading DESCRIPTION then `?edaphos-package` or `?edaphos-roadmap` sees a direct contradiction (ten vs six) inside the tarball itself — a likely rOpenSci/CRAN comment. Users of pillars 7-10 get man pages with no narrative: no derivation vignette in the style promised at README.md:384-388 ("one or more vignettes deriving the object from first principles"), and no status/governing-object row in the roadmap landing page the docs designate as the API entry point.

**Action**

> Four concrete gaps to close: (1) add rows 7-10 to the `R/pillars_roadmap.R` table and retitle to "ten pillars", then re-roxygenise; (2) change `R/edaphos-package.R:10,14` to ten and add \item blocks for pillars 7-10 mirroring the existing 1-6; (3) add `## Pillar 7`..`## Pillar 10` sections to README.md after :1288 and expand the at-a-glance table to 10 rows (also fix the anchor in the badge at :10); (4) promote at least `cheatsheets/pilar7.md`-`pilar10.md` content into real vignettes, or explicitly state in the roadmap that 7-10 are documented via cheatsheets + getting-started only.

#### F1CD43E — R² is floored at zero in three benchmark code paths, censoring negative values and turning them into a "statistically indistinguishable" conclusion

`Scientific reproducibility` · bug · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> Three sites clip R² before it is averaged across folds and published:
> ```
> R/quantum_foundation.R:279            r2 = max(0, 1 - sum(err^2, na.rm = TRUE) / ...)
> data-raw/benchmark_wosis_p4_p5_p7.R:244  r2_val <- max(0, 1 - mean((point_pred - truth)^2, ...) / mean((truth - mean(truth))^2))
> data-raw/benchmark_wosis_6pilar.R:157   r2_val <- max(0, 1 - ...)
> ```
> Effects visible in shipped artefacts and README:
> - `inst/extdata/quantum_foundation_cerrado.rds$cv_table$r2` is exactly `0` for "RBF-KRR on foundation PCs", "Quantum KRR on raw covariates" and "Quantum KRR on foundation PCs" in **every** fold; `cv_summary$r2_mean` = 0, 0, 0, 0.0807.
> - `README.md:1406-1411` publishes "R² 0.00" for three methods and concludes "The four regressors are **statistically indistinguishable** on this benchmark."
> - `inst/extdata/benchmark_wosis_6pilar.rds$cv_aggregate` shows `r2_mean` exactly `0.00000000` for P6 Quantum KRR and P10 GAT ensemble, reproduced in `NEWS.md:427-428`.
> 
> Because the clip is applied per fold before averaging, even a method with mildly positive mean R² has its cross-fold average biased upward, and a method that is systematically worse than the intercept-only model is indistinguishable from one that exactly matches it.

**Impact**

> A method that predicts worse than the training mean is published as "R² = 0.00", identical to a method that ties it. This directly underwrites the README's "statistically indistinguishable" and "matches but does not surpass ranger" conclusions and the NEWS "RMSE is a flat band" reading — conclusions drawn from a censored metric. Any reviewer recomputing R² from the stored predictions gets negative values that the package never reports.

**Action**

> Remove `max(0, ...)` from all three sites and let R² go negative; a negative R² is the informative result. Re-run `data-raw/benchmark_wosis_p4_p5_p7.R`, `data-raw/benchmark_wosis_6pilar.R` and the quantum benchmark, and update `README.md:1406-1411`, `NEWS.md:601-608` and `NEWS.md:421-428`. Add a unit test that `benchmark`-family R² is not clipped (e.g. feed a constant predictor worse than the mean and assert the returned R² < 0).

#### F30D53B — The v1.8.0 multi-backend LLM benchmark is entirely simulated and its headline F1/latency values are hard-coded function arguments

`Scientific reproducibility` · bug · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> `README.md:668-695` presents "### v1.8.0 — Multi-backend LLM extraction benchmark ... **The first quantitative validation** of the Gemma 4 extractor" with a table of Precision / Recall / F1 / Cost / "Latency (median)" for Gemma 4, GPT-4o-mini and Claude Sonnet-4.5, followed by "**Key findings.**"
> 
> The shipped artefact `inst/extdata/llm_benchmark_results.rds` has `mode = "simulated"` and `version = 1.7.2` (`date_computed = 2026-04-23`, i.e. predating the v1.8.0 release it documents). No API was ever called.
> 
> The reported values are inputs, not measurements. `data-raw/llm_benchmark_run.R`:
> ```
> 128:  sim_args = list(recall = 0.80, precision_target = 0.85, ... latency_mean = 15.2, latency_sd = 4.1)   # Gemma 4
> 142:  sim_args = list(recall = 0.88, precision_target = 0.80, ... latency_mean = 3.1,  latency_sd = 0.8)   # GPT-4o-mini
> 156:  sim_args = list(recall = 0.84, precision_target = 0.90, ... latency_mean = 5.7,  latency_sd = 1.4)   # Claude
> ```
> and `R/llm_benchmark.R:327-338` shows `llm_benchmark_simulate(gold, recall = 0.82, precision_target = 0.86, ...)` derives false positives analytically from `precision_target`.
> 
> Each README "key finding" is therefore a restatement of an author-chosen constant:
> - "**Claude has the best F1** (0.82)" ← Claude has the highest `precision_target` (0.90) by construction.
> - "**GPT-4o-mini is the fastest** (2.8 s vs. 5.4 s vs. 16 s median latency per abstract)" ← `latency_mean = 3.1 / 5.7 / 15.2`; the seconds are draws from `rnorm`, not wall-clock timings.
> - "**Backends disagree strongly on which abstracts to extract** (κ ≈ −0.08 to 0.12 pairwise), which means ... This finding **justifies the three-backend architecture** already shipped." ← false positives are drawn iid per backend from a shared `noise_pool` (`R/llm_benchmark.R:353-361`), so near-zero pairwise κ is a mathematical necessity of the simulator, not an empirical discovery.
> 
> The disclosure at `README.md:697-700` ("runs reproducibly in CI using `llm_benchmark_simulate()`") appears *after* the table and does not retract the "Key findings".

**Impact**

> An architecture decision ("justifies the three-backend architecture") and a cost/quality tradeoff recommendation ("switching from Claude to Gemma 4 saves ~$37.50 at the cost of 11 F1-points") are presented as empirical results derived from a simulator whose per-backend parameters the author selected. Vendor-attributed performance numbers for three named commercial products, published in a citable package, are fabricated in the technical sense that no measurement was taken. This is the single highest-reputational-risk item in the repository.

**Verification correction**

> Verified end to end: inst/extdata/llm_benchmark_results.rds has `mode = "simulated"`, `version = 1.7.2`, `date_computed = 2026-04-23 16:52:56` (predating the v1.8.0 release it documents); data-raw/llm_benchmark_run.R:128/:142/:156 carry the hard-coded `sim_args` exactly as quoted (latency_mean 15.2 / 3.1 / 5.7; precision_target 0.85 / 0.80 / 0.90); R/llm_benchmark.R:334-338 derives false positives analytically from `precision_target`, and :351-361 draws them iid from a shared 17-token `noise_pool`, so near-zero pairwise kappa is structural — the shipped `kappa_matrix` off-diagonals (-0.0811, 0.1216) match README's "κ ≈ −0.08 to 0.12" precisely. Two refinements: the tabulated P/R/F1 are simulator *outputs*, not the literal inputs (Claude prints precision 0.82 against a precision_target of 0.90), so "the reported values are inputs" overstates slightly; and README.md:697-700 does disclose the simulation — but four lines BELOW the table, framed as "runs reproducibly in CI", and without retracting "The first quantitative validation" or any of the "Key findings". Vendor-attributed numbers for three named commercial products remain unmeasured.

**Action**

> Either (a) run the real benchmark once with `EDAPHOS_USE_REAL_LLM=1`, commit the resulting `mode = "real"` bundle, and report those numbers; or (b) if a real run is out of scope, delete the vendor-named table from `README.md:676-695` entirely and replace it with a statement that the harness is validated on a deterministic simulator and carries no empirical vendor comparison. Do not keep vendor-attributed P/R/F1/latency figures sourced from `sim_args`. Add a guard in `data-raw/llm_benchmark_run.R` that refuses to write to `inst/extdata/` when `USE_REAL` is FALSE, or writes to a `*_simulated.rds` filename.

#### F485937 — No test validates any headline number or any of the twelve committed result bundles

`Scientific reproducibility` · process-gap · high · effort: days · verdict: **PARTIALLY_TRUE**

**Evidence**

> A grep for the published figures across the whole suite returns nothing: `grep -rn "13\.51|14\.07|13\.86|0\.2188|1095" tests/testthat/` matches only a comment (`tests/testthat/test-benchmark-6pilar.R:4`, "the full 1 095-profile run lives in") and an unrelated confidence value (`test-llm-annotation.R:95`).
> 
> Exactly **one** of 69 test files reads anything from `inst/extdata/`: `tests/testthat/test-llm-annotation.R:111` (`system.file("extdata", "cerrado_gold_standard_v1.jsonl", ...)`), and only to parse the gold-standard JSONL. None of the twelve `.rds` result bundles — `case_cerrado_results.rds`, `causal_cerrado_real.rds`, `causal_iv_cerrado_real.rds`, `benchmark_wosis_6pilar.rds`, `quantum_foundation_cerrado.rds`, `llm_benchmark_results.rds`, and the rest — is opened by any test.
> 
> The consequence is demonstrable: the Sargan sign-flip (README 0.343 ✅ vs bundle 3.2e-08) survived commit `05cb516 feat(v1.9.3): close roadmap promise -- IV refit with real 31-channel ... stack`, whose entire purpose was to refit that analysis. Likewise every β in `README.md:632-636` drifted from `causal_cerrado_real.rds` undetected across ~30 releases. Meanwhile `NEWS.md:357` claims "1 269 tests pass" and `cran-comments.md:5` claims "0 errors / 0 warnings / 0 notes", so the suite's green status is actively reassuring about claims it never checks.

**Impact**

> For a package whose product is its claims, the test suite covers the code but not the science. 1022 passing expectations provide no protection against the exact failure mode that has already occurred three times (IV Sargan, causal β table, LLM benchmark mode). Any future refit will silently desynchronise the README again.

**Verification correction**

> Core claims CONFIRMED: only tests/testthat/test-llm-annotation.R:111 reads inst/extdata (the gold-standard JSONL); no .rds bundle is opened by any test; the headline-number grep hits only the comment at test-benchmark-6pilar.R:4; NEWS.md:357 "1 269 tests pass" and cran-comments.md:5 "0/0/0"; the Sargan divergence is real (README.md:852 "0.343 ✅" vs causal_iv_cerrado_real.rds benchmark_table$sargan_p[2] = 3.22e-08). One detail is wrong: there is no 0.2188 or "1095" match at test-llm-annotation.R:95 -- the grep returns exactly one hit repo-wide in tests/, the comment at test-benchmark-6pilar.R:4.

**Action**

> Add `tests/testthat/test-headline-claims.R` that loads each `inst/extdata/*.rds` and asserts the values quoted in `README.md` and `NEWS.md` to the published precision — Sargan p-values, the six causal β, the 6-pillar RMSE/R²/PICP/CRPS aggregate, the case-study RMSE/MAE/R²/PICP, and `mode == "real"` for `llm_benchmark_results.rds`. Also assert artefact provenance: `as.character(r$version) == "3.10.0"` (or an explicit allow-list of intentionally frozen artefacts) so staleness surfaces as a test failure. Best of all, generate the README tables from the bundles via `README.Rmd` so drift becomes structurally impossible.

#### F623876 — `.bench_inject_aleatoric()` manufactures the published PICP with author-chosen noise and silently degrades the published RMSE

`Scientific reproducibility` · bug · high · effort: days · verdict: **CONFIRMED**

**Evidence**

> `R/benchmark_wosis.R:24-41` documents the intent explicitly: "v3.4.0 adds the missing ALEATORIC term: an estimate of the in-sample residual standard deviation `sigma_resid` is injected as iid Gaussian noise on every (sample, test-row) entry of the posterior matrix ... **PICP at the v3.1.0 head-to-head settings moves from ~0.20 to ~0.85, matching P4/P5/P7.**"
> 
> ```r
> 35: .bench_inject_aleatoric <- function(pred_mat, sigma_resid, seed = NULL) {
> 37:   if (!is.null(seed)) set.seed(seed + 13579L)
> 38:   noise <- matrix(stats::rnorm(length(pred_mat), 0, sigma_resid), nrow(pred_mat), ncol(pred_mat))
> 40:   pred_mat + noise
> ```
> Called at `:126` (P1), `:184` (P6), `:254` (P10). `sigma_resid` comes from `.bench_residual_sd()` (`:47-52`) applied to **in-sample training** residuals.
> 
> Two distinct defects:
> 
> **(a) Coverage is set, not measured.** `NEWS.md:384-389` reports PICP_90 jumping "to nominal coverage": P1 0.232→0.953, P6 0.249→0.601, P10 0.073→0.825. `NEWS.md:430-433` concedes "P1 PICP is now mildly OVER-covered (0.95 vs nominal 0.90) because the OLS residual SD is computed in-sample without a leave-one-out adjustment". The published PICP is therefore a function of an undisclosed estimator choice, not a property of the model.
> 
> **(b) The injected noise corrupts the point predictions and thus RMSE/R².** Point predictions are `colMeans(post$samples)` (`data-raw/benchmark_wosis_6pilar.R:153`). Averaging `n` rows of injected noise leaves a residual offset of sd `sigma_resid/sqrt(n)`. Verified against the shipped bundle: `inst/extdata/benchmark_wosis_6pilar.rds$posterior_bank[[6]]$p1$metadata$sigma_resid = 15.196`. With `n_ensemble = 8L` for P10 (`data-raw/benchmark_wosis_6pilar.R:124`), the injected error is ≈15.2/√8 ≈ 5.4 g/kg — and the bundle's `cv_aggregate` shows **P10 RMSE = 15.199** against `NEWS.md:605`'s pre-injection **14.07** (sqrt(14.07² + 5.66²) = 15.17 ✓). P1, with `n_boot = 300L`, moves only 13.94 → 13.92 as predicted (15.2/√300 = 0.88). P10's R² is driven to exactly 0.000 and it drops from rank 3 to rank 6 in the re-sorted table (`NEWS.md:421-428`), with `NEWS.md:391-395` advertising only "CRPS also improves materially across the board" and no mention of the RMSE regression it caused.

**Impact**

> Three of the six methods in the package's 6-pillar head-to-head have their calibration metric manufactured and their accuracy metric degraded by a fixed-seed noise draw. A reader comparing PICP across the six methods is comparing a real QRF quantile grid (P4/P5) against three numbers tuned to sit near 0.90. The reported P10 RMSE of 15.20 is 8% worse than the model's actual out-of-sample error purely because of the injection, which materially changes the ranking that `data-raw/benchmark_wosis_6pilar.R:194` (`arrange(rmse_mean)`) presents.

**Verification correction**

> none — verified end to end. R/benchmark_wosis.R:24-34 states the intent and the 0.20→0.85 target verbatim; :35-41 is the injector; call sites are :126 (P1), :184 (P6), :254 (P10); `.bench_residual_sd` at :47-52 is applied to in-sample fits (`stats::fitted(full_lm)` at :125). NEWS.md:386-389 reports PICP 0.232→0.953 / 0.249→0.601 / 0.073→0.825 and NEWS.md:430-433 concedes the in-sample no-LOO estimator. The RMSE corruption is arithmetically confirmed against the shipped bundle: `posterior_bank[[6]]$p1$metadata$sigma_resid` = 15.19607, `cv_aggregate` gives P10 rmse_mean = 15.19945 against NEWS.md:605's pre-injection 14.07, and sqrt(15.199² − 14.07²) = 5.75 ≈ sigma_resid/sqrt(n_ensemble=8) (data-raw/benchmark_wosis_6pilar.R:124), exactly the predicted colMeans residual offset; P1 with n_boot = 300L (:97) moves only 13.94→13.92 as predicted. P10's R² is 0.000 and it falls from rank 3 (NEWS.md:605-607, tied 14.07) to rank 6 in the re-sorted v3.4.0 table. NEWS.md:391-395 advertises only the CRPS gains; the RMSE regression appears in the :421-428 table but is never named. Severity honest: this is the package's own head-to-head, three of six methods affected, and it changes the ranking that data-raw/benchmark_wosis_6pilar.R:194 presents.

**Action**

> Stop mutating the posterior samples. Instead (1) estimate the aleatoric term out-of-sample — CV residuals or a leave-one-out/OOB adjustment, not `stats::sd` of in-bag residuals; (2) widen the *intervals* analytically (convolve the epistemic spread with the aleatoric variance when computing PICP/MPIW/CRPS) so the point prediction is untouched and RMSE/R² are unaffected; (3) report both the epistemic-only and total-uncertainty PICP side by side; (4) in `NEWS.md:415-433` disclose the P10 RMSE regression from 14.07 to 15.18 as a consequence of the change rather than presenting only the CRPS improvement.

#### FF375C1 — The P4 "Foundation" row of the headline "first honest cross-pillar comparison" is computed on a pure Gaussian-noise raster

`Scientific reproducibility` · bug · high · effort: days · verdict: **CONFIRMED**

**Evidence**

> `README.md:243-255` heads the section "**v2.8.0 — Real head-to-head benchmark on 1 095 WoSIS profiles.** First honest cross-pillar comparison" and reports `P4 Foundation+QRF | 14.1 | 0.034 | **0.889** | 37.6 | 5.93`, concluding "P4 best-calibrated at 0.89 ≈ nominal 0.90".
> 
> The covariate stack the MoCo encoder is run over is `rnorm()`. `data-raw/benchmark_wosis_p4_p5_p7.R:160-169`:
> ```r
> 166: terra::values(tpl) <- stats::rnorm(terra::ncell(tpl))
> 167: stk <- terra::rast(replicate(moco$n_channels, tpl, simplify = FALSE))
> 168: for (k in seq_len(moco$n_channels))
> 169:   terra::values(stk[[k]]) <- stats::rnorm(terra::ncell(stk))
> ```
> with `dataset_meta` normalisation also placeholder (`means = rep(0, ...), sds = rep(1, ...)`, lines 154-157). The "foundation-model embedding" therefore carries zero information about location; the P4 row is P5's QRF plus 64 columns of noise.
> 
> Two further undisclosed asymmetries in the same script:
> - `:208` `train_bhs <- if (n_tr > 300L) train[sample(n_tr, 300L), ] else train` — P7 BHS is fit on **300** training rows while P4 and P5 get all ~876. `README.md:250` credits P7 with the best R² and MPIW without noting it saw a third of the data.
> - `:139-144` P7's "MCMC posterior" is discarded and replaced by `stats::rnorm(200L, pr$mean[j], pr$sd[j])` — a Gaussian re-simulation of a summary. P7's CRPS and PICP measure that Gaussian approximation, not the Gibbs posterior.
> 
> The honest counterpart exists and is correctly labelled: `README.md:1404` marks the quantum table "(synthetic-stack mode)" and `README.md:1413` says "Under synthetic embeddings (random Gaussian rasters)". The v2.8.0 section carries no such caveat.

**Impact**

> The result advertised as the package's "first honest cross-pillar comparison" attributes a calibration win to a foundation model that was fed noise, and awards R²/MPIW honours to a method trained on 34% of the data whose posterior was replaced by a Gaussian. Because `data-raw/benchmark_wosis_6pilar.R:59-62,179,210` reuses this bundle wholesale for the P4/P5/P7 rows, the defect propagates into the 6-pillar table in `NEWS.md:601-608` and `NEWS.md:421-428` and into `inst/extdata/benchmark_wosis_6pilar.rds`.

**Verification correction**

> none — every cited line verified in data-raw/benchmark_wosis_p4_p5_p7.R: the template raster is filled with `stats::rnorm(terra::ncell(tpl))` and every one of the 31 encoder channels is overwritten with `stats::rnorm` in the following loop (the script's own message even prints "synthetic stack"); `dataset_meta` normalisation is `means = rep(0, ...), sds = rep(1, ...)`; `train_bhs <- if (n_tr > 300L) train[sample(n_tr, 300L), ] else train` caps P7 at 300 rows while P4/P5 get the full training fold; and the P7 "posterior" is rebuilt as `stats::rnorm(200L, pr$mean[j], pr$sd[j])`. README.md:243-255 carries no caveat, in direct contrast to README.md:1404/:1413 which does label the quantum table "(synthetic-stack mode)" / "random Gaussian rasters". The propagation into the 6-pillar table is consistent with the shipped benchmark_wosis_6pilar.rds reusing the same P4/P5/P7 rows.

**Action**

> Either supply the real 31-channel Cerrado stack (the same one `data-raw/causal_iv_benchmark_real.R` builds via `foundation_build_cerrado_stack()`) with correct per-channel normalisation, or drop the P4 row and state that Pillar 4 is not benchmarkable without the raster download. Equalise P7's training set with P4/P5 or disclose the 300-row cap in every table caption. Replace the `rnorm(200, mean, sd)` reconstruction at `:139-144` with the actual Gibbs draws from `bhs_fit`. Add a "synthetic-stack mode" caveat to `README.md:243-255` matching the one already at `README.md:1404`.

#### F10D9DC — edaphos-cerrado-moco-v2 ships as an all-NA placeholder row in the exported public registry, keyed to a nonexistent package version 3.11.0

`Incomplete implementations` · incomplete-implementation · high · effort: minutes · verdict: **CONFIRMED**

**Evidence**

> R/foundation_weights.R:48-85, row 2 of the data frame returned by the exported `foundation_weights_list()` (R/foundation_weights.R:104-106):
> - line 67: `NA_character_           # filled after the user's Zenodo upload` (url)
> - line 71: `NA_character_           # filled by tools/pretrain/package_v2_for_zenodo.R` (sha256)
> - line 75: `NA_character_           # filled after the user's Zenodo upload` (doi)
> - line 80: `NA_character_` (published_at)
> - line 82: `edaphos_version = c("1.2.0", "3.11.0")`
> The description at line 55 is written in the future tense about its own training: "Final InfoNCE loss **expected** ~0.4 at step 200000". DESCRIPTION:3 says `Version: 3.10.0`; there is no `# edaphos 3.11.0` section in NEWS.md. The same phantom version is baked into shipped documentation: R/foundation_embed_coords.R:186 ("As of v3.11.0"), :204 ("the v3.11.0 rewrite closes that gap"), :220, propagated to man/foundation_build_cerrado_stack.Rd:31,39,58.

**Impact**

> `foundation_weights_list()` is an exported catalogue documented (R/foundation_weights.R:87-100) as describing "every pretrained encoder published by the `edaphos` project". Half its rows describe an artefact that does not exist, with a `license = "CC-BY-4.0"` and a full hyperparameter spec that make it look publishable. Users reading the table, or scripting over it, cannot distinguish published from aspirational except by NA-checking four columns. The `edaphos_version = "3.11.0"` column tells a user the weights need a package release that is not on CRAN, GitHub, or in NEWS.

**Action**

> Either (a) drop the v2 row from `.foundation_weights_registry()` until the Zenodo deposit exists and re-add it in the release that publishes it, or (b) add an explicit `status` column (`"published"` / `"pending"`) so the placeholder is machine-readable, document it in the `@return` block at R/foundation_weights.R:100, and change `edaphos_version` to the version that will actually ship it. Separately, replace the v3.11.0 references in R/foundation_embed_coords.R:186,204,220 with 3.10.0 and re-roxygenise so man/foundation_build_cerrado_stack.Rd stops advertising a nonexistent release.

#### F873468 — foundation_build_cerrado_stack() silently writes a truncated stack to the cache when any geodata fetch fails, then reuses it forever

`Incomplete implementations` · bug · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> R/foundation_embed_coords.R. Each of the five source fetches swallows its error into `NULL` with a `message()` (not a `warning()`), so nothing is signalled to the caller: lines 264-269 (SoilGrids loop over 5 vars), 281-285 (WorldClim prec, 12 layers), 297-301 (WorldClim tavg, 12 layers), 313-317 (bio fallback), 329-339 (SRTM elev, with a nested fallback). Each is followed by `if (!is.null(x)) { layers$... <- ... }`. The ONLY completeness check is at lines 359-361:
> ```r
> if (length(layers) == 0L)
>   stop("No layers could be built. Check network + geodata cache.", call. = FALSE)
> ```
> There is no assertion that `schema == "v1_encoder"` produced 31 layers. The result is then written to the schema-keyed cache path at line 366 (`terra::writeRaster(stk, stack_path, overwrite = TRUE)`), and lines 243-247 short-circuit every later call:
> ```r
> if (!force && file.exists(stack_path)) {
>   message(sprintf("  Using cached stack: %s", stack_path))
>   return(terra::rast(stack_path))
> }
> ```
> The documented contract is explicit about the count -- R/foundation_embed_coords.R:186-198 promises exactly "5 SoilGrids + 12 monthly prec + 12 monthly tavg + 2 SRTM" = 31 layers, matched to the 31-channel `edaphos-cerrado-moco-v1` encoder (R/foundation_weights.R:57).

**Impact**

> A transient WorldClim outage during the first call yields a 7-layer stack (5 SoilGrids + 2 SRTM) cached under the filename `cerrado_stack_v1_encoder_<hash>.tif`, which claims to be the v1_encoder schema. Every subsequent call returns that poisoned cache with only an informational "Using cached stack" message -- `force = TRUE` is the only escape and the user has no signal they need it. Feeding it to the 31-channel v1 encoder produces a torch conv2d channel-mismatch error far from the cause; feeding it to any user code that indexes layers positionally silently reads the wrong covariate. The docstring at :202-204 says this rewrite exists specifically to stop the IV benchmark falling back to a synthetic stack, so a silently-truncated real stack is the exact failure mode it was built to prevent.

**Action**

> After line 361 in R/foundation_embed_coords.R, assert the schema's channel count before writing: `expected <- if (schema == "v1_encoder") 31L else 10L; if (terra::nlyr(stk) != expected) stop(sprintf("schema '%s' expects %d layers but only %d could be fetched (%s). Re-run when the sources are reachable.", schema, expected, terra::nlyr(stk), paste(names(layers), collapse=", ")))`. Also convert the five `message("      [warn] ", ...)` calls to `warning(...)` so partial failures are visible to `withCallingHandlers` and to test suites, and validate `terra::nlyr()` on the cache-hit path at line 245 before returning.

#### F9E2C74 — qf_krr_benchmark() clamps R-squared at zero, contradicting the package's own edaphos_r2() and hiding worse-than-mean quantum models

`Incomplete implementations` · inconsistency · high · effort: minutes · verdict: **CONFIRMED**

**Evidence**

> R/quantum_foundation.R:274-283, the local `metrics()` helper used for every row of the benchmark table:
> ```r
> r2     = max(0, 1 - sum(err^2, na.rm = TRUE) /
>                     sum((truth - mean(truth, na.rm = TRUE))^2)),
> ```
> The package's canonical metric does the opposite -- R/edaphos_metrics.R:63-69 returns the unclamped value, guarding only the degenerate case:
> ```r
> edaphos_r2 <- function(observed, predicted) {
>   ...
>   if (ss_tot == 0) return(NA_real_)
>   1 - ss_res / ss_tot
> }
> ```
> and documents itself at R/edaphos_metrics.R:7-10 as "Nash-Sutcliffe efficiency when the mean is the trivial model" -- a quantity whose whole diagnostic value is that it goes negative. `grep -rn "max(0, 1 -" R/*.R` returns exactly one hit, R/quantum_foundation.R:279, so this is a lone deviation, not a house style.

**Impact**

> `qf_krr_benchmark()` is documented (R/quantum_foundation.R:247-250) as giving "an empirical answer" to whether the quantum-foundation hybrid beats its ancestors, and it tabulates the quantum KRR head-to-head against a ranger baseline. Clamping at 0 means a quantum model with true R-squared of -0.4 (materially worse than predicting the mean) is reported as 0.00, indistinguishable from a model that merely explains nothing. The clamp applies to every row including the baselines, so it compresses exactly the region where the comparison would be most informative. This directly undercuts the "Honestly benchmarked" claim the package makes about its Pillar 4/6 comparisons (R/pillars_roadmap.R:13).

**Verification correction**

> Confirmed and stronger than argued. R/quantum_foundation.R:279 `r2 = max(0, 1 - ...)` is the only `max(0, 1 -` in R/; edaphos_r2 (R/edaphos_metrics.R:63-70) is unclamped and its header at :7-10 documents it as Nash-Sutcliffe. New evidence the auditor did not have: the clamp demonstrably fired in the SHIPPED bundle. `inst/extdata/quantum_foundation_cerrado.rds$cv_table` has `r2 == 0.00000000` in 9 of the 12 rows I inspected — in fold 2, RBF-KRR (RMSE 9.57) and ranger (RMSE 13.51) both report 0.00 despite a 4 g/kg RMSE gap, i.e. the clamp erased a real ordering. That bundle is what README.md:1406-1411 prints (0.00 for three of four methods) under the conclusion "The four regressors are statistically indistinguishable on this benchmark" — a conclusion the clamp manufactures.

**Action**

> Replace the inline computation at R/quantum_foundation.R:277-281 with calls to the existing `edaphos_rmse()` / `edaphos_mae()` / `edaphos_r2()` so the benchmark shares one metric definition with the rest of the package, removing the `max(0, ...)`. Add a test asserting that a deliberately bad predictor yields a negative `r2` in the returned data frame.

#### F60AE85 — bhs_fit has no rank check on the model matrix: a constant covariate yields NA rgamma rates (the 2 live WARNINGs) then a cryptic Cholesky death

`Test coverage` · bug · high · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> Reproduced standalone (no package load) for n=30, X = cbind(1, rep(1,30)): `qr(X)$rank = 1` vs `p = 2`; `stats::lm.fit(X,y)$coefficients` = c(0.1327746, NA). R/pilar7_bayesian_hierarchical.R:238 uses exactly that as the Gibbs initial value: `beta <- as.numeric(stats::lm.fit(X, y)$coefficients)`. The NA propagates: :288 `rhs_w <- (y - as.numeric(X %*% beta)) / tau2` -> all NA -> :302 `rate_s` NA -> :303 `sigma2 <- 1/stats::rgamma(1, shape=shape_s, rate=NA)` emits WARNING "NAs produced" and returns NaN; :308-309 does the same for tau2 -> WARNING #2. Exactly two warnings, matching the live run at tests/testthat/test-pilar7-bhs-edge.R:61. On iteration 2 `prec_w` is all-NaN, the 8-step jitter ladder in `.chol_jitter` (:243-254) fails every try, and the final fallback `chol(M + diag(1e-2 * mean(diag(M))))` errors with "the leading minor of order 1 is not positive" (verified). The test at test-pilar7-bhs-edge.R:57-69 swallows this with `tryCatch(..., error = function(e) NULL)` at :61-66 and then asserts the tautology `expect_true(is.null(fit) || inherits(fit, "edaphos_bhs"))` at :68 -- satisfied by both branches, so it can never fail. Also note bhs_fit's own validation (:90-106) checks data/formula/coords types and the MCMC schedule but never the rank of X. R/core_utils.R already ships `.stopf` / `.assert_type` for exactly this.

**Impact**

> Any user whose design matrix is rank-deficient (a constant covariate, a perfectly collinear pair, a one-level factor after NA dropping) gets 'NAs produced' followed by 'the leading minor of order 1 is not positive' -- with no indication which column is at fault -- from the Pillar 7 flagship sampler. The only test covering the case is a tautology, so the suite records it as passing while emitting the warnings that R CMD check will surface.

**Verification correction**

> Mechanism and every behavioural claim CONFIRMED: R/pilar7_bayesian_hierarchical.R:238 seeds beta from stats::lm.fit (NA on rank-deficient X), the NA reaches rate_s at :302 -> rgamma at :303 and rate_t at :308 -> :309 (exactly the 2 live warnings), validation at :90-106 never checks rank(X), and test-pilar7-bhs-edge.R:57-69 is a tautology (`expect_true(is.null(fit) || inherits(fit, "edaphos_bhs"))` at :68). Two line references are wrong: `rhs_w <- (y - as.numeric(X %*% beta)) / tau2` is at :283, not :288 (:288 is the w_cur draw); `.chol_jitter` is defined at :246-256 with the heavy-ridge fallback at :255, not :243-254. The tryCatch spans :61-65, not :61-66.

**Action**

> In R/pilar7_bayesian_hierarchical.R after line 130 (`n <- length(y); p <- ncol(X)`) add a rank guard using the existing helper: `if (qr(X)$rank < p) .stopf("design matrix is rank-deficient (rank %d < %d columns).", qr(X)$rank, p, hint = "Drop constant or collinear covariates; aliased column(s): ...")`, naming the aliased columns from `colnames(X)[is.na(stats::lm.fit(X,y)$coefficients)]`. Then rewrite tests/testthat/test-pilar7-bhs-edge.R:57-69 as `expect_error(bhs_fit(...), "rank-deficient")` and wrap it in `expect_no_warning()` so the 2 'NAs produced' warnings become a regression signal instead of noise.

#### F64B0F0 — R/foundation_finetune.R:41 makes the whole Pillar-4 fine-tuning API require `reticulate`, which it never uses

`Test coverage` · bug · high · effort: minutes · verdict: **CONFIRMED**

**Evidence**

> R/foundation_finetune.R:40-46: `.ft_require_torch <- function() { if (!requireNamespace("reticulate", quietly = TRUE) || !requireNamespace("torch", quietly = TRUE)) stop("Install the `torch` package (and its MPS / CUDA backend) to use the fine-tuning API.", call. = FALSE) }`. Line 41 is the ONLY occurrence of the string `reticulate` in the entire 646-line file (`grep -n reticulate R/foundation_finetune.R` -> single hit). The four call sites are the four public entry points: foundation_fit_classifier (guard at :247, defined :233), predict.edaphos_foundation_classifier (:401 / :397), foundation_fit_regressor (:483 / :468), predict.edaphos_foundation_regressor (:632 / :630). `reticulate` is Suggests-only (DESCRIPTION). The bug is masked by the test gate: tests/testthat/test-foundation-finetune.R:7-12 `skip_if_no_torch()` checks only torch + torch_is_installed(), never reticulate, so all 8 blocks in that file skip rather than fail on a torch-full/reticulate-free machine.

**Impact**

> On a machine with torch and libtorch correctly installed but no reticulate (the normal case for an R-only user), all four fine-tuning entry points die with an error message that tells the user to install torch -- which they already have. Unfixable by the user without reading the source. Zero tests can catch it.

**Verification correction**

> none — verified exactly. R/foundation_finetune.R:40-46 is `.ft_require_torch <- function() { if (!requireNamespace("reticulate", quietly = TRUE) || !requireNamespace("torch", quietly = TRUE)) stop("Install the `torch` package (and its MPS / CUDA backend) to use the fine-tuning API.", call. = FALSE) }`; `grep -n reticulate R/foundation_finetune.R` returns the single hit at :41 in a 646-line file; the guard is called at :247, :401, :483, :632 (the four public entry points); reticulate is Suggests-only (DESCRIPTION:64). The masking is confirmed too: tests/testthat/test-foundation-finetune.R:7-12 defines a local `skip_if_no_torch()` that checks only `skip_if_not_installed("torch")` + `torch::torch_is_installed()`, never reticulate, so no test can ever reach the reticulate branch. Severity is honest: a torch-installed, reticulate-free R user — the normal case — gets four documented entry points dead behind an error message that tells them to install what they already have.

**Action**

> Delete `!requireNamespace("reticulate", quietly = TRUE) ||` from R/foundation_finetune.R:41. Add a torch-free regression test that stubs `requireNamespace` (or uses `local_mocked_bindings`) to assert `.ft_require_torch()` does not consult reticulate.

#### F8EC452 — No CI leg has ever executed the torch code paths: 74 test blocks / 223 expectations / ~3,140 LOC unexercised

`Test coverage` · process-gap · high · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> .github/workflows/R-CMD-check.yaml:29-34 sets `TORCH_INSTALL: 0` for all 5 matrix legs (macos/windows/ubuntu devel+release+oldrel-1) with the comment "CI still exercises ~70 % of the test suite". `r-lib/actions/setup-r-dependencies@v2` (line 47-50) installs all Suggests, so the R `torch` package IS present but libtorch/Lantern is not, hence `torch::torch_is_installed()` is FALSE and every test gate skips. Parsed gate attribution over tests/testthat: 460 test_that blocks total, 184 gated (40.0%), of which 74 are torch-gated, carrying 223 of the 1209 static expect_ calls (18.4%). A further 20 blocks need Python qiskit (tests/testthat/test-quantum-vqe.R:5-13, test-quantum-v09.R:11-33 -> skip_if_no_qiskit / skip_if_no_aer / skip_if_no_nature) which no leg installs. CI therefore runs ~366/460 blocks (79.6%) and ~931/1209 expectations (77.0%). The torch-only R sources never executed anywhere: R/foundation_moco.R (776 LOC), R/foundation_finetune.R (646), R/temporal_convlstm.R (356), R/pilar9_diffusion_torch.R (265), R/piml_hierarchical.R (263), R/piml_neural_ode.R (224), R/foundation_simclr.R (216), R/pilar8_neural_operators_torch.R (216), R/pilar10_graph_nn_torch.R (181) = 3,143 LOC; 18 R/ files reference torch at all, totalling 5,904 LOC (30% of R/). .github/workflows/test-coverage.yaml does not set TORCH_INSTALL either, and has no .covrignore or codecov.yml, so the badge silently reports these files near 0% with no gate.

**Impact**

> Pillars 2 (Neural ODE / hierarchical), 3 (ConvLSTM), 4 (SimCLR/MoCo/fine-tune), 8, 9 and 10 torch backends -- the headline 'disruptive' content and roughly a third of R/ -- have zero regression protection. A refactor that breaks any of them ships green. Findings #2 and #3 below are live proof: both are real defects sitting inside or adjacent to torch-gated code, and neither is detectable by the current CI.

**Verification correction**

> Structural claims CONFIRMED exactly: 460 test_that blocks, 184 gated (40.0%), 74 torch-gated, 20 qiskit-gated (test-quantum-vqe.R:5-13, test-quantum-v09.R:11-33), 3143 LOC across the 9 torch-only files (exact), TORCH_INSTALL: 0 for all 5 matrix legs, test-coverage.yaml sets no TORCH_INSTALL and there is no .covrignore / codecov.yml. Counts that are wrong: the suite has 1089 expect_ calls (the figure in the audit brief), not 1209, and 197 of them sit in torch-gated blocks, not 223; 20 R/ files reference torch totalling 6275 LOC, not 18 files / 5904 LOC. Line cites drift by one: TORCH_INSTALL is at .github/workflows/R-CMD-check.yaml:35 (env block :29-35) and setup-r-dependencies at :48-51.

**Action**

> Add one CI leg (ubuntu-release) that omits `TORCH_INSTALL: 0` and runs `torch::install_torch()` with a cached ~/.cache/torch (actions/cache keyed on the torch version), so the 74 torch blocks execute at least once per push. Do the same in test-coverage.yaml, or add a .covrignore + codecov.yml `target` so the badge stops averaging in permanently-unexecuted files. Correct the misleading comment at R-CMD-check.yaml:31-33 to state explicitly that no torch code path is covered.

### Detail — medium severity (action lines only)

- **F29E750** (CI & infra, hours) — Two competing release checklists contradict each other and describe a deploy action the pkgdown workflow does not use; referenced artefacts do not exist
  - Delete RELEASE.md (or reduce it to a pointer) and keep one un-versioned `RELEASE-CHECKLIST.md`, then generalise .Rbuildignore:24 to `^RELEASE-CHECKLIST.*\.md$`. Correct RELEASE-CHECKLIST-v3.10.0.md:86-92 to the single working option (branch `gh-pages`, folder `/`) and fix the peaceiris/JamesIves reference at :91-92. Drop the invented "24 MB" and "100 MB" CRAN figures from RELEASE.md:95 and cran-comments.md:96 in favour of the actual 5 MB soft target the note is arguing against. Make artefact generation a step in the checklist rather than a claim that it already happened.

- **F3D7BED** (CI & infra, days) — 33 of 43 NEWS.md releases have no git tag and there is no release-automation workflow, contradicting CONTRIBUTING's tagging promise
  - Backfill tags where the corresponding commits are identifiable (`git log --oneline --grep='v3\\.' ` on the version-bump commits), or state plainly in CONTRIBUTING.md:82-87 that only milestone versions are tagged. Add a release workflow triggered on `push: tags: ['v*']` that runs R CMD check, builds the tarball, and creates the GitHub release with the matching NEWS.md section as the body -- that also makes pkgdown.yaml:14-15's `release: published` trigger meaningful. Add a CI assertion that DESCRIPTION Version equals the newest `# edaphos` heading in NEWS.md; that single check would have caught the 3.10.0/3.11.0 split.

- **F5E91CE** (CI & infra, days) — Dockerfile is not a reproducibility artefact: builds from GitHub main, unpinned libtorch, R 4.4.1 in no CI leg, v2.1.0 metadata, missing Suggests
  - Switch to `COPY . /src` + `R -e 'remotes::install_local("/src", dependencies = TRUE, build_vignettes = TRUE)'` so the image is built from the tree that `.dockerignore` describes. Pin libtorch by setting `TORCH_HOME`/version env or by installing a fixed torch release. Bump the base to the R version in the CI `release` leg and sync all `2.1.0` strings (Dockerfile:1, 9, 15, 19, 28) to the DESCRIPTION Version, ideally via `ARG EDAPHOS_VERSION`. Add spBayes/ecmwfr/geobr/reticulate to line 45-54 or correct the claim at Dockerfile:5-6. Update the pre-downloaded encoder to the v2 identifier. Add a `docker build` job to CI (it can be `workflow_dispatch`-only) so this file stops rotting.

- **F6F101E** (CI & infra, hours) — CI builds vignettes, but 3 of 14 self-truncate to a one-line stub without libtorch -- and CONTRIBUTING tells contributors to skip vignette building entirely
  - Add a post-build assertion step to R-CMD-check.yaml that greps the rendered `inst/doc/*.html` for the knit_exit sentinel strings and fails if any vignette is a stub, or gate that assertion to the new libtorch leg from finding 1. Align CONTRIBUTING.md:44-45 and .github/PULL_REQUEST_TEMPLATE.md:23 with the actual CI invocation (drop `--no-build-vignettes`, or state explicitly that CI is stricter). Update cran-comments.md:24-26 to state which vignettes are stubs and why.

- **F9C6DD9** (CI & infra, hours) — Distribution metadata is 9 minor versions stale: CITATION.cff says 2.1.0, README says 2.8.0, .zenodo.json has no version at all
  - Update CITATION.cff:109-110 and the README citation block to the DESCRIPTION Version, add a `"version"` key to .zenodo.json, and add a CI step (or a `usethis`-style helper in the release checklist) that asserts DESCRIPTION Version == CITATION.cff version == .zenodo.json version == newest NEWS.md heading. Add a `cff-validator` action so a malformed CITATION.cff is caught. Correct the stale `v3.0.0 CRAN + rOpenSci` roadmap row in README.md.

- **FD3C0C1** (CI & infra, minutes) — Chunk option in pilar4-simclr vignette calls `reticulate::` unguarded with broken `&&`/`||` precedence -- hard error in exactly the Docker configuration
  - Replace the chunk option at vignettes/pilar4-simclr-embeddings.Rmd:361 with `eval=.torch_ok` (semantically identical, no reticulate dependency), or if the Python path is genuinely intended write `eval=.torch_ok && requireNamespace("reticulate", quietly = TRUE) && reticulate::py_available()`. Add `reticulate` to the Dockerfile install list, or leave it out and confirm the vignette renders. Add a grep-based lint (or an explicit item in the release checklist) for `[a-zA-Z]+::` appearing in a chunk option without a preceding `requireNamespace` in the same expression.

- **FD941E5** (CI & infra, hours) — cran-comments.md test-suite and install-size figures are contradicted by the tree they describe
  - Regenerate cran-comments.md:28-35 from an actual `devtools::test()` run, reporting test_that blocks vs expectations vs skips separately and grouping the 109 skips by the optional dependency that causes them (that framing also supports the Suggests table at :54-65). Regenerate :70-79 from `ls -l inst/extdata/`, listing every file over 500 KB. Since these numbers must be re-derived every release, add the two commands to the release checklist rather than hand-editing prose.

- **FDC9573** (CI & infra, hours) — No CI leg ever installs libtorch: 25% of R/ and 70 of 460 test blocks are unreachable in all three workflows
  - Add a sixth matrix leg (ubuntu-latest, R release) that sets `TORCH_INSTALL: 1` and runs `Rscript -e 'torch::install_torch()'` after setup-r-dependencies, with a cache keyed on the torch version (~/.cache/torch or the libtorch install dir). Mark it `continue-on-error: false` but exclude it from the required-checks set initially so a flaky 1 GB download does not block PRs. As a cheap intermediate step, add a `torch-smoke` job that installs libtorch and runs only the 20 torch test files via `testthat::test_dir(filter = ...)`.

- **F0E4DC1** (Code quality, hours) — Pillars 8/9/10 default backend="r" never trains the architecture it is named after, while DESCRIPTION/README mark them "implemented"
  - Either (a) rename the pure-R paths to what they are — `backend = "elm"` / `"random-features"` — and state in DESCRIPTION, README.md:375-381 and R/pillars_roadmap.R that pillars 8/9/10 require torch for the full architecture; or (b) implement backprop for the frozen layers. Option (a) is hours of edits and is honest; option (b) is weeks. Do NOT submit to CRAN/rOpenSci with the current wording. At minimum, add a `message()` at R/pilar8_neural_operators.R:106, R/pilar9_diffusion_models.R:171 and R/pilar10_graph_nn.R:193 when `backend == "r"` naming the limitation.

- **F215985** (Code quality, minutes) — Off-by-one in the RcppArmadillo BHS backend biases w_post_mean, silently corrupting every predict.edaphos_bhs() for backend="rcpp"
  - Change src/bhs_gibbs_rcpp.cpp:132 from `if (iter > burn)` to `if (iter >= burn)`. Then add a test to tests/testthat/test-pilar7-bhs-rcpp.R asserting `expect_equal(fit_r$w_post_mean, fit_cpp$w_post_mean, tolerance = <MCMC noise>)` and a direct assertion that the accumulation count equals `nmcmc - burn` (e.g. run with nmcmc=11, burn=10 and check the result equals the single retained w draw). Also soften the false equivalence claims at src/bhs_gibbs_rcpp.cpp:14-15 and R/pilar7_bayesian_hierarchical.R:270-272, which contradict tests/testthat/test-pilar7-bhs-rcpp.R:38-40 ("We don't expect bit-equivalence").

- **F3E0E05** (Code quality, hours) — gnn_embed() returns a different column count per backend and its documented @return is wrong for backend="torch"
  - Pick one contract. Simplest: make the torch path concatenate the final layer's heads so both return (n, hidden * n_heads), matching R/pilar10_graph_nn.R:289; otherwise change the roxygen @return to document the per-backend shape explicitly and record `emb_dim` in both fit objects. Either way add a test in tests/testthat/test-pilar10-gat.R that fits both backends with the same hidden/n_heads and asserts `ncol(gnn_embed(fit_r)) == ncol(gnn_embed(fit_t))`.

- **F4ED689** (Code quality, hours) — Rank-deficient design matrix poisons the entire BHS Gibbs chain to NA on iteration 1, then hard-errors — and the test's own comment about it is wrong
  - At R/pilar7_bayesian_hierarchical.R:238, detect rank deficiency and fail loudly: `qrX <- qr(X); if (qrX$rank < ncol(X)) .stopf("design matrix is rank-deficient (rank %d < %d columns).", qrX$rank, ncol(X), hint = "Drop collinear or zero-variance covariates from the formula.")`. As a belt-and-braces fix also add `beta[!is.finite(beta)] <- 0` and mirror the rank check before src/bhs_gibbs_rcpp.cpp:93. Then rewrite tests/testthat/test-pilar7-bhs-edge.R:57-69 to assert the specific error with `expect_error(..., regexp = "rank-deficient")` instead of accepting both outcomes, and delete the incorrect comment at :66-67.

- **F7EC076** (Code quality, hours) — Twelve copies of skip_if_no_torch() in three divergent flavours, orphaning the helper-torch.R that was added to replace them
  - Delete all 12 local definitions and rename the 52 undotted call sites to `.skip_if_no_torch()`. Adopt variant (b)'s tensor allocation inside helper-torch.R:7 (it is the only sound check) while keeping the `isTRUE()` wrapper. Then grep-assert in CI that `skip_if_no_torch <- function` appears nowhere under tests/ so the duplication cannot come back.

- **FBDE0E9** (Code quality, minutes) — al_fit(num.trees=) has no lower bound against ranger's undocumented OOB-quantile minimum, and the test that breaks is unseeded — a ~25% flaky ERROR
  - Two changes. (1) In R/active_fit.R, before the ranger call at :3, add `if (num.trees < 100L) .stopf("`num.trees` = %d is too small for out-of-bag quantile regression.", num.trees, hint = "ranger requires every observation to be out-of-bag in >= 10 trees; use num.trees >= 100.")` and document the floor at :29 and R/active_loop.R:36. (2) Add `set.seed(3L)` at the top of tests/testthat/test-active-quantum-posterior.R:30 and raise `num.trees` there to 100L — every other al_* test already uses >= 100.

- **FC841F7** (Code quality, minutes) — Same loop-invariant matrix product recomputed n_draws times, copy-pasted into two files
  - Hoist line R/bridges_active_learning_v3.R:295 to just after :283, and hoist R/pilar7_bayesian_hierarchical.R:389-391 to just after :379. Both are one-line moves with no behaviour change (verify with a before/after `expect_equal` on the returned object under a fixed seed). Then extract the shared "exponential-correlation kriging weights from coords" block — duplicated at R/pilar7_bayesian_hierarchical.R:370-379 and R/bridges_active_learning_v3.R:275-283 — into one internal helper in R/core_utils.R.

- **FCF64DC** (Code quality, days) — Naming schism: pilar/pillar, ordinal/domain module names, al_* vs active_*, and five undocumented cryptic export prefixes
  - Three mechanical passes, none behaviour-changing. (1) `git mv` the 7 R/pilar*.R files and 17 test files to domain names matching pillars 1-6 (bhs_*.R, neural_operators*.R, diffusion*.R, graph_nn*.R) and fix the two user-facing print strings at R/bridges_active_learning_v3.R:313 and R/bridges_structure_v3.R:225 to "Pillar". (2) Extend R/pillars_roadmap.R:8-15 from six rows to ten, retitle :1 from "six pillars" to "ten pillars", and add the `bhs_*`/`no_*`/`dm_*`/`gnn_*`/`qf_*` namespace entries; either rename `active_learning_posterior` to `al_posterior` (with an alias for back-compat) or amend the `al_*` claim in R/pillars_roadmap.R:14 and README.md:379. (3) Rename the four shadowing parameters to `fit` or `object` (R/bridges_active_learning_v3.R:260, :174; R/bridges_structure_v3.R:50, :196) and re-roxygenise. Consider renaming the `no_*` prefix to `fno_*`/`don_*`.

- **FD27999** (Code quality, days) — Twelve exported functions are never referenced anywhere in tests/, including the entire advertised tile-source pipeline
  - Add offline tests for the cheap half first: argument validation and returned-descriptor schema for each `foundation_tile_source_*` (they should be pure constructors — assert the returned list's fields and that a bad CRS/bbox errors) and for `foundation_build_cerrado_stack` with a stubbed source. Gate the network-touching halves behind `skip_on_cran()` + `skip_if_offline()`. Separately, reconsider whether `edaphos_zenodo_release` belongs in R/ at all — it is release tooling, not a soil-mapping algorithm, and shipping it as a public export means CRAN users can POST to Zenodo; moving it to inst/scripts/ removes both the test debt and the API-surface cost.

- **F00A9C3** (CRAN readiness, minutes) — `Depends: R (>= 3.5)` is falsified by two features requiring R 4.0.0 and R 3.6.0
  - Change `DESCRIPTION:90-91` to `Depends: R (>= 4.0)`, and add an explicit `r: '4.0'` (or `'oldrel-3'`) leg to `.github/workflows/R-CMD-check.yaml` so the declared floor is actually tested.

- **F4484D7** (CRAN readiness, days) — 5 of 14 vignettes are written in Portuguese while DESCRIPTION declares `Language: en-US`
  - Decide one way: either translate the 5 Portuguese vignettes to English (and fix `organised`->`organized`, `synthesised`->`synthesized` in DESCRIPTION:8,27), or move them out of `vignettes/` into `articles/` and drop them from the tarball. Then add `spelling` to Suggests plus `tests/spelling.R` so `inst/WORDLIST` is actually enforced instead of being 20 KB of shipped dead weight.

- **F4BEBBD** (CRAN readiness, hours) — DESCRIPTION Title/Description violate CRAN style: marketing adjectives, unquoted software names, zero method references
  - Rewrite DESCRIPTION:2 to a neutral Title (e.g. `Advanced Algorithms for Digital Soil Mapping`); single-quote every software name in the Description; append 3-5 anchor references pulled from `vignettes/references.bib` as `Author (Year) <doi:10.xxxx/yyyy>`; add `"cph"` to the Authors@R role vector; drop the `v3.0.0`/`edaphos_posterior` internals from the Description.

- **F4EC093** (CRAN readiness, minutes) — `src/Makevars.win` documents a Unix `src/Makevars` that does not exist
  - Add `src/Makevars` containing `PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)` (the standard RcppArmadillo skeleton), which makes `Makevars.win`'s comment true and removes the platform-dependent link assumption.

- **F83F26A** (CRAN readiness, hours) — RELEASE-CHECKLIST-v3.10.0.md instructs the maintainer to upload two artefacts that do not exist, and asserts a green state contradicted by the live test run
  - Replace the hard-coded artefact paths with the commands that produce them (`devtools::build()`, and whatever script built `zenodo_release.zip` — it is not in `tools/`). Rename/renumber the checklist for the actual next version, add a NEWS.md `# edaphos 3.11.0` section for the HEAD~1 work, and gate the header claim on a passing `devtools::test()`.

- **F00AF5C** (Release consistency, hours) — Two overlapping release checklists disagree with each other and both claim to be the authoritative list of remaining steps
  - Delete RELEASE.md (its v2.9.1 content is superseded), rename the survivor to a version-free `RELEASE-CHECKLIST.md`, and change .Rbuildignore:24 to `^RELEASE-CHECKLIST.*\.md$` so it stays excluded across releases. Reconcile the install-size numbers to one figure and fold RELEASE.md:16-18's concept-DOI-resolves-to-v0.2.0 warning into the surviving checklist.

- **F545DD7** (Release consistency, days) — The "ten pillars" identity exists only in the unreleased HEAD; every other metadata artefact still says six
  - In one commit, propagate the ten-pillar wording from DESCRIPTION:8-28 to CITATION.cff:4-107, .zenodo.json:3, _pkgdown.yml:43-48 and :66, and R/pillars_roadmap.R:1 (whose roxygen table also needs rows for Pilares 7-10, then re-roxygenise man/edaphos-roadmap.Rd). Update README.md:371 and its anchor consumers (README.md:10, :210). Tie the whole change to the version bump from finding #1 so "ten pillars" first appears in a numbered, tagged release.

- **FB9DA9E** (Release consistency, days) — The 84 KB README documents nothing after v2.8.0; its only 3.x reference is the version badge
  - Either add Pillar 7-10 sections and TOC entries and retitle README.md:371 to "The ten pillars at a glance" (updating the anchor at README.md:10 and the TOC entry at README.md:210), or drop the "10/10 pillars" badge until the README backs it. Delete the stale "🆕" prefixes at README.md:147 and :230, correct README.md:1674-1675 to the real check status (see finding #4), and change "six" to "seven" at README.md:364.

- **FBB414A** (Release consistency, hours) — .zenodo.json carries no version field at all and its description is frozen at v1.8.0
  - Add `"version": "3.10.0"` (or 3.11.0 per finding #1) and `"publication_date"` to .zenodo.json, and replace the .zenodo.json:3 description with the current 10-pillar text from DESCRIPTION:8-28 plus the v1.9.x-v3.10.0 highlights already written in cran-comments.md:105-132. Then the manual steps at RELEASE-CHECKLIST-v3.10.0.md:63-65 become unnecessary.

- **FC9610C** (Release consistency, hours) — The only DOI badge is a concept DOI the repo itself says resolves to v0.2.0, and nothing after v1.5.0 was ever deposited
  - Execute the Zenodo deposit (RELEASE-CHECKLIST-v3.10.0.md:51-71) so a version DOI exists, then add a version-DOI badge alongside the concept-DOI badge at README.md:7 and record the minted id in CITATION.cff. Add a release-publishing workflow so README.md:8 has Releases to report. Until the deposit exists, either remove RELEASE.md:16-18's known-stale badge or annotate it in the README as "concept DOI (all versions)" so readers do not mistake it for the current release.

- **FF84B54** (Release consistency, hours) — Two parallel version schemes collide inside a single README table: "v1.x roadmap lines" are interleaved with package 3.x versions, and v3.0.0 means two different things
  - Split the table in two: a "Released" table keyed strictly on DESCRIPTION versions (with every 2.6.0-3.10.0 row filled in, and Pilar 10 corrected from v2.8.0 to v2.6.0 at README.md:1713), and a separate "Open research promises" list that uses names rather than version numbers (e.g. "MoCo v2 200k-step re-benchmark", "CRAN + rOpenSci submission") so no roadmap item can ever collide with a release number again. Mark the three completed rows (README.md:1714-1716) as done and stop using v1.x strings in commit subjects for work landing in 3.x.

- **F1E1D2B** (Roadmap promises, hours) — Archival metadata (.zenodo.json, CITATION.cff) still describes a six-pillar package that stops at v1.8.0
  - Rewrite `.zenodo.json` description to ten pillars + the v2.x/v3.x history and correct the vignette count to 14; update `CITATION.cff:7,33` to ten pillars and bump its version/date fields; update the README citation block and install pin. Do all of this BEFORE executing RELEASE-CHECKLIST-v3.10.0.md step 3, since the deposit snapshots these files.

- **F2E57CE** (Roadmap promises, minutes) — Step 4 of the v1.3.2 hand-off (wire_up_v2_doi.R) matches nothing and silently writes the timestamp into the `url` field
  - In tools/pretrain/wire_up_v2_doi.R replace `\\\'` with `\'` in the patterns at lines 50 and 55 (or switch to matching on the unambiguous anchors `url         = c(` / `doi         = c(` blocks). Delete the unused `patches` list at 37-46. Replace the positional `ix[1L]` published_at fallback with an explicit match inside the `published_at = c(` block, and add a post-write assertion that `.foundation_weights_registry()` has zero NA fields for the v2 row before the script exits 0.

- **F492008** (Roadmap promises, hours) — Four pkgdown navbar links point at articles pkgdown never builds, and man/edaphos-package.Rd tells users to open a vignette that is not in the package
  - Move the four files to `vignettes/articles/` (pkgdown's supported location for non-tarball articles) and add `^vignettes/articles$` to `.Rbuildignore` so they still stay out of the CRAN build; add them to the `_pkgdown.yml` `articles:` index. Then either drop the `vignette("pilar5-soilgrids-br")` reference from `R/edaphos-package.R:153` or change it to a pkgdown URL. Fix the misleading comment at the top of `.github/workflows/pkgdown.yaml`.

- **FD3DBCB** (Roadmap promises, hours) — Two competing release checklists, one stale, pointing at a tarball path that does not exist
  - Delete or archive `RELEASE.md` (superseded) and make `RELEASE-CHECKLIST-v3.10.0.md` the single source; replace its two "already built at" claims with the commands that build them (`devtools::build()` and `edaphos_zenodo_release(...)` per RELEASE.md:22-31), since neither artifact survives a fresh clone. Pick one GH-Pages recommendation.

- **FD528FC** (Roadmap promises, days) — Three exported functions with .Rd pages and pkgdown entries are permanent stop() stubs
  - For the two tile sources: either mark them `@keywords internal` / unexport until implemented, or add an explicit "not implemented" note to `R/pillars_roadmap.R:13` and the `_pkgdown.yml:142-148` group description so the roadmap stops describing them as delivered. For spBayes: implement `predict()` for that backend or have `bhs_fit()` reject `backend = "spBayes"` up front with the same message, so the failure happens at fit time rather than after the sampler has run.

- **FF7221D** (Roadmap promises, hours) — v1.3.2 (MoCo v2 200k-step encoder) is 43 % short of target and the checkpoint exists nowhere in the repository
  - Run `Rscript data-raw/pretrain_cerrado_train_v2.R` to completion (needs `tools/pretrain/cerrado_stack.tif`, 108 MB, also gitignored, plus `cerrado_dataset_meta.rds` — see data-raw/pretrain_cerrado_train_v2.R:23-33). Before that, fix the wire-up bug above. Consider archiving the intermediate `checkpoints/state.rds` to Zenodo or a release asset so the run is resumable off-machine, and correct the stale "epoch 110000" figures in V1_3_2_HANDOFF.md:20,32.

- **F0F5D47** (Scientific reproducibility, hours) — Pretrained-weight DOI is real but the v2 registry row is all-NA while claiming a nonexistent version; CITATION.cff and .zenodo.json are many releases stale and assign one DOI to ten releases
  - 1. Bump `CITATION.cff:109` and `:184` to 3.10.0 with the correct `date-released`, and either supply the real per-release Zenodo version DOIs or delete the `identifiers:` block rather than repeating one DOI ten times. 2. Add `"version": "3.10.0"` to `.zenodo.json` and rewrite its `description` for ten pillars, or generate it from DESCRIPTION at release time. 3. Change `R/foundation_weights.R:82` from `"3.11.0"` to the version that will actually ship the v2 row, and have `foundation_weights_list()` omit or clearly flag rows with `is.na(doi)` so users are not offered an undownloadable encoder. 4. Add a release-checklist step in `RELEASE-CHECKLIST-v3.10.0.md` asserting DESCRIPTION, NEWS.md, CITATION.cff and .zenodo.json agree on the version.

- **F2F16E8** (Scientific reproducibility, hours) — cran-comments.md misstates both the check status and the extdata sizes it uses to justify the install-size NOTE
  - Regenerate the `cran-comments.md:67-96` itemisation from `file.size(list.files("inst/extdata", full.names = TRUE))` rather than by hand. Reconcile `:5`/`:21` with the actual check output — report the 2 inst/doc warnings and explain them, or fix them. Resolve the two live test errors before submitting: pass `num.trees >= 100` (or a `quantreg`-compatible minimum) at the `al_fit()` call site in `test-active-quantum-posterior.R:34`, and reorder the argument validation in `foundation_moco_*()` so the `n_channels` check precedes `.moco_require_torch()` at `R/foundation_weights.R:294` — the current order makes `test-foundation-weights.R:33` unable to observe the error it asserts on any machine without torch.

- **F3467DC** (Scientific reproducibility, hours) — Four mutually incompatible definitions of the headline benchmark's target variable across README, vignette and runner
  - Read the actual filter out of `data-raw/case_cerrado_prepare.R:220-240`, write it down once in a single authoritative place, and make `README.md:1611`, `vignettes/case-cerrado-end-to-end.Rmd:43-46`, its §3 prose, and the `data-raw/case_cerrado_run.R:8-32` header all point at it. Delete the dead `.back_transform` at `:75` and the stale log1p claims at `:22,:30-32` and `vignettes/case-cerrado-end-to-end.Rmd:71`. Remove the duplicated near-identical filter blocks at `case_cerrado_prepare.R:220-225` / `:235-240` so there is one code path.

- **F366B1F** (Scientific reproducibility, hours) — README's headline benchmark tables are two to four release cycles stale, and the current 6-method result exists only in NEWS.md
  - Promote the v3.4.0 six-method table from `NEWS.md:421-428` into `README.md`, replacing or clearly superseding `README.md:243-255`, and stamp each README table with the artefact and version it came from (e.g. "computed at v3.4.0 from `inst/extdata/benchmark_wosis_6pilar.rds`"). Correct "56 covariates" → 59 and disclose `lon`/`lat`/`year`. Correct the quantum caption to state the 250-row per-fold training cap and n = 1081. Regenerate the `inst/extdata` size table with `file.size()` and add the two benchmark bundles. Fix `README.md:841`.

- **F54856E** (Scientific reproducibility, hours) — The "LLM-augmented (Gemma 4)" DAG in the causal-discovery trio is six hand-typed edges, not an LLM output
  - Either call `causal_llm_extract()` (or read `inst/extdata/cerrado_claims.jsonl`, which the comment names as "production") and derive `llm_extra_edges` from it, committing the raw extraction alongside; or relabel the arm honestly as "expert + literature-derived edges" throughout `README.md:643-662`, `NEWS.md`, and `articles/…`, and drop "(Gemma 4)" and the fabricated per-edge confidence scores.

- **F5672C5** (Scientific reproducibility, hours) — DESCRIPTION's "every vignette runs offline" is false: four advertised vignettes are not vignettes, and the Pilar 4 × Pilar 6 vignette evaluates nothing
  - Decide per document: move the four `articles/*.Rmd` into `vignettes/` (they read only `inst/extdata`, so they should build offline), or remove them from the `README.md:1644-1662` table and from the "Used by" column at `:1615-1632`, replacing `vignette("llm-kg-benchmark")` at `:702` with a pkgdown URL. Enable the two chunks in `vignettes/pilar4-pilar6-quantum.Rmd` — the `benchmark-table` chunk only needs `readRDS(system.file(...))` and should evaluate offline. Add `getting-started` to the vignette table. Add a CI check that every `vignette("...")` string in `README.md` resolves in the built package.

- **F884A23** (Scientific reproducibility, days) — The flagship case-study benchmark cannot be re-run by anyone: its input is .gitignore'd and its output path is not the shipped artefact
  - 1. Change `out_path` at `data-raw/case_cerrado_run.R:44` to `inst/extdata/case_cerrado_results.rds` so the committed artefact has a scripted origin. 2. Either commit `case_cerrado_bundle.rds` (the extracted 1095×59 profile frame is small — `causal_cerrado_real.rds` is only 62 KB for a comparable table) or publish it under the existing Zenodo deposit and have the runner fetch + SHA-256 verify it, matching the pattern already implemented in `R/foundation_weights.R:214-221`. 3. Re-run against v3.10.0 and refresh the stamp, or add a dated "computed at v1.3.1" banner to `README.md:1554-1582`.

- **FDA80DD** (Scientific reproducibility, hours) — Residual kriging (B2) is fit to in-bag rather than OOB forest residuals, manufacturing the README's PICP conclusion
  - Replace `predict(rf_b1, data = train)$predictions` at `:201` with `rf_b1$predictions` (ranger's OOB predictions), re-run, and update `inst/extdata/case_cerrado_results.rds` and `README.md:1566-1582`. Additionally, restrict all three methods to the common 910-row intersection so the RMSE/MAE/R²/PICP columns are comparable, and state the intersection size in the table rather than three different `n` values with a footnote.

- **F71D795** (Incomplete implementations, hours) — The spBayes backend is advertised as an equal peer in README/NEWS/man but predict(), as_edaphos_posterior() and al_query_bhs() all fail on it
  - Minimum: add a `backend` guard to `as_edaphos_posterior.edaphos_bhs` at R/pilar7_bayesian_hierarchical.R:412 mirroring the one at :355 so it fails with a readable message; fix the stale "for v2.3.0" text in the :356 message to name the current version; and add an explicit `\note{}` to man/bhs_fit.Rd, man/predict.edaphos_bhs.Rd and README.md:272 stating that only `gibbs`/`rcpp` support prediction, posterior extraction and active-learning queries. Better: have the spBayes branch populate `w_post_mean` from `fit_sp$p.w.recover.samples` and `phi_hat` from `median(theta_draws[,"phi"])`, which would make all three methods work.

- **F9046AE** (Incomplete implementations, minutes) — bhs_fit()'s rcpp backend is absent from its own @param documentation, and al_query_bhs() rejects it despite the fit being complete
  - Add `"rcpp"` to the `@param backend` block at R/pilar7_bayesian_hierarchical.R:68-70 (describing the RcppArmadillo fast path) and re-roxygenise. Relax R/bridges_active_learning_v3.R:263 to `if (!bhs_fit$backend %in% c("gibbs", "rcpp"))` and add a test in tests/testthat/test-bridges-v3.R that `al_query_bhs()` succeeds on a `backend = "rcpp"` fit.

- **FAEC54C** (Incomplete implementations, hours) — al_fit() performs no validation of num.trees against nrow(labeled), producing an opaque ranger error; the guarding test is unseeded and fails ~12% of runs
  - In R/active_fit.R:53, before `.fit_core`, validate and rethrow: check `num.trees >= 100L` (or better, wrap the `ranger::ranger` call at :3-9 in `tryCatch` and rethrow "Too few trees" as "`al_fit()` needs more trees for out-of-bag quantile regression on n = <nrow> labelled rows; raise `num.trees` (>= 100 recommended, default 500)."). Document the floor at R/active_fit.R:29. Separately, add `set.seed(...)` and raise `num.trees` to 100L at tests/testthat/test-active-quantum-posterior.R:31-34, and add a `ranger (>= 0.18.0)` bound to DESCRIPTION:82 so the guard's behaviour is pinned.

- **FC68E1D** (Incomplete implementations, minutes) — foundation_weights_load() requires torch BEFORE resolving the registry, so the placeholder v2 entry reports the wrong reason for failing
  - Move registry resolution ahead of the torch gate in R/foundation_weights.R:287-301: call `.foundation_weights_entry(source)` and the `is.na(entry$url)` check for the registry-name branch first, then `.moco_require_torch()` immediately before `.moco_build_encoder()` at line 325 (which is the first statement that actually needs torch). Add a test asserting `foundation_weights_load("edaphos-cerrado-moco-v2")` matches "no published URL yet" that runs WITHOUT torch installed.

- **FD825FD** (Incomplete implementations, hours) — bhs_fit() returns an all-NaN posterior for a rank-deficient design matrix, and the edge-case test is written to accept it
  - After building `X` at R/pilar7_bayesian_hierarchical.R:128, check rank and fail with a named message: `if (qr(X)$rank < ncol(X)) stop(sprintf("Design matrix is rank-deficient (rank %d < %d columns); drop constant or collinear covariates: %s", ...), call. = FALSE)`. Then tighten tests/testthat/test-pilar7-bhs-edge.R:57-69 to `expect_error(bhs_fit(...), "rank-deficient")` instead of accepting either outcome.

- **FFFC52E** (Incomplete implementations, minutes) — causal_iv bootstrap silently discards failed 2SLS replicates and rewrites B to the survivor count
  - In R/causal_iv.R:360-372, record both counts and warn: keep `B_requested`, compute `n_failed <- B - length(draws)`, add `if (n_failed > 0) warning(sprintf("%d of %d bootstrap replicates failed to fit 2SLS (weak or collinear instruments after resampling); the posterior uses %d draws.", n_failed, B, length(draws)))`, `stop()` when `length(draws) < 2`, and store both `B_requested` and `B_effective` in the metadata list at :369 instead of silently reassigning `B`.

- **F21DBBA** (Test coverage, minutes) — test-foundation-weights.R:29-36 asserts an error message that is unreachable without torch (live ERROR 2) -- green on CI, red on CRAN
  - Move `.moco_require_torch()` in R/foundation_weights.R from line 294 down to immediately before line 325 (`EncCtor <- .moco_build_encoder()`), so the source/shape validation at 300-315 runs torch-free. Leave tests/testthat/test-foundation-weights.R:29-36 ungated -- it then becomes a real torch-free test. Do NOT 'fix' this by adding skip_if_no_torch() to the test; that would delete the only coverage of the validation branch. Audit the other four guards (.foundation_require_torch R/foundation_simclr.R:18, .piml_require_torch R/piml_neural_ode.R:11, .temporal_require_torch R/temporal_convlstm.R:12, .ft_require_torch R/foundation_finetune.R:40) for the same validate-after-guard ordering.

- **F2C0D91** (Test coverage, minutes) — al_fit is ~14.5%-flaky by construction: test-active-quantum-posterior.R:30-35 has no set.seed and passes num.trees=50 for OOB quantile regression (live ERROR 1)
  - Primary fix is the TEST: tests/testthat/test-active-quantum-posterior.R:30-35 -- add `set.seed(...)` at the top of the block and raise `num.trees` to 100L or higher (this block does not exercise forest size at all; it only checks that `as_edaphos_posterior()` demands `newdata`). Secondary, in R/active_fit.R after line 55, add a guard so the failure is actionable rather than a ranger internal: e.g. `if (num.trees < 100L) .stopf("num.trees = %d is too small for ranger's out-of-bag quantile regression (needs every observation OOB in >= 10 trees).", num.trees, hint = "Use num.trees >= 100.")`. Note test-error-messages.R covers input validation for only 4 of 169 exports (bhs_fit, gnn_build_graph, dm_fit, no_deeponet_fit) -- al_fit is not among them.

- **F86487C** (Test coverage, hours) — R/pilar7_bayesian_hierarchical.R:270-272 cites a test that does not perform the verification it claims
  - Either implement the claimed check -- keep a `.bhs_gibbs_dense()` reference implementation as an internal (not exported) function and assert `expect_equal(draws_fast, draws_dense, tolerance = 1e-10)` under a fixed seed in test-pilar7-bhs-fastpath.R -- or delete the unsupported sentence at R/pilar7_bayesian_hierarchical.R:270-272 and replace it with what the test actually contracts.

- **FA6ECC8** (Test coverage, hours) — The RcppArmadillo BHS Gibbs backend has no real numerical-agreement test: one scalar mean at 0.2 tolerance, w_post_mean never compared, no edge cases
  - Replace the scalar check in tests/testthat/test-pilar7-bhs-rcpp.R:37-56 with a draw-by-draw comparison: run both backends with the same `seed` and assert `expect_equal(fit_r$beta_draws, fit_cpp$beta_draws, tolerance = 1e-8)` plus the same for sigma2_draws, tau2_draws and w_post_mean. If that fails, the C++ header comment at src/bhs_gibbs_rcpp.cpp:24-25 is wrong and should be corrected -- either way the ambiguity must be resolved. Add `backend = "rcpp"` variants of the 10 blocks in test-pilar7-bhs-edge.R (parameterise the file over both backends), and reconcile `arma::solve` at src/bhs_gibbs_rcpp.cpp:91 with `lm.fit` at R/pilar7_bayesian_hierarchical.R:238.

- **FB609A4** (Test coverage, minutes) — NEWS.md v3.10.0 test and check claims are not reproducible in any environment the project automates
  - Restate NEWS.md:71-72 as the CI-reproducible figure with the environment named, e.g. "1 022 expectations pass, 109 skipped (74 torch, 22 dagitty, 9 bnlearn, 3 dbarts, 1 other) on R 4.6.1 without libtorch", and add the full-stack figure separately if desired. Fix the two errors before re-asserting '0 errors'. Consider having the test-coverage workflow emit the PASS/SKIP counts as a job summary so future NEWS entries quote a machine-generated number.

- **FB6D884** (Test coverage, days) — 12 exported functions are never called by any test, including the entire tile-download layer and a function that recursively deletes a directory
  - Add a tests/testthat/test-zenodo-release.R that runs `edaphos_zenodo_release(tempfile(), include_tarball = FALSE, zip = FALSE)` and asserts the manifest/metadata.json/checksums, plus an explicit test that it refuses a non-empty non-edaphos directory (i.e. gate the `unlink` behind a confirmation or an `overwrite = FALSE` default). Add offline tests for `foundation_tile_source_soilgrids/worldclim/srtm` that assert the request objects they build (httr2 is already an Import and 14 blocks already use httr2 mocking), and simple `expect_error(..., "EarthData|Copernicus")` tests for the two documented stubs at R/foundation_tiles.R:183 and :202. Add a direct call test for `causal_ontology_agrovoc()` query construction.

- **FBCB1E4** (Test coverage, days) — The v3.8.0 friendly-error work covers 4 of 169 exports; .assert_type/.stopf adopted in 6 of 70 R/ files
  - Extend .stopf/.assert_type to the public entry points of pillars 1-6, starting with the ones the suite already stresses: al_fit (R/active_fit.R:52), al_loop (R/active_loop.R:73), quantum_krr_fit, piml_profile_fit, temporal_convlstm_fit, causal_estimate_effect, foundation_weights_load (replace the bare stop at R/foundation_weights.R:312 and the stopifnot at :318). Grow tests/testthat/test-error-messages.R in lockstep -- it is the highest-value file in the suite because it is the only large one that is 100% ungated and therefore runs everywhere including CRAN.

- **FC5841E** (Test coverage, minutes) — Three of four wall-clock assertions run on CRAN: only 1 skip_on_cran() exists in the whole 460-block suite
  - Add `skip_on_cran()` as the first line of the three blocks: tests/testthat/test-pilar7-bhs-rcpp.R:84, tests/testthat/test-pilar7-bhs-fastpath.R:80, tests/testthat/test-pilar10-gat-sparse.R:112 -- matching the pattern already used correctly at test-quantum-kernel-rcpp.R:46. Consider also gating them on `Sys.getenv("NOT_CRAN")` in the coverage job so they still run somewhere.

### Low severity

| ID | Area | Effort | Finding |
| --- | --- | --- | --- |
| F0CBFC4 | CI & infra | hours | test-coverage has no threshold gate, no codecov.yml, and diverges from R-CMD-check on TORCH_INSTALL; reported coverage has an invisible ~75% ceiling |
| F6330AE | CI & infra | minutes | pkgdown site loads mermaid from a third-party CDN with no integrity attribute, on a surface SECURITY.md declares in scope |
| FA46190 | CI & infra | days | Documented quality gates (spell check, URL check, lint) exist in prose and templates but in no workflow; `_R_CHECK_FORCE_SUGGESTS_` is never relaxed across 40 Suggests |
| FAACA6C | CI & infra | minutes | `needs: website` and `needs: coverage` are no-ops: DESCRIPTION declares no Config/Needs/* fields |
| FAF9367 | CI & infra | minutes | .Rbuildignore hygiene: version-pinned checklist pattern, duplicated entry, dead README.Rmd rule |
| FDA19FA | CI & infra | hours | No dependency pinning outside the Dockerfile; floating action tags in a job granted `contents: write` |
| F434C69 | Code quality | minutes | %\|\|% is copy-pasted into 7 files; the definition that actually wins is decided by alphabetical collation, not by design |
| F503F9C | Code quality | hours | quantum_kernel_rcpp allocates nX * 2^n complex states but its only guard is a warning keyed on n alone |
| F594BF7 | Code quality | hours | Dead code, an undocumented non-dotted internal, and three comment/code contradictions in the pillar 7-10 modules |
| FA36407 | Code quality | days | The v3.8.0 friendly-error system covers ~5% of failure sites and exactly the 6 files that got a test; 136 raw stop() and 13 divergent torch gates bypass it |
| FB51F5F | Code quality | minutes | history[history > 0] injects NA into fit$history; the fix exists in all four torch files and none of the three pure-R files |
| FFAFBF2 | Code quality | days | 169 exports + 73 S3 methods is an exceptionally wide public API for 19.7k LOC, with several internal-looking primitives promoted to the surface |
| F4516A9 | CRAN readiness | hours | Maintainer-only files install into the user's library; CITATION metadata is stale and there is no inst/CITATION |
| F5825EA | CRAN readiness | minutes | 6 of 40 Suggests are never used anywhere in the package |
| FEC2806 | CRAN readiness | minutes | `MASS::ginv()` called unguarded at 5 sites while MASS is Suggests-only |
| FEDA31F | CRAN readiness | hours | Two network entry points call `httr2::req_perform()` with no error handling, against CRAN's graceful-failure policy |
| FF58F4E | CRAN readiness | hours | Two exported functions are unconditional `stop()` stubs, documented and counted as shipped features |
| F63C7AD | Release consistency | hours | Placeholder and NA DOIs are committed: the exported weights registry advertises an encoder with no URL, DOI or checksum |
| F6C4FB9 | Release consistency | hours | _pkgdown.yml's release list stops at v2.0.0 and its site description still says six pillars |
| FA7F096 | Release consistency | minutes | RELEASE-CHECKLIST-v3.10.0.md instructs the maintainer to upload artefacts that do not exist and names the wrong deploy action |
| FEA55C5 | Release consistency | hours | 32 of the last 33 NEWS releases have no git tag, violating the project's own documented release policy |
| FFBBEBB | Release consistency | hours | Dockerfile self-identifies as v2.1.0 and pins a 2026-04-23 CRAN snapshot, but installs HEAD |
| F1A720B | Roadmap promises | weeks | v1.8.3 (expand LLM gold standard from 72 to 300 claims) is untouched — still 30 abstracts / 72 claims |
| F2FC8F9 | Roadmap promises | minutes | V1_3_2_HANDOFF.md instructs the maintainer to cd into a directory named after a different project |
| F3E4CA6 | Roadmap promises | hours | Documentation promises that point at content which does not exist: cheatsheets "on the pkgdown site", P8/P9 benchmarks "in vignettes/" |
| F4BEE44 | Roadmap promises | minutes | package_v2_for_zenodo.R fails with a cryptic stopifnot before its own step-count guard, and drops the resume hint from its error message |
| F4EE43C | Roadmap promises | hours | Roadmap table and NEWS were never updated for the last two feature commits; DESCRIPTION 3.10.0 conflicts with the 3.11.0 baked into the weights registry |
| F66D149 | Roadmap promises | minutes | Stale dead-end in data-raw/causal_iv_benchmark.R blocks a path that v1.9.1 already delivered |
| F9EDEBA | Roadmap promises | minutes | Pilar 7 was promised as INLA/Stan and delivered as a hand-rolled Gibbs sampler; the substitution is never disclosed |
| FCC0D53 | Roadmap promises | days | Promised production-scale outputs never produced: the 10k-abstract LLM-KG run and the 6-pillar benchmark wrapper set |
| F37E56E | Incomplete implementations | hours | foundation_embed_at_coords() converts a failed raster block read into an all-zero patch that is indistinguishable from a real embedding |
| F3A34C0 | Incomplete implementations | minutes | foundation_build_cerrado_stack() calls digest::digest() unguarded, but digest is Suggests-only -- the exported function dies on a clean install |
| F3CACF8 | Incomplete implementations | minutes | Off-by-one in the RcppArmadillo Gibbs sampler's w_post_mean accumulation makes the rcpp backend disagree with the R backend it claims to reproduce |
| F52B874 | Incomplete implementations | minutes | Two exported functions ship without \value in man/, contradicting the NEWS claim of 0 R CMD check notes |
| F649AF8 | Incomplete implementations | minutes | Stale forward-looking version markers and dead code left in shipped R/ sources |
| FBDF515 | Incomplete implementations | hours | quantum_kernel() with the default rcpp backend has only a warning where it needs a hard cap, and silently returns an all-ones kernel for reps <= 0 |
| F1A5FC0 | Test coverage | hours | 12 duplicated, semantically divergent torch skip helpers shadow the canonical helper-torch.R; the package's own runtime guards never check torch_is_installed() |
| F3CED48 | Test coverage | hours | 44 print/summary S3 methods, zero snapshot tests, 15 expect_output calls -- half of them behind torch/qiskit gates |

## 12. Gaps found by the completeness critic

### Nobody looked at the git clock: the entire package — 43 "releases", 19.7k LOC, 10 pillars, 185 man pages — was built in 8 calendar days, and has had zero commits in the 90 days since (high, hours)

**Evidence**

> `git log --reverse --format="%ci"` → first commit 2026-04-20 23:44 ("Initial release of edaphos 0.1.0"), last commit 2026-04-27 17:49 (272b378). Commits per day: 1, 10, 10, 22, 15, 7, 9, 8 = 82 commits total. NEWS.md contains 43 `^# edaphos` sections (v0.1.0 → v3.10.0). That is 5.4 "releases" per day and ~2,460 lines of R per day, and it means the average commit ships more than one version. Today is 2026-07-26 — 90 days of silence since the last commit. `git tag -l` gives 18 tags: v0.1.0…v1.6.0 contiguous, then a single v3.10.0 — i.e. tagging was abandoned on day ~4 and re-attempted once. All eight auditors treated the version history as a maintenance record ("32 of 33 NEWS releases have no git tag", "metadata is 9 minor versions stale"); none established that the versions are labels applied inside one continuous week-long build, which is the actual cause of every drift finding they reported. Nothing was ever cut, tagged, installed, or consumed by a third party between "releases".

**Action**

> Stop treating the version number as evidence of maturity. Collapse the 43 NEWS sections into an honest history (or keep them but add a preamble stating they are development milestones within a single build sprint, not distributed releases), reset the version to something defensible (0.x or 1.0.0-rc), and set DESCRIPTION `Lifecycle: experimental` to match the badge already in README.md:4. Then tag exactly one commit and make that the first thing anyone can install.

### The README roadmap's own terminal milestone — `v3.0.0 | CRAN + rOpenSci submission | 📝` — is still marked not-started, while DESCRIPTION says 3.10.0 (high, hours)

**Evidence**

> README.md roadmap table (lines ~1687-1717) ends with four unfinished rows: `| v1.9.3 | Real geodata download path | 📝 |`, `| v1.3.2 | Re-benchmark with MoCo v2 encoder (200 k steps) | 🚧 |`, `| v1.8.3 | Expand gold-standard to 300 real claims | 📝 |`, `| v3.0.0 | CRAN + rOpenSci submission | 📝 |`. DESCRIPTION:3 is `Version: 3.10.0`. So the package shipped ten minor versions past the milestone at which it was supposed to be submitted, and the roadmap still shows that gate as untouched. The same table also has zero rows for v2.6.0, v2.7.0, or any v3.x release, and misattributes Pillar 10 to v2.8.0 while NEWS.md:915-917 and NEWS.md:1201 both say v2.6.0 (matching _pkgdown.yml:180 "Pilar 10 — Graph Attention Networks (v2.6.0+)"). The release-consistency auditor found the two version schemes collide; nobody noticed the roadmap says the submission never happened.

**Action**

> Rewrite the README roadmap table as two separate tables (delivered features vs. open work) and move the CRAN/rOpenSci row into an explicit "not yet attempted" section. Fix the v2.8.0→v2.6.0 Pillar-10 row. Delete rows for work that has since landed (v1.9.3 is done per commit 05cb516).

### `inst/rosc/submission.md` — an outward-facing rOpenSci pre-submission dossier — installs into every user's library and asserts at least eight claims that are false in this tree (high, hours)

**Evidence**

> .Rbuildignore has no `inst/` exclusion, so `inst/rosc/submission.md` (and `inst/WORDLIST`) ship in the CRAN tarball and land in the user's library. Its false claims: (1) "**Examples**: every exported function has at least one `@examples` block" — the CRAN auditor measured 134 of 169 exports with no examples; (2) "**Vignettes**: 14 vignettes covering all 10 pillars" — there are 14, and none covers pillars 7-10; (3) "50+ test files, **1 345 expectations**" — live run gave 1022 + 109 skipped; (4) "[x] Package builds on `R CMD check --as-cran` with 0 errors / 0 notes" — two test errors reproduce; (5) "Code is formatted consistently (styler)" — no styler config exists anywhere in the repo; (6) "**Some Suggests are pinned** (`bnlearn`, `dagitty`)" — DESCRIPTION Suggests lists both with no version constraint at all; (7) "`spBayes` … We use it as an alternative backend" — the incomplete-implementation auditor found predict()/as_edaphos_posterior()/al_query_bhs() all fail on that backend; (8) it advertises `quantum_kernel_rcpp()` to reviewers as user-facing API, but it exists only in R/RcppExports.R:8 and is not in NAMESPACE. It also states the Zenodo concept DOI as 10.5281/zenodo.19683708 and ships the author's affiliation, personal email and availability commitments into every install.

**Action**

> Add `^inst/rosc$` to .Rbuildignore immediately (or move the file to a `.Rbuildignore`d top-level `submission/` directory). Then reconcile every quantitative claim in it against a real `R CMD check` + `devtools::test()` run before it is pasted into a public rOpenSci issue — as written it would be falsified by the first reviewer who runs the suite.

### The 10 per-pillar cheatsheets call 8 functions that do not exist anywhere in R/ — `cheatsheets/pilar4.md`'s entire "Core API" block is fictional (high, hours)

**Evidence**

> Extracting every `pkg_prefix(` token from cheatsheets/*.md and diffing against NAMESPACE exports yields 10 non-exported names; grepping R/ for their definitions shows 8 are defined nowhere at all: `foundation_tile_raster` (cheatsheets/pilar4.md:11), `foundation_simclr_fit` (pilar4.md:18), `foundation_moco_fit` (pilar4.md:25), `foundation_finetune` (pilar4.md:41), `temporal_cube_build` (pilar3.md:11), `temporal_convlstm_forecast` (pilar3.md:27), `al_batchbald` (pilar5.md:39), `piml_default_prior` (pilar2.md:24). In cheatsheets/pilar4.md the "Core API" fence has 6 calls and 4 of them are invented; it also says "# MoCo v1 pre-training" while the package ships MoCo v2 via `foundation_moco_pretrain()`. The real names are `foundation_tile_dataset`, `foundation_simclr_pretrain`, `foundation_moco_pretrain`, `foundation_fit_classifier`/`foundation_fit_regressor`. By contrast the same extraction over README.md (84 KB) and INTRO.md returns **zero** non-exported names — so the drift is confined precisely to the artefact that no tool ever renders or checks. Created wholesale in commit 5ceb86f "docs(v3.9.0): documentation reorganisation -- INTRO.md + 10 per-pilar cheatsheets".

**Action**

> Rewrite cheatsheets/pilar2.md, pilar3.md, pilar4.md and pilar5.md against NAMESPACE. Then add a CI step (or a testthat test) that extracts backticked `fn(` tokens from cheatsheets/*.md, INTRO.md and README.md and asserts each resolves via `exists(fn, envir = asNamespace("edaphos"))` — this is a 15-line test that would have caught all 8.

### Pillars 8, 9 and 10 ship with zero scholarly attribution: no `@references` in any pillar-7-10 source file, and no DDPM / DeepONet / FNO / GAT entry in the 94-entry bibliography (high, hours)

**Evidence**

> `grep -c "@references" R/*.R` returns hits in only 21 of 70 files, and **none** of R/pilar7_bayesian_hierarchical.R, R/pilar8_neural_operators.R, R/pilar8_neural_operators_torch.R, R/pilar9_diffusion_models.R, R/pilar9_diffusion_torch.R, R/pilar10_graph_nn.R, R/pilar10_graph_nn_torch.R contains a single `@references` tag — so no man/*.Rd page for any pillar-7-10 function cites its source paper. vignettes/references.bib has 94 entries, and greps for Ho2020, DDPM, Lu2021, DeepONet, Li2021, Fourier, Velickovic and GAT all return 0; the bib stops at pillar 6 (it has Chen2020simclr, Chen2020moco2, He2020moco, Shi2015, Kirsch2019batchbald, CinelliHazlett2020). The papers appear only in non-Roxygen `#` comments invisible to users: R/pilar9_diffusion_models.R:33 ("Ho, J., Jain, A. and Abbeel, P. (2020)"), R/pilar8_neural_operators.R:15/21 ("FNO, Li et al. 2021", "DeepONet, Lu et al. 2021"), R/pilar10_graph_nn.R:10 ("Velickovic et al. 2018"). For a package whose entire value proposition is faithful implementation of named research methods, the four newest pillars — exactly the ones that justify the "ten pillars" claim in DESCRIPTION — are unattributed. DESCRIPTION's Description field also contains zero method references, and cheatsheets/pilar8-10.md have no "Key references" section comparable to pilar4.md's.

**Action**

> Add the four missing bib entries (Ho, Jain & Abbeel 2020 arXiv:2006.11239; Lu et al. 2021 Nat. Mach. Intell. 3:218; Li et al. 2021 ICLR arXiv:2010.08895; Veličković et al. 2018 ICLR arXiv:1710.10903; plus Kovachki et al. 2023 JMLR already cited in a comment) and a `@references` block on every exported `no_*`, `dm_*`, `gnn_*` and `bhs_*` function. This is the cheapest credibility fix in the repo and is a hard requirement for rOpenSci/JOSS review.

### The pkgdown site is live and current at HEAD — which refutes the CI audit's "pkgdown cannot succeed" and two release docs' "gated on enabling GH Pages" — but its public homepage says "six research pillars", its citation block says version 2.8.0, and 4 navbar links are live 404s (high, hours)

**Evidence**

> `origin/gh-pages` exists with commit 419c6ee "Deploying to gh-pages from @ HugoMachadoRodrigues/edaphos@272b378…" dated 2026-04-27 21:57 — i.e. the site was built and deployed from the exact commit under audit. `git ls-tree origin/gh-pages:reference | grep -c '\.html$'` = 184, and `reference/index.html` exists with all 17 sections including "Pilar 7…10" — so `has_concept("pilar1")` matching zero topics does NOT break the build (the section fills from `starts_with("causal_")`), contradicting the CI auditor's blocker. Meanwhile: `git show origin/gh-pages:index.html | grep version` gives `version">3.10.0</small>` in the header but `version   = {2.8.0}` in the BibTeX the site tells users to cite; `git show origin/gh-pages:index.md | head -20` reads "It is organised around **six research pillars**"; `git ls-tree -r origin/gh-pages | grep -E 'pilar1-causal-real|pilar3-4d-real|pilar5-soilgrids-br|llm-kg-benchmark'` returns nothing, so the four navbar entries at _pkgdown.yml:75, 79, 91, 101 are 404s on the live site right now; and `grep -i cheat` over the whole gh-pages tree returns nothing. INTRO.md — the one document that says "The ten research pillars" (INTRO.md:42) — is deployed as INTRO.html but appears nowhere in _pkgdown.yml's navbar, so it is reachable only by guessing the URL.

**Action**

> Correct the audit record: the pkgdown workflow works. Then fix what is actually broken in production — delete or relocate the four dead navbar entries (or move articles/*.Rmd into vignettes/ with `eval=FALSE` so pkgdown builds them), regenerate README.md so the homepage says ten pillars and the citation says 3.10.0, add INTRO.md and cheatsheets/ to the navbar, and mark the "enable GH Pages" line in RELEASE-CHECKLIST-v3.10.0.md and the `[ ]` box in inst/rosc/submission.md as done.

### Pillars 3 and 4 are demonstrated nowhere a user can see: their live site articles are reference-list stubs and their getting-started sections are `eval = FALSE` comments (high, days)

**Evidence**

> Deployed article sizes from `git show origin/gh-pages:articles/<x>.md | wc -c`: pilar1-causal 34,813 B, pilar6-quantum 29,118 B, llm-annotation-workflow 12,556 B — but **pilar3-4d-soc 5,287 B** and **pilar4-simclr-embeddings 3,956 B**, and neither has a `_files/` figure directory on gh-pages (unlike pilar1/2/5/6). The deployed pilar3-4d-soc.md ends in the Shi et al. 2015 bibliography with no results; pilar4-simclr-embeddings.md shows the NT-Xent maths, then the chunk `if (!.torch_ok) knitr::knit_exit(...)` and stops. Independently, vignettes/getting-started.Rmd — the orientation tour — has `## Pilar 3` as a single `{r p3, eval = FALSE}` comment ("Skipped in the getting-started tour") and `## Pilar 4` as a single `{r p4, eval = FALSE}` comment. So on the public documentation site, in the tarball, and in the onboarding vignette, the ConvLSTM and Foundation-Model pillars produce not one number. The CI auditor predicted this truncation; I confirmed it is live.

**Action**

> Either add a `libtorch`-installing CI leg for the pkgdown job (`torch::install_torch()` before `pkgdown::build_site`), or replace the `knit_exit()` stubs with pre-computed `inst/extdata` bundles rendered offline (the pattern already used by pilar1-causal). At minimum give getting-started.Rmd a runnable P3/P4 example using the shipped `case_cerrado_results.rds` so the tour covers 10 of 10 pillars rather than 8.

### Bundled-data licensing is undeclared and one shipped file redistributes 301 verbatim sentences from copyrighted journal articles (high, days)

**Evidence**

> README.md:1613 titles the section "### `inst/extdata` real-data bundles (**CC-BY-4.0**)" and README.md:1561 attributes the WoSIS source as "(Batjes et al. 2020, CC-BY-4.0)". But DESCRIPTION:26 declares only `License: MIT + file LICENSE`; LICENSE contains just "YEAR: 2026 / COPYRIGHT HOLDER: Hugo Rodrigues"; there is no `inst/COPYRIGHTS`, no `LICENSE.note`, no `inst/extdata/LICENSE` or README, and no `Copyright:` field. A tarball that mixes MIT code with CC-BY-4.0 third-party data must declare the second licence and carry its attribution — nothing in the installed package tells a user that SoilGrids/WorldClim/SRTM/WoSIS/MODIS-derived content is present or how to attribute it (the only such statement lives in tools/pretrain/README.md:76-81, which is `.Rbuildignore`d). Worse, `inst/extdata/cerrado_claims_real_corpus.jsonl` (96 KB, 301 lines) ships verbatim `evidence` sentences lifted from journal articles keyed only by OpenAlex work IDs, e.g. `{"cause":"vegetation_shift",...,"source":"https://openalex.org/W2151838555","evidence":"Shifts of woody and herbaceous vegetation with deforestation, afforestation, and woody plant encroachment typically alter the depth and distribution of plant roots, influencing soil nutrients, the water balance, and net primary productivity (NPP)."}` — no publisher, no title, no licence field, no reuse statement, redistributed under MIT.

**Action**

> Add an `inst/COPYRIGHTS` (or `LICENSE.note`) enumerating each inst/extdata file, its upstream source, its licence and the required attribution string; add `Copyright:`/`LicenseNote:` to DESCRIPTION. For cerrado_claims_real_corpus.jsonl, either replace the verbatim `evidence` field with the OpenAlex ID plus a character offset, truncate to a short quotation with full bibliographic attribution, or move the file out of the tarball and fetch it at runtime.

### The 10 cheatsheets — the only doc set consistent with the "ten pillars" claim — are excluded from the tarball, absent from the pkgdown site, and unlinked from the README, and their own README says otherwise (medium, hours)

**Evidence**

> cheatsheets/README.md closes with: "These cheatsheets are NOT shipped in the CRAN tarball (`.Rbuildignore` excludes the `cheatsheets/` directory) -- they live on the GitHub repo **and the pkgdown site** for ergonomic browsing." But `grep -n "cheat" _pkgdown.yml` returns nothing, `git ls-tree -r origin/gh-pages | grep -i cheat` returns nothing, and `grep -in "cheatsheet" README.md` returns nothing — the 84 KB README never mentions them. .Rbuildignore:23 has `^cheatsheets$`. So cheatsheets/README.md's table ("One-page references for each of the **10** research pilares") — the single artefact where pillars 7-10 get equal billing, which the roadmap auditor correctly noted is missing from every other document — is reachable only by browsing the GitHub file tree. The low-severity finding "cheatsheets 'on the pkgdown site'" was raised as a doc-promise nit; the structural point is that the ten-pillar identity has exactly one home and it is off every distribution channel.

**Action**

> Either add `cheatsheets/` to the pkgdown site (copy into `vignettes/` as `.Rmd` articles, or list them under `_pkgdown.yml` as external links), or delete the false sentence in cheatsheets/README.md and link the directory from README.md. Fix the phantom function names first (see the cheatsheet-API finding) — publishing them as-is would put four fictional APIs on the public site.

### No 5-minute path exists from the front door: the string "getting-started" appears nowhere in the 84 KB README, there is no quickstart section, and Installation is at line 335 of 1871 (medium, hours)

**Evidence**

> `grep -n "getting-started\|Getting started\|getting started" README.md` returns **zero hits** — the package's orientation vignette (vignettes/getting-started.Rmd, the one file that runs one example per pillar offline in seconds) is invisible from the README, which is simultaneously the GitHub landing page and the pkgdown homepage. README.md structure: the first three `##` sections after the badges are "Why edaphos exists" (47), "Architecture at a glance" (81) and "## 🆕 v1.7.0 — capstone cross-pillar vignette" (147); the **Table of contents is at line 207**, i.e. below three release-announcement blurbs; the next two are "## 🆕 v2.7.0 – v2.8.0" (230) and "## 🆕 v2.1.0" (262) — three "🆕" banners for releases 12-23 versions old, in non-chronological order (1.7.0, then 2.7.0, then 2.1.0). `## Installation` is at line 335 (18 % into the file) and its only command pins `@v2.8.0`, a ref that does not exist. There is no `## Quick start` heading anywhere. 73 `##`/`###` headings in one file.

**Action**

> Insert a `## Quick start` section immediately after the badges: `remotes::install_github("HugoMachadoRodrigues/edaphos")` (unpinned), then the toy-data + `al_fit()` + `uncertainty_calibrate()` block from getting-started.Rmd, then `vignette("getting-started")`. Delete the three "🆕" blurbs (that content belongs in NEWS.md) and move the TOC above line 50.

### README's vignette table lists 17 vignettes, 4 of which do not exist, and omits the only one a new user should open (medium, minutes)

**Evidence**

> README.md:1638-1662: the `## Vignettes` section opens with `browseVignettes("edaphos")` and then a table of 17 vignette rows. Diffing the backticked names against `ls vignettes/*.Rmd`: **listed but nonexistent** — `pilar1-causal-real`, `pilar3-4d-real`, `pilar5-soilgrids-br`, `llm-kg-benchmark` (all four were moved to the `.Rbuildignore`d `articles/` in commit 5ceb86f and are also absent from the deployed site); **exists but not listed** — `getting-started`. So `browseVignettes("edaphos")` returns 14 entries against a table advertising 17, and the 4 richest-sounding rows ("1 095 real WoSIS Cerrado profiles", "MODIS NDVI + stochastic EnKF", "Gemma 4 vs GPT-4o-mini vs Claude Sonnet-4.5") resolve to nothing. The same wrong count propagates: vignettes/getting-started.Rmd "Next steps" says "**17 vignettes**, one per pillar + key case studies", and inst/rosc/submission.md says "14 vignettes covering all 10 pillars" plus "4 additional articles in `articles/`". Two lines above the table, README also claims a "shared BibTeX bibliography (`vignettes/references.bib`)" for all of them — which the articles/ four cannot reach (see next finding).

**Action**

> Split the table into "Vignettes (shipped, `browseVignettes("edaphos")`)" — 14 rows including getting-started as row 1 — and "Case-study articles (GitHub / pkgdown only)" — 4 rows with links to the site once those pages actually build. Fix "17 vignettes" in getting-started.Rmd's Next steps.

### The four `articles/*.Rmd` cannot be rendered by anyone: they retain full vignette metadata but point at a `references.bib` that does not exist in their directory (medium, hours)

**Evidence**

> All four files in articles/ carry complete vignette headers — e.g. articles/llm-kg-benchmark.Rmd:12-14 has `%\VignetteIndexEntry{...}`, `%\VignetteEngine{knitr::rmarkdown}`, `%\VignetteEncoding{UTF-8}` — and all four declare `bibliography: references.bib` (llm-kg-benchmark.Rmd:9, pilar1-causal-real.Rmd:7, pilar3-4d-real.Rmd:7, pilar5-soilgrids-br.Rmd:6). But `ls -la articles/` shows exactly four `.Rmd` files and no `references.bib` — the bib lives at vignettes/references.bib. Pandoc resolves `bibliography:` relative to the input file, so knitting any of these in place fails on a missing bibliography, and all four use `[@key]` citations (e.g. articles/llm-kg-benchmark.Rmd cites the same keys as the vignettes). Combined with .Rbuildignore:22 `^articles$` (never built by R CMD build) and pkgdown reading only `vignettes/` (confirmed absent from origin/gh-pages), these 43 KB of case-study prose — the documents README advertises as the real-data evidence for Pillars 1, 3 and 5 and the LLM benchmark — are unrenderable by every tool in the project.

**Action**

> Either move the four files back to `vignettes/` with `eval = FALSE` heavy chunks (the `.rds` bundles they need are already in inst/extdata), or add `articles/references.bib` (a symlink will not survive `git archive`; copy it) and a small `articles/build.R` that knits them into `docs/articles/`. Whichever path, the 4 dead navbar links in _pkgdown.yml must resolve.

### `inst/extdata/cerrado_abstracts.jsonl` contains 10 LLM-written abstracts attributed to fabricated citation keys, and the README calls them "curated" (medium, hours)

**Evidence**

> The file has 10 lines; its `source` fields are `Ferreira2021_Cerrado_SOC_climate`, `Oliveira2019_Oxisol_argillic`, `Silva2018_Cerrado_topography_TWI`, `Reis2020_land_use_SOC`, `Moura2017_Cerrado_erosion`, `Lima2022_fire_SOC`, `Vasconcelos2019_clay_water_productivity`, `Cunha2020_NDVI_soil_moisture`, `Pereira2021_pH_nutrient_availability`, `Gomes2018_microbial_temperature_SOC` — Author+Year keys that look like real literature; none appears in the 94-entry vignettes/references.bib, and the abstract prose is textbook-smooth ("Across a 1000 km precipitation transect… topsoil SOC in native savanna plots increased linearly with MAP between 900 and 1700 mm"). data-raw/annotation_tool_demo.R:4 calls them "30 **synthetic** abstracts" and data-raw/llm_benchmark_gold_standard.R:20 documents the field as "~400-600 char **synthetic** abstract", but README.md:1630 sells the file as "10 **curated** Cerrado-pedology abstracts" with size "~40 KB" (actual: 8 KB), under the section header "`inst/extdata` **real-data** bundles". inst/extdata/cerrado_gold_standard_v1.jsonl is likewise 30 synthetic records keyed `CER_01`… So the corpus that Pillar 1's LLM-KG pipeline is demonstrated and benchmarked on consists of invented papers with planted causal claims, presented in the README as curated literature. The reproducibility auditor established the *benchmark numbers* are simulated; the corpus provenance is a separate and more citable problem.

**Action**

> Rename the `source` values to unambiguously synthetic identifiers (`SYN_01`…) so no reader can mistake them for citations, change README.md:1630 from "curated" to "synthetic" and fix the size, and retitle README.md:1613 from "real-data bundles" to something accurate (the directory mixes real WoSIS derivatives with fully synthetic corpora).

### `br_amazon` and `br_pantanal` ship as LazyData with man pages but are absent from README, absent from DESCRIPTION, and used by exactly one smoke-test file (medium, hours)

**Evidence**

> data/ contains br_cerrado.rda (22 KB), br_amazon.rda (21 KB), br_pantanal.rda (21 KB); all three are documented (man/br_amazon.Rd, man/br_pantanal.Rd, R/data.R:43-60) and listed in _pkgdown.yml's "Bundled datasets" section. But README's `## Bundled datasets` section (README.md:1597-1612) documents **only** `br_cerrado` ("### `br_cerrado` — 45 × 45 synthetic surrogate") and never names the other two; DESCRIPTION's Description says "A synthesised **Cerrado** dataset is bundled so every vignette runs offline" — singular. Grepping every consumer: `br_amazon` appears only in R/data.R, data-raw/prepare_br_amazon.R, man/br_amazon.Rd and tests/testthat/test-data-regional.R; same for `br_pantanal`. Zero vignettes, zero articles, zero examples, zero exported functions touch them. test-data-regional.R is a schema/range smoke test ("Smoke tests for the v3.7.0 regional synthetic datasets") plus two `al_fit()` calls. So 42 KB of installed data and 2 of the 185 man pages exist to satisfy a single test file, and the README never tells a user they are there.

**Action**

> Either promote them — add a row to README's Bundled datasets section, mention them in DESCRIPTION, and use one of them in a vignette to demonstrate the "any pillar runs unchanged" contract test-data-regional.R asserts — or drop them and their man pages. As shipped they are dead weight that inflates both the install size NOTE and the export/doc counts.

### `llm_annotation_launch()` guards four packages but the Shiny UI calls `DiagrammeR::grVizOutput()` at startup, and the 690-line app has no tests at all (medium, minutes)

**Evidence**

> R/llm_annotation.R:680-684 pre-flights exactly four Suggests: `for (p in c("shiny", "DT", "bslib", "shinyjs")) if (!requireNamespace(p, quietly = TRUE)) stop(sprintf("Install '%s' to launch the annotation app.", p))`. But inst/shiny-apps/annotation/app.R:215 calls `DiagrammeR::grVizOutput("dag_plot", height = "680px")` **inside the UI definition** (plus renderGrViz/grViz at :557, :560, :564, :587), and `DiagrammeR` is Suggests-only with no `requireNamespace` guard anywhere in app.R (grep for `requireNamespace` in app.R returns nothing). Because the call is in the UI, not a lazy render path, the app dies at `shiny::runApp()` with a bare "there is no package called 'DiagrammeR'" — bypassing the package's own friendly-error message — for any user who installed the four advertised packages. The DAG preview is a headline feature (README.md:1657 "with DAG preview, dark mode and Zenodo export"). Separately, `grep -rn "llm_annotation_launch\|shiny-apps" tests/` returns nothing: 690 lines of app code, reachable from an exported function, is untested and — because R CMD check does not parse inst/ — a syntax error there would ship silently (it parses today; I checked).

**Action**

> Add `"DiagrammeR"` to the requireNamespace loop at R/llm_annotation.R:680. Add a test that at minimum `parse()`s inst/shiny-apps/annotation/app.R and asserts every `pkg::` prefix used in it appears in the launcher's guard list — that single test covers both defects and any future drift.

### README's "Testing and continuous integration" section is the fourth mutually incompatible test count and pins its check status to v1.7.0 (medium, minutes)

**Evidence**

> README.md:1670-1685 claims "**109+ unit and integration tests** (`testthat`) covering every public function across the **six** pillars" and "**Local:** `R CMD check --as-cran` → **0 errors / 0 warnings / 0 notes** on **v1.7.0**". That is 20 releases stale, scoped to six pillars, and the figure 109 is off by an order of magnitude against the 460 test_that blocks / 1089 expect_ calls actually present — while coinciding numerically with the live run's 109 *skips*. The project now carries four different test counts in four places: README "109+", NEWS.md v3.10.0 "1 345 tests pass", inst/rosc/submission.md "1 345 expectations", and the live run's 1022 passing + 109 skipped + 2 errors. The same section says optional-dependency tests "are gated by `skip_if_not_installed()`", but the test auditor found 12 divergent hand-rolled skip helpers instead of the canonical one. The release auditor flagged the NEWS chain's arithmetic breaks; the README's own figure was never compared.

**Action**

> Replace the hard-coded count with the actual `devtools::test()` summary (or drop the number and link the codecov badge), scope the sentence to ten pillars, and re-run `R CMD check --as-cran` on 3.10.0 before restating any check status. Given the two reproducible ERRORs, the honest current line is "2 errors", not "0 errors".

### `inst/WORDLIST` ships to users but has no consumer anywhere: `spelling` is not in Suggests and no workflow runs a spell check (low, minutes)

**Evidence**

> inst/WORDLIST exists and (with no `inst/` line in .Rbuildignore) installs into the user's library. But `grep -n "spelling" DESCRIPTION` → nothing (it is absent from the 40-package Suggests list), and `grep -rn "spell\|WORDLIST" .github/workflows/` → nothing across R-CMD-check.yaml, pkgdown.yaml and test-coverage.yaml. There is also no `tests/spelling.R`. So the file is a dictionary for a tool the project does not depend on and never invokes — dead maintainer metadata occupying user disk. The CI auditor noted spell check "exists in prose and templates but in no workflow"; the orphaned artefact and its shipping into the library were not identified.

**Action**

> Add `spelling` to Suggests plus a `tests/spelling.R` with `spelling::spell_check_test(vignettes = TRUE, error = FALSE, skip_on_cran = TRUE)` so the WORDLIST is actually used, and add `^inst/WORDLIST$` handling (spelling expects it at inst/WORDLIST, so instead ensure it is only consumed at check time — or move maintainer-only files to a `.Rbuildignore`d directory).

### `.claude/` holds no project automation and there is no CLAUDE.md; the only cross-project artefact is a live GeoVersa worktree at HEAD — investigated, nothing leaked (low, minutes)

**Evidence**

> The .claude/ directory is gitignored (.gitignore:29 `.claude/`) and contains only `.DS_Store` and `settings.local.json`, whose entire content is `{"permissions":{"allow":["Bash(R --version)"]}}`. `git ls-files .claude/` → empty. There is no CLAUDE.md at the repo root or in .claude/, no committed agents, skills, hooks or slash commands, and no status/roadmap document beyond the ones the eight auditors already read (README roadmap table, R/pillars_roadmap.R, RELEASE.md, RELEASE-CHECKLIST-v3.10.0.md, DESIGN-v1.6.md, INTRO.md, tools/pretrain/V1_3_2_HANDOFF.md). So for a 19.7k-LOC repo built at ~2.5k LOC/day there is zero committed development-process automation — no lint config, no styler config (despite inst/rosc/submission.md claiming styler), no renv.lock, no pre-commit hook, and no .Rproj. On the GeoVersa question: `git worktree list` shows a third, `prunable` worktree at `/Users/rodrigues.h/Library/CloudStorage/OneDrive-Personal/GeoVersa/.claude/worktrees/stoic-elgamal-942d62`, checked out at the same commit `272b378` on a live local branch `claude/stoic-elgamal-942d62` — so edaphos work has been driven from inside a second project's worktree tree. A case-insensitive grep for "geoversa" across the whole tree returns exactly **one** hit, tools/pretrain/V1_3_2_HANDOFF.md:23 `cd /path/to/GeoVersa`, confirming that the hand-off doc's wrong directory name is a real cross-project artefact rather than a typo. No GeoVersa code, data or config leaked into the repository. Also note `GATEOUT.rds` (460-row data.frame of test file/line/gate triples) is untracked in the working root — an audit by-product, not project state, but it means the tree is no longer clean.

**Action**

> Run `git worktree prune` and delete the stale `claude/stoic-elgamal-942d62` branch; fix V1_3_2_HANDOFF.md:23 to `cd /path/to/edaphos`; delete the untracked GATEOUT.rds. If the project is to be maintained, commit a minimal CLAUDE.md (build/test/check commands, the pilar-vs-pillar naming rule, the "no version bump without a NEWS section and a tag" rule) and a `.lintr` — the eight audits' recurring theme is that no automated gate ever compared documents to code.

## 13. Work order

Grouping of the open findings into phases. The grouping is the only
editorial content in this file; it lives in `PHASES` in
[`tools/status/render.R`](tools/status/render.R). Each entry links back to a
finding ID above, so nothing here is a new claim.

### Phase 0 — Make R CMD check truthful

_Nothing else can be verified while the check is red and the release paperwork asserts it is green. Every item here is minutes-to-hours and needed before any claim can be re-stated._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | FF20A54 | blocker | hours | "R CMD check: 0 errors / 0 notes" is false: two test errors reproduce in this tree, and one of them fires specifically in the torch-less CRAN environment that cran-comments.md swears is clean |
| [ ] | F52C0B8 | high | hours | cran-comments.md is self-contradictory and every quantitative claim in it is stale or wrong |
| [ ] | F5F7D9A | high | hours | The "1 345 tests" figure is unreproducible, mis-attributed, and the NEWS test-count chain contains two arithmetic breaks |
| [ ] | FA81F77 | high | minutes | Undeclared `utils` and `tools` namespaces — guaranteed R CMD check WARNING that cran-comments.md denies |
| [ ] | F64B0F0 | high | minutes | R/foundation_finetune.R:41 makes the whole Pillar-4 fine-tuning API require `reticulate`, which it never uses |
| [ ] | FAEC54C | medium | hours | al_fit() performs no validation of num.trees against nrow(labeled), producing an opaque ranger error; the guarding test is unseeded and fails ~12% of runs |
| [ ] | F2F16E8 | medium | hours | cran-comments.md misstates both the check status and the extdata sizes it uses to justify the install-size NOTE |
| [ ] | FC68E1D | medium | minutes | foundation_weights_load() requires torch BEFORE resolving the registry, so the placeholder v2 entry reports the wrong reason for failing |

### Phase 1 — Scientific integrity

_In a research package the empirical claims are the product._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | F2A0EC5 | blocker | days | Shipped IV bundle refutes the README's "decisive test passes" headline: Sargan p = 3.2e-08, not 0.343 |
| [ ] | F862881 | blocker | hours | Every β in the README's real-data causal table disagrees with the shipped bundle, and the confounding correction has the wrong sign for tree cover |
| [ ] | F485937 | high | days | No test validates any headline number or any of the twelve committed result bundles |
| [ ] | F623876 | high | days | `.bench_inject_aleatoric()` manufactures the published PICP with author-chosen noise and silently degrades the published RMSE |
| [ ] | FF375C1 | high | days | The P4 "Foundation" row of the headline "first honest cross-pillar comparison" is computed on a pure Gaussian-noise raster |
| [ ] | F1CD43E | high | hours | R² is floored at zero in three benchmark code paths, censoring negative values and turning them into a "statistically indistinguishable" conclusion |
| [ ] | F30D53B | high | hours | The v1.8.0 multi-backend LLM benchmark is entirely simulated and its headline F1/latency values are hard-coded function arguments |
| [ ] | F884A23 | medium | days | The flagship case-study benchmark cannot be re-run by anyone: its input is .gitignore'd and its output path is not the shipped artefact |
| [ ] | F0F5D47 | medium | hours | Pretrained-weight DOI is real but the v2 registry row is all-NA while claiming a nonexistent version; CITATION.cff and .zenodo.json are many releases stale and assign one DOI to ten releases |
| [ ] | F3467DC | medium | hours | Four mutually incompatible definitions of the headline benchmark's target variable across README, vignette and runner |
| [ ] | F366B1F | medium | hours | README's headline benchmark tables are two to four release cycles stale, and the current 6-method result exists only in NEWS.md |
| [ ] | F54856E | medium | hours | The "LLM-augmented (Gemma 4)" DAG in the causal-discovery trio is six hand-typed edges, not an LLM output |
| [ ] | F5672C5 | medium | hours | DESCRIPTION's "every vignette runs offline" is false: four advertised vignettes are not vignettes, and the Pilar 4 × Pilar 6 vignette evaluates nothing |
| [ ] | FDA80DD | medium | hours | Residual kriging (B2) is fit to in-bag rather than OOB forest residuals, manufacturing the README's PICP conclusion |

### Phase 2 — Version coherence

_One version number, asserted in one place, tagged once._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | F36D2FE | high | hours | The "v3.11.0" work is committed and self-referenced in shipped code, but no version exists: no DESCRIPTION bump, no NEWS section, no tag |
| [ ] | F5EF8F6 | high | hours | Four mutually exclusive citation versions: DESCRIPTION 3.10.0, README 2.8.0, CITATION.cff 2.1.0, CITATION.cff preferred-citation 1.6.0 |
| [ ] | F7DC6A4 | high | minutes | The README's only install command pins a git ref that does not exist (`@v2.8.0`) |
| [ ] | FA01BFB | high | minutes | CITATION.cff assigns the identical DOI 10.5281/zenodo.19710162 to twelve different "Version DOI" entries |
| [ ] | F545DD7 | medium | days | The "ten pillars" identity exists only in the unreleased HEAD; every other metadata artefact still says six |
| [ ] | FB9DA9E | medium | days | The 84 KB README documents nothing after v2.8.0; its only 3.x reference is the version badge |
| [ ] | F00AF5C | medium | hours | Two overlapping release checklists disagree with each other and both claim to be the authoritative list of remaining steps |
| [ ] | FBB414A | medium | hours | .zenodo.json carries no version field at all and its description is frozen at v1.8.0 |
| [ ] | FC9610C | medium | hours | The only DOI badge is a concept DOI the repo itself says resolves to v0.2.0, and nothing after v1.5.0 was ever deposited |
| [ ] | FF84B54 | medium | hours | Two parallel version schemes collide inside a single README table: "v1.x roadmap lines" are interleaved with package 3.x versions, and v3.0.0 means two different things |

### Phase 3 — Close the ten-pillar promise

_DESCRIPTION claims ten pillars; the shipped docs document six._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | FBAF1FD | high | days | DESCRIPTION promises ten research pillars; every document shipped in the CRAN tarball documents six, and pillars 7-10 have no roadmap row, no README section and no vignette |
| [ ] | F873468 | high | hours | foundation_build_cerrado_stack() silently writes a truncated stack to the cache when any geodata fetch fails, then reuses it forever |
| [ ] | F10D9DC | high | minutes | edaphos-cerrado-moco-v2 ships as an all-NA placeholder row in the exported public registry, keyed to a nonexistent package version 3.11.0 |
| [ ] | F9E2C74 | high | minutes | qf_krr_benchmark() clamps R-squared at zero, contradicting the package's own edaphos_r2() and hiding worse-than-mean quantum models |
| [ ] | FD528FC | medium | days | Three exported functions with .Rd pages and pkgdown entries are permanent stop() stubs |
| [ ] | F1E1D2B | medium | hours | Archival metadata (.zenodo.json, CITATION.cff) still describes a six-pillar package that stops at v1.8.0 |
| [ ] | F492008 | medium | hours | Four pkgdown navbar links point at articles pkgdown never builds, and man/edaphos-package.Rd tells users to open a vignette that is not in the package |
| [ ] | FD3DBCB | medium | hours | Two competing release checklists, one stale, pointing at a tarball path that does not exist |
| [ ] | FF7221D | medium | hours | v1.3.2 (MoCo v2 200k-step encoder) is 43 % short of target and the checkpoint exists nowhere in the repository |
| [ ] | F71D795 | medium | hours | The spBayes backend is advertised as an equal peer in README/NEWS/man but predict(), as_edaphos_posterior() and al_query_bhs() all fail on it |
| [ ] | FD825FD | medium | hours | bhs_fit() returns an all-NaN posterior for a rank-deficient design matrix, and the edge-case test is written to accept it |
| [ ] | F2E57CE | medium | minutes | Step 4 of the v1.3.2 hand-off (wire_up_v2_doi.R) matches nothing and silently writes the timestamp into the `url` field |
| [ ] | F9046AE | medium | minutes | bhs_fit()'s rcpp backend is absent from its own @param documentation, and al_query_bhs() rejects it despite the fit being complete |
| [ ] | FFFC52E | medium | minutes | causal_iv bootstrap silently discards failed 2SLS replicates and rewrites B to the survivor count |

### Phase 4 — CRAN submission

_Only meaningful once phases 0-3 hold._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | FCBA23B | high | days | 134 of 169 exported functions have no examples; only 10 have an example R CMD check executes |
| [ ] | FE42047 | high | hours | pkgdown workflow cannot succeed: `has_concept("pilar1")` matches zero topics and 4 navbar links point at pages never built |
| [ ] | FDE7C43 | high | hours | Installed size will NOTE: inst/extdata 9.98 MB + man/figures 2.3 MB, of which a 1.9 MB PNG logo |
| [ ] | F3D7BED | medium | days | 33 of 43 NEWS.md releases have no git tag and there is no release-automation workflow, contradicting CONTRIBUTING's tagging promise |
| [ ] | F5E91CE | medium | days | Dockerfile is not a reproducibility artefact: builds from GitHub main, unpinned libtorch, R 4.4.1 in no CI leg, v2.1.0 metadata, missing Suggests |
| [ ] | F4484D7 | medium | days | 5 of 14 vignettes are written in Portuguese while DESCRIPTION declares `Language: en-US` |
| [ ] | F29E750 | medium | hours | Two competing release checklists contradict each other and describe a deploy action the pkgdown workflow does not use; referenced artefacts do not exist |
| [ ] | F6F101E | medium | hours | CI builds vignettes, but 3 of 14 self-truncate to a one-line stub without libtorch -- and CONTRIBUTING tells contributors to skip vignette building entirely |
| [ ] | F9C6DD9 | medium | hours | Distribution metadata is 9 minor versions stale: CITATION.cff says 2.1.0, README says 2.8.0, .zenodo.json has no version at all |
| [ ] | FD941E5 | medium | hours | cran-comments.md test-suite and install-size figures are contradicted by the tree they describe |
| [ ] | FDC9573 | medium | hours | No CI leg ever installs libtorch: 25% of R/ and 70 of 460 test blocks are unreachable in all three workflows |
| [ ] | F4BEBBD | medium | hours | DESCRIPTION Title/Description violate CRAN style: marketing adjectives, unquoted software names, zero method references |
| [ ] | F83F26A | medium | hours | RELEASE-CHECKLIST-v3.10.0.md instructs the maintainer to upload two artefacts that do not exist, and asserts a green state contradicted by the live test run |
| [ ] | FD3C0C1 | medium | minutes | Chunk option in pilar4-simclr vignette calls `reticulate::` unguarded with broken `&&`/`\|\|` precedence -- hard error in exactly the Docker configuration |
| [ ] | F00A9C3 | medium | minutes | `Depends: R (>= 3.5)` is falsified by two features requiring R 4.0.0 and R 3.6.0 |
| [ ] | F4EC093 | medium | minutes | `src/Makevars.win` documents a Unix `src/Makevars` that does not exist |

### Phase 5 — Code quality and tech debt

_Non-blocking, but cheaper to fix before the API is frozen by CRAN._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | F60AE85 | high | hours | bhs_fit has no rank check on the model matrix: a constant covariate yields NA rgamma rates (the 2 live WARNINGs) then a cryptic Cholesky death |
| [ ] | F8EC452 | high | hours | No CI leg has ever executed the torch code paths: 74 test blocks / 223 expectations / ~3,140 LOC unexercised |
| [ ] | FAC0043 | high | minutes | foundation_weights_load() gates on torch before validating its own arguments — the live ERROR 2 |
| [ ] | FCF64DC | medium | days | Naming schism: pilar/pillar, ordinal/domain module names, al_* vs active_*, and five undocumented cryptic export prefixes |
| [ ] | FD27999 | medium | days | Twelve exported functions are never referenced anywhere in tests/, including the entire advertised tile-source pipeline |
| [ ] | FB6D884 | medium | days | 12 exported functions are never called by any test, including the entire tile-download layer and a function that recursively deletes a directory |
| [ ] | FBCB1E4 | medium | days | The v3.8.0 friendly-error work covers 4 of 169 exports; .assert_type/.stopf adopted in 6 of 70 R/ files |
| [ ] | F0E4DC1 | medium | hours | Pillars 8/9/10 default backend="r" never trains the architecture it is named after, while DESCRIPTION/README mark them "implemented" |
| [ ] | F3E0E05 | medium | hours | gnn_embed() returns a different column count per backend and its documented @return is wrong for backend="torch" |
| [ ] | F4ED689 | medium | hours | Rank-deficient design matrix poisons the entire BHS Gibbs chain to NA on iteration 1, then hard-errors — and the test's own comment about it is wrong |
| [ ] | F7EC076 | medium | hours | Twelve copies of skip_if_no_torch() in three divergent flavours, orphaning the helper-torch.R that was added to replace them |
| [ ] | F86487C | medium | hours | R/pilar7_bayesian_hierarchical.R:270-272 cites a test that does not perform the verification it claims |
| [ ] | FA6ECC8 | medium | hours | The RcppArmadillo BHS Gibbs backend has no real numerical-agreement test: one scalar mean at 0.2 tolerance, w_post_mean never compared, no edge cases |
| [ ] | F215985 | medium | minutes | Off-by-one in the RcppArmadillo BHS backend biases w_post_mean, silently corrupting every predict.edaphos_bhs() for backend="rcpp" |
| [ ] | FBDE0E9 | medium | minutes | al_fit(num.trees=) has no lower bound against ranger's undocumented OOB-quantile minimum, and the test that breaks is unseeded — a ~25% flaky ERROR |
| [ ] | FC841F7 | medium | minutes | Same loop-invariant matrix product recomputed n_draws times, copy-pasted into two files |
| [ ] | F21DBBA | medium | minutes | test-foundation-weights.R:29-36 asserts an error message that is unreachable without torch (live ERROR 2) -- green on CI, red on CRAN |
| [ ] | F2C0D91 | medium | minutes | al_fit is ~14.5%-flaky by construction: test-active-quantum-posterior.R:30-35 has no set.seed and passes num.trees=50 for OOB quantile regression (live ERROR 1) |
| [ ] | FB609A4 | medium | minutes | NEWS.md v3.10.0 test and check claims are not reproducible in any environment the project automates |
| [ ] | FC5841E | medium | minutes | Three of four wall-clock assertions run on CRAN: only 1 skip_on_cran() exists in the whole 460-block suite |

### Unphased

| Done | ID | Sev | Area | Item |
| --- | --- | --- | --- | --- |
| [ ] | F0BC16C | blocker | CI & infra | "CI green" and "0 errors \| 0 warnings \| 0 notes" are asserted in release docs while a dependency-independent test error would redden all 5 matrix legs |
| [ ] | F0CBFC4 | low | CI & infra | test-coverage has no threshold gate, no codecov.yml, and diverges from R-CMD-check on TORCH_INSTALL; reported coverage has an invisible ~75% ceiling |
| [ ] | F6330AE | low | CI & infra | pkgdown site loads mermaid from a third-party CDN with no integrity attribute, on a surface SECURITY.md declares in scope |
| [ ] | FA46190 | low | CI & infra | Documented quality gates (spell check, URL check, lint) exist in prose and templates but in no workflow; `_R_CHECK_FORCE_SUGGESTS_` is never relaxed across 40 Suggests |
| [ ] | FAACA6C | low | CI & infra | `needs: website` and `needs: coverage` are no-ops: DESCRIPTION declares no Config/Needs/* fields |
| [ ] | FAF9367 | low | CI & infra | .Rbuildignore hygiene: version-pinned checklist pattern, duplicated entry, dead README.Rmd rule |
| [ ] | FDA19FA | low | CI & infra | No dependency pinning outside the Dockerfile; floating action tags in a job granted `contents: write` |
| [ ] | F434C69 | low | Code quality | %\|\|% is copy-pasted into 7 files; the definition that actually wins is decided by alphabetical collation, not by design |
| [ ] | F503F9C | low | Code quality | quantum_kernel_rcpp allocates nX * 2^n complex states but its only guard is a warning keyed on n alone |
| [ ] | F594BF7 | low | Code quality | Dead code, an undocumented non-dotted internal, and three comment/code contradictions in the pillar 7-10 modules |
| [ ] | FA36407 | low | Code quality | The v3.8.0 friendly-error system covers ~5% of failure sites and exactly the 6 files that got a test; 136 raw stop() and 13 divergent torch gates bypass it |
| [ ] | FB51F5F | low | Code quality | history[history > 0] injects NA into fit$history; the fix exists in all four torch files and none of the three pure-R files |
| [ ] | FFAFBF2 | low | Code quality | 169 exports + 73 S3 methods is an exceptionally wide public API for 19.7k LOC, with several internal-looking primitives promoted to the surface |
| [ ] | F4516A9 | low | CRAN readiness | Maintainer-only files install into the user's library; CITATION metadata is stale and there is no inst/CITATION |
| [ ] | F5825EA | low | CRAN readiness | 6 of 40 Suggests are never used anywhere in the package |
| [ ] | FEC2806 | low | CRAN readiness | `MASS::ginv()` called unguarded at 5 sites while MASS is Suggests-only |
| [ ] | FEDA31F | low | CRAN readiness | Two network entry points call `httr2::req_perform()` with no error handling, against CRAN's graceful-failure policy |
| [ ] | FF58F4E | low | CRAN readiness | Two exported functions are unconditional `stop()` stubs, documented and counted as shipped features |
| [ ] | F63C7AD | low | Release consistency | Placeholder and NA DOIs are committed: the exported weights registry advertises an encoder with no URL, DOI or checksum |
| [ ] | F6C4FB9 | low | Release consistency | _pkgdown.yml's release list stops at v2.0.0 and its site description still says six pillars |
| [ ] | FA7F096 | low | Release consistency | RELEASE-CHECKLIST-v3.10.0.md instructs the maintainer to upload artefacts that do not exist and names the wrong deploy action |
| [ ] | FEA55C5 | low | Release consistency | 32 of the last 33 NEWS releases have no git tag, violating the project's own documented release policy |
| [ ] | FFBBEBB | low | Release consistency | Dockerfile self-identifies as v2.1.0 and pins a 2026-04-23 CRAN snapshot, but installs HEAD |
| [ ] | F1A720B | low | Roadmap promises | v1.8.3 (expand LLM gold standard from 72 to 300 claims) is untouched — still 30 abstracts / 72 claims |
| [ ] | F2FC8F9 | low | Roadmap promises | V1_3_2_HANDOFF.md instructs the maintainer to cd into a directory named after a different project |
| [ ] | F3E4CA6 | low | Roadmap promises | Documentation promises that point at content which does not exist: cheatsheets "on the pkgdown site", P8/P9 benchmarks "in vignettes/" |
| [ ] | F4BEE44 | low | Roadmap promises | package_v2_for_zenodo.R fails with a cryptic stopifnot before its own step-count guard, and drops the resume hint from its error message |
| [ ] | F4EE43C | low | Roadmap promises | Roadmap table and NEWS were never updated for the last two feature commits; DESCRIPTION 3.10.0 conflicts with the 3.11.0 baked into the weights registry |
| [ ] | F66D149 | low | Roadmap promises | Stale dead-end in data-raw/causal_iv_benchmark.R blocks a path that v1.9.1 already delivered |
| [ ] | F9EDEBA | low | Roadmap promises | Pilar 7 was promised as INLA/Stan and delivered as a hand-rolled Gibbs sampler; the substitution is never disclosed |
| [ ] | FCC0D53 | low | Roadmap promises | Promised production-scale outputs never produced: the 10k-abstract LLM-KG run and the 6-pillar benchmark wrapper set |
| [ ] | F37E56E | low | Incomplete implementations | foundation_embed_at_coords() converts a failed raster block read into an all-zero patch that is indistinguishable from a real embedding |
| [ ] | F3A34C0 | low | Incomplete implementations | foundation_build_cerrado_stack() calls digest::digest() unguarded, but digest is Suggests-only -- the exported function dies on a clean install |
| [ ] | F3CACF8 | low | Incomplete implementations | Off-by-one in the RcppArmadillo Gibbs sampler's w_post_mean accumulation makes the rcpp backend disagree with the R backend it claims to reproduce |
| [ ] | F52B874 | low | Incomplete implementations | Two exported functions ship without \value in man/, contradicting the NEWS claim of 0 R CMD check notes |
| [ ] | F649AF8 | low | Incomplete implementations | Stale forward-looking version markers and dead code left in shipped R/ sources |
| [ ] | FBDF515 | low | Incomplete implementations | quantum_kernel() with the default rcpp backend has only a warning where it needs a hard cap, and silently returns an all-ones kernel for reps <= 0 |
| [ ] | F1A5FC0 | low | Test coverage | 12 duplicated, semantically divergent torch skip helpers shadow the canonical helper-torch.R; the package's own runtime guards never check torch_is_installed() |
| [ ] | F3CED48 | low | Test coverage | 44 print/summary S3 methods, zero snapshot tests, 15 expect_output calls -- half of them behind torch/qiskit gates |

## 14. Regenerating this document

```sh
# 1. real check log (needed for section 5)
R CMD build . && R CMD check --as-cran edaphos_*.tar.gz 2>&1 | tee /tmp/check.log

# 2. measure, then render
Rscript tools/status/facts.R --check-log=/tmp/check.log
Rscript tools/status/render.R
```

`tools/status/facts.json` is the measurement snapshot and is regenerated in
full each run. `tools/status/findings.json` is frozen audit input: edit it only
to record a finding as resolved, never to change a measured number.

