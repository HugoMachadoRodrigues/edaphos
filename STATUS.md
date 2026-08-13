<!-- GENERATED FILE -- DO NOT EDIT BY HAND.
     Regenerate:  Rscript tools/status/facts.R [--check-log=LOG]
                  Rscript tools/status/render.R                     -->

# edaphos — development status

**Commit** `8e725b9` (`main`) — **DESCRIPTION version** `0.9.0` — **measured** 2026-08-13T04:00:09Z

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
| Commits | 173 |
| First → last commit | 2026-04-20 → 2026-08-12 (114.0 calendar days, 19 with commits) |
| Days since last commit | 0 |
| NEWS release sections | 1 |
| Git tags | 19 |
| NEWS versions with no tag | 0 |
| R/ source lines | 30 768 |
| Exported functions | 178 |
| Test blocks | 601 |
| Tests passing | 2 192 |
| Tests skipped | 1 |
| Test failures + errors | 0 |
| R CMD check status | Status: 2 NOTEs |
| Source tarball (CRAN cap 5 MB) | 5.32 MB |
| Findings open (blocker/high) | 9 |
| Findings closed since the audit | 47 |

### Stage assessment

From the audit's completeness critic (editorial, not measured). It describes the tree at `272b378`, not at `8e725b9`: several of the specifics it cites have since been closed — see "Closed since the audit" in section 11 for which ones, and on what measurement. The verdict is quoted unedited because a stage assessment that gets revised alongside the work it judges is worth nothing.

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
| OS | Darwin 25.6.0 |
| Worktree clean | no |
| Local vs origin/main | `2 / 0` (ahead / behind) |
| Optional deps missing | 5 |

Suggests **not installed** in the measuring environment: `DiagrammeR`, `ecmwfr`, `fmsb`, `ontologyIndex`, `spBayes`.
Every test and vignette gated on these is skipped, so the pass counts below
are a floor, not a total.

## 3. The git clock

`8e725b9` — 173 commits across 19 active days.

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
| 2026-07-26 | 6 |
| 2026-07-27 | 4 |
| 2026-07-28 | 1 |
| 2026-07-29 | 9 |
| 2026-07-30 | 12 |
| 2026-08-03 | 6 |
| 2026-08-04 | 11 |
| 2026-08-05 | 25 |
| 2026-08-10 | 2 |
| 2026-08-11 | 6 |
| 2026-08-12 | 9 |

Releases declared in `NEWS.md`: **1**. Git tags: **19**.
Tags present: `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.4.0`, `v0.5.0`, `v0.6.0`, `v0.7.0`, `v0.8.0`, `v0.9.0`, `v1.0.0`, `v1.1.0`, `v1.2.0`, `v1.3.0`, `v1.3.1`, `v1.4.0`, `v1.5.0`, `v1.6.0`, `v3.10.0`, `v4.0.0`.
Commits since the newest tag (`v4.0.0`): **84**.

## 4. Version coherence

| Check | Result |
| --- | --- |
| DESCRIPTION version equals newest NEWS section | ✅ (DESCRIPTION `0.9.0`, NEWS `0.9.0`) |
| DESCRIPTION version has a git tag | ✅ (`v0.9.0`) |
| HEAD is the tagged release commit | ❌ (84 commits past `v4.0.0`) |
| Every NEWS release is tagged | ❌ (0 of 1 untagged; 1 tagged at a commit that predates the entry: `0.9.0`) |

Version strings each artefact claims for the package:

| Artefact | Claims |
| --- | --- |
| DESCRIPTION | `0.9.0` |
| NEWS.md | `0.9.0` |
| README.md | _none_ |
| CITATION.cff | `0.9.0` |
| .zenodo.json | has a version field |

Version strings asserted inside shipped `R/` or `man/` that **neither a `NEWS.md` section nor a git tag declares** (23): `3.1.0`, `3.4.0`, `3.0.0`, `2.0.0`, `2.2.1`, `1.9.0`, `1.9.2`, `3.8.0`, `2.1.0`, `1.9.1`, `1.8.1`, `1.8.0`, `2.7.0`, `2.6.0`, `3.6.0`, `2.3.0`, `3.5.0`, `3.2.0`, `2.4.0`, `4.1.0` … (+3 more). Each names a release that never existed.

| File | Line | Version |
| --- | --: | --- |
| `R/benchmark_wosis.R` | 1 | `3.1.0` |
| `R/benchmark_wosis.R` | 21 | `3.4.0` |
| `R/benchmark_wosis.R` | 29 | `3.1.0` |
| `R/benchmark_wosis.R` | 34 | `3.4.0` |
| `R/benchmark_wosis.R` | 143 | `3.1.0` |
| `R/benchmark_wosis.R` | 158 | `3.1.0` |
| `R/bridges_active_learning_v3.R` | 1 | `3.0.0` |
| `R/bridges_structure_v3.R` | 1 | `3.0.0` |
| `R/bridges_structure_v3.R` | 338 | `2.0.0` |
| `R/causal_4d_bridge.R` | 2 | `2.2.1` |
| `R/causal_iv.R` | 1 | `1.9.0` |
| `R/causal_sensitivity.R` | 1 | `1.9.2` |
| `R/core_utils.R` | 29 | `3.8.0` |
| `R/edaphos_zenodo_release.R` | 1 | `2.1.0` |
| `R/foundation_embed_coords.R` | 1 | `1.9.1` |
| `R/foundation_embed_coords.R` | 8 | `1.9.0` |
| `R/foundation_embed_coords.R` | 15 | `1.9.0` |
| `R/foundation_embed_coords.R` | 24 | `1.9.1` |
| `R/llm_annotation.R` | 1 | `1.8.1` |
| `R/llm_annotation.R` | 4 | `1.8.0` |
| `R/llm_benchmark.R` | 1 | `1.8.0` |
| `R/pilar10_graph_nn_torch.R` | 1 | `2.7.0` |
| `R/pilar10_graph_nn_torch.R` | 3 | `2.6.0` |
| `R/pilar10_graph_nn.R` | 2 | `2.6.0` |
| `R/pilar10_graph_nn.R` | 222 | `3.6.0,2.6.0` |
| `R/pilar10_graph_nn.R` | 226 | `2.6.0` |
| `R/pilar10_graph_nn.R` | 247 | `2.6.0` |
| `R/pilar10_graph_nn.R` | 472 | `2.7.0` |
| `R/pilar7_bayesian_hierarchical.R` | 1 | `2.3.0` |
| `R/pilar7_bayesian_hierarchical.R` | 58 | `2.3.0` |
| `R/pilar7_bayesian_hierarchical.R` | 420 | `3.5.0` |
| `R/pilar7_bayesian_hierarchical.R` | 421 | `3.2.0` |
| `R/pilar7_bayesian_hierarchical.R` | 480 | `3.2.0` |
| `R/pilar7_bayesian_hierarchical.R` | 493 | `2.3.0` |
| `R/pilar8_neural_operators_torch.R` | 1 | `2.7.0` |
| `R/pilar8_neural_operators_torch.R` | 3 | `2.4.0` |
| `R/pilar8_neural_operators.R` | 2 | `2.4.0` |
| `R/pilar8_neural_operators.R` | 59 | `4.1.0` |
| `R/pilar9_diffusion_models.R` | 2 | `2.5.0` |
| `R/pilar9_diffusion_models.R` | 168 | `3.2.0` |
| `R/pilar9_diffusion_models.R` | 340 | `3.2.0` |
| `R/pilar9_diffusion_torch.R` | 2 | `2.7.0` |
| `R/pilar9_diffusion_torch.R` | 4 | `2.5.0` |
| `R/piml_quantum_bridge.R` | 2 | `2.2.0` |
| `R/piml_quantum_bridge.R` | 34 | `2.0.0` |
| `R/quantum_foundation.R` | 2 | `2.0.0` |
| `R/quantum_foundation.R` | 390 | `2.0.0` |
| `R/quantum_foundation.R` | 530 | `2.0.0` |
| `R/quantum_kernel.R` | 185 | `2.1.3` |
| `man/benchmark_fit_p1_causal.Rd` | 35 | `3.1.0` |
| `man/benchmark_fit_p1_causal.Rd` | 46 | `3.1.0` |
| `man/bhs_fit.Rd` | 85 | `2.3.0` |
| `man/gnn_fit.Rd` | 73 | `2.7.0` |
| `man/qf_krr_benchmark.Rd` | 43 | `2.0.0` |

Conversely, git tags with **no `NEWS.md` section**: `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.4.0`, `v0.5.0`, `v0.6.0`, `v0.7.0`, `v0.8.0`, `v1.0.0`, `v1.1.0`, `v1.2.0`, `v1.3.0`, `v1.3.1`, `v1.4.0`, `v1.5.0`, `v1.6.0`, `v3.10.0`, `v4.0.0`.

## 5. `R CMD build` / `R CMD check --as-cran`

| Result | Value |
| --- | --- |
| Status | Status: 2 NOTEs |
| ERRORs | 0 |
| WARNINGs | 0 |
| NOTEs | 2 |

Counts are taken from R's own `Status:` line; an independent walk of the log agrees.

**NOTES:**

- `checking CRAN incoming feasibility`
- `checking for detritus in the temp directory`

**INFOS:**

- `checking package dependencies`
- `checking installed package size`

#### `checking CRAN incoming feasibility`

| Field | Value |
| --- | --- |
| Maintainer | `Hugo Rodrigues <rodrigues.machado.hugo@gmail.com>` |
| CRAN status | **New submission** — R's own confirmation that nothing named `edaphos` exists on CRAN |
| Tarball size | 5.32 MB measured on disk — the log prints this only above its own threshold (CRAN guidance: 5.00 MB) |
| URLs flagged as invalid | 0 |

Suggests unavailable to the check (so their tests and vignette chunks were skipped): 'DiagrammeR', 'ecmwfr', 'fmsb', 'ontologyIndex', 'spBayes'.

Installed size, verbatim from the log:

```
  installed size is  8.4Mb
  sub-directories of 1Mb or more:
    doc       3.2Mb
    extdata   2.2Mb
    help      1.5Mb
```

Log: `tools/status/check.log` (98 lines, sha256 `40a6ffca0e46c061`). Verbatim tail:

```
* checking examples ... [102s/100s] OK
* checking examples with --run-donttest ... [716s/542s] OK
* checking for unstated dependencies in tests ... OK
* checking tests ...
  Running testthat.R [546s/531s]
 [546s/531s] OK
* checking for unstated dependencies in vignettes ... OK
* checking package vignettes ... OK
* checking re-building of vignette outputs ... [284s/274s] OK
* checking for non-standard things in the check directory ... OK
* checking for detritus in the temp directory ... NOTE
Found the following files/directories:
  tmp_5fp7pqq
* DONE
Status: 2 NOTEs
See
  /Users/rodrigues.h/Library/CloudStorage/OneDrive-Personal/edaphos/edaphos.Rcheck/00check.log
for details.
```

#### Each reported item: package defect or measuring environment?

Item names and levels come from the log above; the classification and
source attribution are editorial and live in [`tools/status/check-classification.json`](tools/status/check-classification.json).

| Item | Level | Class | Blocks CRAN | Source |
| --- | --- | --- | --- | --- |
| `checking CRAN incoming feasibility` | NOTE | environment | no | README.md (https://hugomachadorodrigues.github.io/edaphos needs a trailing slash) and inst/doc/case-cerrado-end-to-end.html (https://github.com/ipeaGIT/geobr moved to https://github.com/ipea/geobr); both fixed. Tarball was 15734027 bytes at the baseline commit and is 6740328 bytes now. |
| `checking tests` | ERROR | **defect** | yes | tests/testthat/test-foundation-weights.R:33 and tests/testthat/test-active-quantum-posterior.R:34 |
| `checking PDF version of manual` | WARNING | **defect** | yes | R/foundation_finetune.R:165 (U+2265 GREATER-THAN OR EQUAL) and R/foundation_finetune.R:436 (U+2208 ELEMENT OF); man/*.Rd is roxygen-generated so the fix must land in R/ and be re-documented. |
| `checking PDF version of manual without index` | ERROR | **defect** | yes | R/foundation_finetune.R:165,436 |
| `checking Rd files` | NOTE | **defect** | no | R/foundation_embed_coords.R:207 |
| `checking installed package size` | INFO | **defect** | no | inst/doc (vignette HTML rendered at build time), inst/extdata (result bundles), man/figures |
| `checking for hidden files and directories` | NOTE | **defect** | no | .Rbuildignore |
| `checking top-level files` | NOTE | **defect** | no | v4.1.0: figure/ (knitr fig.path default when a vignette is knitted outside vignettes/). Baseline: GATEOUT.rds. |
| `checking HTML version of manual` | NOTE | environment | no | measuring machine |
| `checking for non-standard things in the check directory` | NOTE | environment | no | consequence of the PDF-manual failure above |
| `checking for detritus in the temp directory` | NOTE | **defect** | no | Not the LaTeX run, as first assumed: the NOTE persists after the PDF manual builds cleanly. The directory is named tmp<8 chars> and differs on every run (tmph7u64pdz, tmpl_pg5ehe, tmpspsyky6e), which is Python's tempfile.mkdtemp() pattern, not R's file<hex>. It comes from the optional qiskit / PySCF bridge reached through reticulate in R/quantum_vqe.R, R/quantum_nature.R and R/quantum_ibmq.R. |
| `R CMD build (vignettes)` | ERROR | **defect** | no | vignettes/pilar1-causal.Rmd:58-65 |
| `checking package dependencies` | INFO | environment | no | measuring machine; see the Test environments section |

Of 13 reported items, **9 are package defects** and 3 are artefacts of this measuring environment. 3 block CRAN acceptance.

Fixes, per item:

- `checking CRAN incoming feasibility` — Nothing to fix: 'New submission' is accurate. Recorded because it is R's own confirmation that nothing named edaphos exists on CRAN, which contradicts every artefact implying the package is released.
- `checking tests` — See findings FC68E1D (move .moco_require_torch below the argument validation in R/foundation_weights.R) and FAEC54C (validate num.trees in R/active_fit.R, seed the test).
- `checking PDF version of manual` — Replace with \eqn{\ge} / \eqn{\in} or ASCII, then roxygen2::roxygenise(). The 165 em-dashes and 18 en-dashes in Rd are safe -- R's Rd-to-LaTeX pass maps them.
- `checking PDF version of manual without index` — Resolved by the same change.
- `checking Rd files` — Use \eqn{\sim} or the word 'about'.
- `checking installed package size` — See finding FDE7C43, but note its arithmetic is stale: the 1.9 MB logo it names is now 299 KB. The largest contributor is no longer committed payload at all -- inst/doc is 38% of the tarball and 72% of that is base64 figure data inlined by rmarkdown::html_vignette, so lowering vignette figure sizes reduces the tarball without moving a single tracked file.
- `checking for hidden files and directories` — Add ^\.git$. Note this surfaces here because the build ran from a git worktree, where .git is a plain file rather than a directory; adding the pattern makes the build correct from either layout.
- `checking top-level files` — Removed the directory and added a permanent guard -- `^figure$` in .Rbuildignore and `figure/` in .gitignore -- so a stray knit cannot reach the tarball again.
- `checking HTML version of manual` — None needed in the package.
- `checking for non-standard things in the check directory` — Disappears once the Unicode fix lands.
- `checking for detritus in the temp directory` — Have the Python bridge clean up the directories it creates (or create them under tempdir() and remove them on.exit). Only appears on machines where the optional Python stack is installed, so it would not fire on CRAN, where reticulate-gated tests skip.
- `R CMD build (vignettes)` — Guard the chunk with requireNamespace('dagitty') (the pattern the R/ code already uses via .causal_require_dagitty), or set eval=FALSE with a precomputed result, as the other heavy vignettes do.
- `checking package dependencies` — None needed in the package. CRAN installs Suggests, so this INFO does not appear there.

> **checking CRAN incoming feasibility**: 'New submission' is R's own confirmation that nothing named edaphos exists on CRAN, at version 3.10.0 with 43 NEWS releases behind it.

> **R CMD build (vignettes)**: CRAN installs Suggests, so this would not block CRAN itself -- but it does block every contributor and any reproduction attempt on a lean machine, and it falsifies the offline claim.

### Rd portability (the source of the PDF-manual check items)

`man/*.Rd` files containing characters outside latin1: **67** of 191. Most are cosmetic — R's Rd-to-LaTeX pass maps dashes and ellipses. Distinct characters found:

| Character | Codepoint | Occurrences | Breaks LaTeX |
| --- | --- | --: | :-: |
| <U+2014> | `U+2014` | 199 | ❌ |
| <U+2013> | `U+2013` | 21 | ❌ |
| <U+0107> | `U+0107` | 3 | ✅ |
| <U+010D> | `U+010D` | 3 | ✅ |
| <U+2026> | `U+2026` | 1 | ❌ |

`man/` is roxygen-generated, so the fix belongs in `R/`. Exact source lines:

| Source | Line |
| --- | --- |
| `R/edaphos-package.R:182` | #'     (Veli\enc{<U+010D>}{c}kovi\enc{<U+0107>}{c} et al., 2018) over a k-NN |
| `R/pilar10_graph_nn.R:478` | #' Veli\enc{<U+010D>}{c}kovi\enc{<U+0107>}{c}, P., Cucurull, G., Casanova, A., Romero, |
| `R/pillars_roadmap.R:19` | #' \| 10. Graph Neural Networks        \| `gnn_*`        \| implemented \| Graph Attention Network (Veli\enc{<U+010D>}{c}kovi\enc{<U+0107>}{c} et al., 2018) over a k-NN co-location graph of profiles ([gnn_build_graph()], with `edges = "spatial"`, `"feature"` or `"hybrid"` and optional self-loops). [gnn_fit()] trains multi-head attention \eqn{\alpha_{ij} = \mathrm{softmax}_j(\mathrm{LeakyReLU}(a^\top [Wh_i \Vert Wh_j]))} by analytic reverse-mode gradients through the grouped softmax <U+2014> verified against central finite differences <U+2014> with residual connections, head averaging, a transductive `train_mask` and a closed-form ridge readout. [gnn_fit_ensemble()] averages seeds so the comparison against a quantile regression forest is between two ensembles rather than one model and a forest; [gnn_embed()] exposes the learned node embeddings and [gnn_causal_discovery()] feeds them to Pillar 1's structure learner. \| |

## 6. Test suite

| Measure | Value |
| --- | --- |
| Test files | 92 |
| `test_that` blocks | 601 |
| `expect_*` calls | 1 685 |
| `skip_if_not_installed` gates | 85 |
| `skip_on_cran` gates | 13 |
| `set.seed` calls | 144 |

Live run in this environment:

| Outcome | Count |
| --- | --- |
| Passed | 2 192 |
| Skipped | 1 |
| Failed | 0 |
| Errored | 0 |
| Warnings | 4 |
| Wall clock (s) | 495.4 |

Conditional skipping by dependency (static gate count):

| Dependency | Gate sites | Installed here |
| --- | --: | :-: |
| torch | 18 | ✅ |
| igraph | 11 | ✅ |
| dagitty | 10 | ✅ |
| terra | 5 | ✅ |
| bnlearn | 4 | ✅ |
| reticulate | 2 | ✅ |
| dbarts | 1 | ✅ |

Result bundles in `inst/extdata/`: **29**. Test files that read `inst/extdata`: `test-al-policy-claims.R`, `test-bundle-provenance.R`, `test-causal-real-bundle.R`, `test-extrapolation-claims.R`, `test-headline-claims.R`, `test-llm-annotation.R`, `test-no-masked-loss.R`, `test-piml-closed-form.R`, `test-piml-convergence-verdict.R`, `test-piml-coverage-claims.R` … (+4 more).

Exported functions never named in any test (**14**): `causal_ontology_agrovoc`, `causal_ontology_envo`, `edaphos_zenodo_release`, `foundation_build_cerrado_stack`, `foundation_tile_source_era5`, `foundation_tile_source_modis`, `foundation_tile_source_soilgrids`, `foundation_tile_source_srtm`, `foundation_tile_source_worldclim`, `gnn_fit_ensemble`, `llm_annotation_launch`, `piml_neural_ode_predict`, `piml_profile_fit_mechanistic`, `temporal_convlstm_predict`.

## 7. Documentation coverage

| Measure | Value |
| --- | --- |
| `man/*.Rd` files | 191 |
| Rd with `\examples` | 180 |
| — wrapping `\dontrun` | 43 |
| — wrapping `\donttest` | 12 |
| — with an example `R CMD check` runs | 125 |
| Exports with no example anywhere | 0 |
| Exports with no `.Rd` | 0 |
| Rd with `\references` | 36 |
| Vignettes | 19 |
| Root `articles/` | 4 |
| Cheatsheets | 11 |
| README size | 111 KB |

"six pillars" vs "ten pillars", counted per file:

| File | says "six" | — unqualified | says "ten" |
| --- | --: | --: | --: |
| DESCRIPTION | 0 | 0 | 1 |
| R/pillars_roadmap.R | 0 | 0 | 1 |
| R/edaphos-package.R | 0 | 0 | 2 |
| README.md | 4 | 0 | 4 |
| CITATION.cff | 1 | 0 | 1 |
| .zenodo.json | 1 | 0 | 1 |
| _pkgdown.yml | 1 | 0 | 1 |

"— unqualified" excludes occurrences whose surrounding sentence scopes them to a past release. Those are correct history. No file makes an unqualified six-pillar claim.

Occurrences of `getting-started` in README.md: **0**.

Function names called in `pilar1.md`, `pilar10.md`, `pilar2.md`, `pilar3.md`, `pilar4.md`, `pilar5.md`, `pilar6.md`, `pilar7.md`, `pilar8.md`, `pilar9.md`, `README.md`, `INTRO.md` that are **defined nowhere** in `R/` (**9** of 43 referenced): `al_batchbald`, `foundation_finetune`, `foundation_moco_fit`, `foundation_simclr_fit`, `foundation_tile_raster`, `gnn_gat_layer`, `piml_default_prior`, `temporal_convlstm_forecast`, `temporal_cube_build`.

## 8. Install size

| Directory | Size | Ships in tarball |
| --- | --: | :-: |
| `paper` | 19.23 MB | ❌ |
| `inst` | 2.20 MB | ✅ |
| `man` | 1.36 MB | ✅ |
| `R` | 1.31 MB | ✅ |
| `tools` | 707 KB | ❌ |
| `data-raw` | 497 KB | ❌ |
| `tests` | 460 KB | ✅ |
| `<root>` | 377 KB | ✅ |
| `vignettes` | 356 KB | ✅ |
| `data` | 64 KB | ✅ |
| `articles` | 43 KB | ❌ |
| `src` | 16 KB | ✅ |
| `cheatsheets` | 16 KB | ❌ |
| `.github` | 10 KB | ❌ |

Git-tracked bytes that ship: **5.89 MB**. That is not the figure CRAN applies its 5 MB guidance to — the built tarball is, and it is larger, because `R CMD build` renders the vignettes into `inst/doc`, which does not exist in the repository.

Largest tracked files that ship:

| File | Size |
| --- | --: |
| `inst/extdata/case_cerrado_results.rds` | 351 KB |
| `inst/extdata/capstone_native_calibration.rds` | 294 KB |
| `inst/extdata/capstone_campaign_results.rds` | 287 KB |
| `man/figures/logo.png` | 287 KB |
| `inst/extdata/temporal_cerrado_results.rds` | 194 KB |
| `inst/extdata/causal_sensitivity_cerrado.rds` | 142 KB |
| `inst/extdata/piml_external_anchors.rds` | 124 KB |
| `man/figures/pillar6-quantum.png` | 121 KB |
| `inst/extdata/piml_depth_benchmark.rds` | 113 KB |
| `README.md` | 111 KB |
| `inst/extdata/cerrado_claims_real_corpus.jsonl` | 94 KB |
| `man/figures/pillar5-al-map.png` | 86 KB |

### Where the tarball's bytes are

`edaphos_0.9.0.tar.gz` is **5.32 MB** compressed, against the CRAN 5 MB guidance (5.00 MB) — **over by 326 KB**. The shares below are of its 8.99 MB uncompressed contents (495 files), measured by unpacking it; gzip does not compress the two big contributors evenly, so treat them as shares, not as MB off the cap.

| Directory | Size | Share | In the repo |
| --- | --: | --: | :-: |
| `inst/doc` | 3.10 MB | 34% | ❌ |
| `inst/extdata` | 2.15 MB | 24% | ✅ |
| `R` | 1.31 MB | 15% | ✅ |
| `man/figures` | 705 KB | 8% | ✅ |
| `man` | 687 KB | 7% | ✅ |
| `tests/testthat` | 460 KB | 5% | ✅ |
| `vignettes` | 356 KB | 4% | ✅ |
| `<root>` | 146 KB | 2% | ✅ |
| `data` | 64 KB | 1% | ✅ |
| `inst/shiny-apps` | 28 KB | 0% | ✅ |
| `inst` | 17 KB | 0% | ✅ |
| `src` | 16 KB | 0% | ✅ |
| `inst/rosc` | 8 KB | 0% | ✅ |
| `build` | 1 KB | 0% | ✅ |
| `tests` | 0 KB | 0% | ✅ |

`inst/doc` is 2.65 MB of rendered vignette HTML in 19 files, of which **1.60 MB (60%) is base64 image data inlined as `data:` URIs**. Base64 costs 4 bytes for every 3, so that payload is ~1.20 MB of PNG carried at 1.60 MB. It is generated at build time from the figure sizes in `vignettes/*.Rmd`, which means it is the one large contributor that can be reduced without moving a single committed file.

| Vignette HTML | Size | of it base64 |
| --- | --: | --: |
| `capstone-cerrado-campaign.html` | 769 KB | 587 KB |
| `case-cerrado-end-to-end.html` | 251 KB | 216 KB |
| `pilar6-quantum.html` | 192 KB | 122 KB |
| `pilar1-pilar4-iv.html` | 189 KB | 113 KB |
| `edaphos-paper.html` | 134 KB | 100 KB |
| `pilar4-simclr-embeddings.html` | 166 KB | 90 KB |

## 9. CI and infrastructure

Workflows (3): `pkgdown.yaml`, `R-CMD-check.yaml`, `test-coverage.yaml`.

`R-CMD-check` matrix legs:

- `- {os: macos-latest,   r: 'release'}`
- `- {os: windows-latest, r: 'release'}`
- `- {os: ubuntu-latest,  r: 'devel',   http-user-agent: 'release'}`
- `- {os: ubuntu-latest,  r: 'release'}`
- `- {os: ubuntu-latest,  r: 'oldrel-1'}`
- `- {os: ubuntu-latest,  r: 'release', torch: true}`

`TORCH_INSTALL` setting found in the workflows: `TORCH_INSTALL: ${{ matrix.config.torch && '1' || '0' }}` — 1 of 6 matrix legs carry `torch: true` and install libtorch, so the torch-gated tests run on those legs.

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
| Computed | 2026-07-26 12:19:34 |
| Used real stack | yes |
| Stack layers | 31 |
| Resolution (deg) | 0.01 |
| Profiles | 1 095 |

Health of the stored embedding sample (measured, not characterised):

| Statistic | Value |
| --- | --: |
| Values stored | 30 |
| Exactly zero | 3 |
| Share exactly zero | 10% |
| Min | 0 |
| Max | 1.08 |
| SD | 0.314 |

A healthy standardised embedding contains no exact zeros. A large share of exact zeros indicates channels that were never populated, or normalisation statistics left at their placeholder values.

Estimates as shipped, all rows:

| Exposure | Estimator | beta | Stage-1 F | Sargan p |
| --- | --- | --: | --: | --: |
| MAP (mm/a) | Backdoor OLS | 0.007691 |  |  |
| MAP (mm/a) | 2SLS (real MoCo v1) | 0.012590 | 861.900 | 0.25000 |
| Tree cover (%) | Backdoor OLS | 6.536000 |  |  |
| Tree cover (%) | 2SLS (real MoCo v1) | 47.740000 | 8.437 | 0.04200 |
| Clay (%) | Backdoor OLS | 0.192400 |  |  |
| Clay (%) | 2SLS (real MoCo v1) | -0.533000 | 10.970 | 0.00302 |

### `llm_benchmark_results.rds`

`mode = "simulated"`, bundle version `1.7.2`, computed 2026-04-23 16:52:56. **No API was called; the published vendor comparison reports its own simulator inputs.**

### `quantum_foundation_cerrado.rds`

| method | rmse_mean | rmse_sd | mae_mean | r2_mean | r2_sd | r2_min | r2_pooled | rmse_pooled | n_folds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Quantum KRR on raw covariates | 14.13 | 4.579 | 9.213 | -0.3501 | 0.7253 | -1.647 | -0.07475 | 15.53 | 5 |
| ranger (raw covariates) | 14.34 | 4.039 | 8.972 | -0.7951 | 1.9540 | -4.282 | -0.07530 | 15.53 | 5 |
| Quantum KRR on foundation PCs | 14.19 | 4.683 | 9.332 | -0.2951 | 0.4847 | -1.160 | -0.08871 | 15.63 | 5 |
| RBF-KRR on foundation PCs | 14.76 | 4.600 | 9.765 | -0.4492 | 0.6739 | -1.650 | -0.15910 | 16.12 | 5 |

Methods reporting R² of exactly zero: **0** — a consequence of the clamp sites below.

R² clamped with `max(0, 1 - ...)` at: `data-raw/quantum_foundation_benchmark.R:27`.

Benchmark covariate rasters filled with `rnorm()` at: `data-raw/causal_iv_benchmark_real.R:138`, `data-raw/quantum_foundation_benchmark.R:76`.

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

- **FA36407** — The v3.8.0 friendly-error system covers ~5% of failure sites and exactly the 6 files that got a test; 136 raw stop() and 13 divergent torch gates bypass it
  - Why it does not hold: Counts reproduce exactly: 14 `.stopf(`, 7 `.assert_type(`, 136 raw `stop(`, 154 `stopifnot(`, zero rlang/cli; helpers defined once in R/core_utils.R (.stopf at :39-45, .assert_type at :49-54, .assert_covariates :6-13, .assert_coords :15-27) with the "Use sparingly at user-facing entry points" note at :33; 13 torch-gate sites with 9 wordings. But "The adopted set is EXACTLY the set covered by tests/testthat/test-error-messages.R" is wrong: R/llm_kg_pipeline.R has 3 `.stopf` calls and is outside that file's declared scope (:4-7 names bhs_fit, gnn_build_graph, dm_fit, no_deeponet_fit). The "165 exports get a bare stop()" framing also ignores the 12 `.assert_covariates` and 3 `.assert_coords` call sites, which do produce named, readable messages across more files. This is style/consistency debt, not a defect — no failure mode is described.

- **F363935** — pkgdown reference index selects on `has_concept("pilar1")` but no Rd file has a `\concept{}` tag
  - Why it does not hold: The premise checks out (\_pkgdown.yml:123 `- has_concept("pilar1")`; 0 of 182 man/*.Rd contain `\concept{`; 0 `@concept`/`@family` in R/) but the conclusion is false. I read the installed pkgdown: `section_topics()` calls `select_topics(match_strings, topics, error_pkg=, error_path=, error_call=)` WITHOUT `check = TRUE`, and `select_topics` only aborts when `check` is TRUE; it aborts on an all-empty section (`purrr::every(indexes, is_empty)`) and otherwise runs `indexes <- purrr::discard(indexes, is_empty)`. The Pilar-1 section also has `starts_with("causal_")` etc., which match, so the zero-match selector is silently dropped. No abort. Sub-claim 2 is also refuted: man/edaphos-package.Rd carries `\keyword{internal}` at line 189, and `check_missing_topics()` computes `missing <- !in_index & !pkg$topics$internal`, so it is exempt from the index requirement (edaphos-roadmap.Rd is internal too). I simulated the full reference index against all 182 topics: ZERO non-internal topics are unmatched, so `check_missing_topics()` will not fire either. What survives is minor: a dead selector, `news: releases:` stale at v2.0.0 (cosmetic navbar list), and articles/ being unrendered — which inst/rosc/submission.md:82-84 itself discloses as "`.Rbuildignore`-d to keep the vignette build fast". `pkgdown::build_site_github_pages()` is not blocked.

- **F0EEC2D** — .batchbald_aleatoric_var() silently falls back to in-sample random-forest residuals whenever any OOB prediction is NA
  - Why it does not hold: The code reads exactly as quoted (R/active_batchbald.R:67-77) and the silent two-branch design is real, but the fallback is unreachable for any model `al_fit()` can produce, so the impact does not exist. `al_fit` -> `.fit_core` always calls `ranger::ranger(..., quantreg = TRUE, keep.inbag = TRUE)`, and ranger itself enforces `minoob <- min(rowSums(inbag.counts == 0)); if (minoob < 10) stop("Error: Too few trees for out-of-bag quantile regression.")` — I read this in the installed ranger 0.18.0 source. That guarantees every observation has >= 10 OOB trees, hence zero NAs in `rg$predictions`, hence `length(na.omit(oob)) == length(y_train)` always holds and the OOB branch always wins. Verified empirically on ranger 0.18.0: n = 40 with num.trees = 50 and 500 both give length-40 predictions with 0 NAs. The claimed trigger regime ("small-n / small-num.trees") is precisely the regime where ranger refuses to fit at all rather than emitting NA OOB predictions — the two failure modes are mutually exclusive, not co-located.

### Closed since the audit (measured, not asserted)

47 findings were true at `272b378` and cannot be reproduced at `8e725b9`. Each line states the measurement that closed it, not a claim that it was addressed.

| ID | Sev | Area | Fixed in | Finding | Measurement |
| --- | --- | --- | --- | --- | --- |
| F0BC16C | blocker | CI & infra | `3f2d005` | "CI green" and "0 errors \| 0 warnings \| 0 notes" are asserted in release docs while a dependency-independent test error would redden all 5 matrix legs | Both live errors are fixed in code and the suite is green. R/active_fit.R:13-20 adds .al_min_trees_for_quantreg(), which derives ranger's OOB-quantile floor from the Binomial(num.trees, (1-1/n)^n) tail, and .assert_num_trees() applies it; foundation_weights_load() now runs its argument validation before .moco_require_torch(). Residual: RELEASE-CHECKLIST-v3.10.0.md:3 still asserts CI green, which stays open under F29E750 and F00AF5C. |
| F2A0EC5 | blocker | Scientific reproducibility | `2fd03a5` | Shipped IV bundle refutes the README's "decisive test passes" headline: Sargan p = 3.2e-08, not 0.343 | The IV benchmark was re-run on real data and the headline was replaced by what the bundle actually shows, rather than hand-patched. The bundle was regenerated 2026-07-26 with normalisation_source recorded as aoi and a note that the v1 encoder's training statistics are unrecoverable. |
| F862881 | blocker | Scientific reproducibility | `be4c086` | Every β in the README's real-data causal table disagrees with the shipped bundle, and the confounding correction has the wrong sign for tree cover | The fabricated real-data causal table was replaced with measured results computed from a newly generated bundle, and the numbers are pinned by test. |
| FAC0043 | high | Code quality | `a809ec9` | foundation_weights_load() gates on torch before validating its own arguments — the live ERROR 2 | foundation_weights_load("no-such-id") without torch now returns "Unknown pretrained encoder 'no-such-id'. Run foundation_weights_list() to see available names." -- the registry lookup runs before the torch gate. |
| FA81F77 | high | CRAN readiness | `3f2d005` | Undeclared `utils` and `tools` namespaces — guaranteed R CMD check WARNING that cran-comments.md denies | DESCRIPTION Imports: clhs, deSolve (>= 1.40), httr2, jsonlite, ranger, Rcpp (>= 1.0.0), stats, tools, utils. The 'checking dependencies in R code' WARNING no longer appears in the check log. |
| FCBA23B | high | CRAN readiness | `28dac7d` | 134 of 169 exported functions have no examples; only 10 have an example R CMD check executes | NAMESPACE has 170 export() lines and 0 exports without an \examples block; 172 Rd files carry one, 129 of them outside \dontrun. The audit measured 134 of 169 exports with no example and 10 with a runnable one. |
| F5EF8F6 | high | Release consistency | `a549528` | Four mutually exclusive citation versions: DESCRIPTION 3.10.0, README 2.8.0, CITATION.cff 2.1.0, CITATION.cff preferred-citation 1.6.0 | Every artefact that states a version now states 4.1.0: DESCRIPTION, CITATION.cff (both the top-level field and preferred-citation), .zenodo.json, the README version badge and the top NEWS section. One distinct value across six artefacts, against the four mutually exclusive ones the audit found. Separately still true and still open: 4.1.0 has no git tag (last tag is v4.0.0) -- see FEA55C5. |
| F7DC6A4 | high | Release consistency | `2984aa5` | The README's only install command pins a git ref that does not exist (`@v2.8.0`) | Commit 2984aa5 unpinned the README install command, so it no longer points at a git ref that does not exist. |
| FA01BFB | high | Release consistency | `2984aa5` | CITATION.cff assigns the identical DOI 10.5281/zenodo.19710162 to twelve different "Version DOI" entries | Commit 2984aa5 deleted the eleven duplicate version-DOI entries and wrote the reason into the file instead of leaving it implicit. |
| FBAF1FD | high | Roadmap promises | `3bd1938` | DESCRIPTION promises ten research pillars; every document shipped in the CRAN tarball documents six, and pillars 7-10 have no roadmap row, no README section and no vignette | vignettes/ has 18 Rmd files including pilar7-bayesian-hierarchical, pilar8-neural-operators, pilar9-diffusion-models and pilar10-graph-attention; README carries a section for each of pillars 7-10; R/pillars_roadmap.R has a row for each and no longer calls itself the roadmap of six pillars. The related metadata claim, F545DD7, was open when this line was first written and was closed in the same session at a549528. |
| F1CD43E | high | Scientific reproducibility | `23dc4d3` | R² is floored at zero in three benchmark code paths, censoring negative values and turning them into a "statistically indistinguishable" conclusion | The bundle was regenerated by re-running data-raw/quantum_foundation_benchmark.R at HEAD with the unclamped edaphos_r2(). inst/extdata/quantum_foundation_cerrado.rds now holds 17 negative per-fold R2 values and zero exact zeros, where it previously held 17 exact zeros and no negatives; the run reproduces bit-for-bit from its seed. README.md and vignettes/pilar4-pilar6-quantum.Rmd were rewritten: the 'statistically indistinguishable' conclusion the clamp manufactured is replaced by the measured finding that all four methods, including the ranger baseline, fall below the null. The vignette's hand-typed '#>' console block -- indistinguishable from knitr output -- was replaced by a live chunk reading the bundle. tests/testthat/test-readme-numbers.R binds the table to the bundle and asserts no censored R2 survives. |
| F30D53B | high | Scientific reproducibility | `2fd03a5` | The v1.8.0 multi-backend LLM benchmark is entirely simulated and its headline F1/latency values are hard-coded function arguments | The claim was withdrawn rather than faked, which is the correct half of the finding's own recommended action: the bundle still records mode = simulated and the README now says so in the heading and the body. |
| F485937 | high | Scientific reproducibility | `2fd03a5` | No test validates any headline number or any of the twelve committed result bundles | A claim-binding test layer was added across the campaign, so headline numbers and shipped bundles are now asserted against each other rather than published unchecked. |
| F623876 | high | Scientific reproducibility | `ec04bee` | `.bench_inject_aleatoric()` manufactures the published PICP with author-chosen noise and silently degrades the published RMSE | Both defects fixed: the author-chosen aleatoric noise injection is gone and the RMSE degradation it caused was corrected, with the response scale made honest in the same pass. |
| FF375C1 | high | Scientific reproducibility | `0cb0b0a` | The P4 "Foundation" row of the headline "first honest cross-pillar comparison" is computed on a pure Gaussian-noise raster | predict.edaphos_bhs() now returns the sampler's own predictive draws under draws = TRUE (as an attribute, so no existing caller changes), and data-raw/benchmark_wosis_p4_p5_p7.R uses them instead of rebuilding rnorm(200, mean, sd) from the summary. The cost of the substitution is measured rather than asserted: a paired diagnostic scores both distributions over the same predictions, fold and held-out truth, with the Gaussian drawn on a private RNG stream. On this archive it was CRPS 0.3405 vs 0.3420 and PICP90 0.9224 vs 0.9283 against a nominal 0.90; the per-fold table ships in the bundle as p7_gaussian_gap. The correction was propagated through benchmark_wosis_6pilar.rds, the README pooled table and the rendered manuscript. |
| F9E2C74 | high | Incomplete implementations | `2fd03a5` | qf_krr_benchmark() clamps R-squared at zero, contradicting the package's own edaphos_r2() and hiding worse-than-mean quantum models | The R-squared clamp was removed and the function now delegates to the package's own metrics, so worse-than-mean quantum models are reported as negative rather than censored to zero. |
| F60AE85 | high | Test coverage | `3bd1938` | bhs_fit has no rank check on the model matrix: a constant covariate yields NA rgamma rates (the 2 live WARNINGs) then a cryptic Cholesky death | R/pilar7_bayesian_hierarchical.R now computes qr(X)$rank and names the aliased columns; the rank-deficient fit raises one informative error and zero warnings, against the 2 warnings the audit measured. |
| F64B0F0 | high | Test coverage | `3f2d005` | R/foundation_finetune.R:41 makes the whole Pillar-4 fine-tuning API require `reticulate`, which it never uses | The spurious reticulate clause was deleted from the Pillar 4 fine-tuning gate, so the API no longer requires a package it never uses. |
| F9C6DD9 | medium | CI & infra | `a549528` | Distribution metadata is 9 minor versions stale: CITATION.cff says 2.1.0, README says 2.8.0, .zenodo.json has no version at all | Same measurement as F5EF8F6. .zenodo.json carries a version field (it had none) and the README badge reads 4.1.0 rather than 3.10.0; the badge is now generated by patch-readme-metrics.R from DESCRIPTION, and its link points at /releases rather than at a per-tag URL, because the DESCRIPTION version routinely leads the last tag. |
| FD941E5 | medium | CI & infra | `3f2d005` | cran-comments.md test-suite and install-size figures are contradicted by the tree they describe | cran-comments.md was replaced wholesale by a generated document rendered from a real check log by tools/status/render-cran-comments.R, so the hand-written test-suite and install-size figures the finding indicts no longer exist. |
| FDC9573 | medium | CI & infra | `d51b0d6` | No CI leg ever installs libtorch: 25% of R/ and 70 of 460 test blocks are unreachable in all three workflows | A libtorch CI leg now exists. Commit d51b0d6 added a sixth matrix leg with a libtorch cache and a post-check step that fails the leg if any torch test skipped, so the torch code paths are executed by CI rather than asserted. |
| F215985 | medium | Code quality | `99cd6a1` | Off-by-one in the RcppArmadillo BHS backend biases w_post_mean, silently corrupting every predict.edaphos_bhs() for backend="rcpp" | The exact one-character change the finding prescribed was made, so w_post_mean is no longer biased and predict.edaphos_bhs(backend = rcpp) agrees with the R backend. |
| F3E0E05 | medium | Code quality | `28dac7d` | gnn_embed() returns a different column count per backend and its documented @return is wrong for backend="torch" | man/gnn_embed.Rd documents the average_heads argument and the column count each setting produces; the pure-R path in R/pilar10_graph_nn.R implements the same argument, so both backends are described by one \value. |
| F4ED689 | medium | Code quality | `3bd1938` | Rank-deficient design matrix poisons the entire BHS Gibbs chain to NA on iteration 1, then hard-errors — and the test's own comment about it is wrong | Same measurement as FD825FD: the rank-deficient design is rejected before the Gibbs loop starts, so neither of the two "NAs produced" warnings is emitted. |
| FBDE0E9 | medium | Code quality | `3f2d005` | al_fit(num.trees=) has no lower bound against ranger's undocumented OOB-quantile minimum, and the test that breaks is unseeded — a ~25% flaky ERROR | Both prescribed changes landed: a derived lower bound now exists for num.trees, and the flaky test was seeded and given a valid tree count. |
| FC841F7 | medium | Code quality | `28dac7d` | Same loop-invariant matrix product recomputed n_draws times, copy-pasted into two files | Both copies of the loop-invariant product were hoisted out of their loops. |
| F00A9C3 | medium | CRAN readiness | `3f2d005` | `Depends: R (>= 3.5)` is falsified by two features requiring R 4.0.0 and R 3.6.0 | DESCRIPTION Depends: R (>= 4.0). |
| F4BEBBD | medium | CRAN readiness | `ac7b9c2` | DESCRIPTION Title/Description violate CRAN style: marketing adjectives, unquoted software names, zero method references | DESCRIPTION was rewritten to CRAN style: the marketing adjectives are gone, software names are quoted, and the Title and Description no longer make the claims the finding cites. |
| F545DD7 | medium | Release consistency | `a549528` | The "ten pillars" identity exists only in the unreleased HEAD; every other metadata artefact still says six | CITATION.cff, .zenodo.json and _pkgdown.yml now say ten research pillars and enumerate all ten; DESCRIPTION, README.md, R/pillars_roadmap.R and R/edaphos-package.R already did. The only surviving "six pillars" strings are historical and correct -- the v1.7.0 capstone integrated the six pillars that existed then. Measured by grepping for the phrase and excluding occurrences qualified by that/then/of-v1.x. |
| F1E1D2B | medium | Roadmap promises | `a549528` | Archival metadata (.zenodo.json, CITATION.cff) still describes a six-pillar package that stops at v1.8.0 | Both archival metadata files were rewritten for the ten-pillar package and then reset to the honest development version, so neither still describes a six-pillar package stopping at v1.8.0. |
| F2F16E8 | medium | Scientific reproducibility | `3f2d005` | cran-comments.md misstates both the check status and the extdata sizes it uses to justify the install-size NOTE | cran-comments.md is now generated from a real R CMD check log instead of hand-written, so the check status and the extdata sizes it quotes come from the log rather than memory. |
| F3467DC | medium | Scientific reproducibility | `0cb0b0a` | Four mutually incompatible definitions of the headline benchmark's target variable across README, vignette and runner | The shipped artefact settles the contradiction: B1's 95% interval bounds are exactly 0.8 and 194.0, the exact min and max of soc_topsoil_gkg on the raw scale, so the target is untransformed g/kg with no log1p, over a surface-anchored slice of variable thickness (upper_depth == 0, lower_depth in 5-30 cm, median 15) rather than any fixed window. data-raw/case_cerrado_run.R's header claimed 'Target: log1p(SOC, g/kg). Point estimate = back-transformed MEDIAN' and defined a .back_transform that was never called; header, the kriging-scale sentence and the vignette's target line are corrected to the measured definition, and the dead function is gone. |
| F54856E | medium | Scientific reproducibility | `2fd03a5` | The "LLM-augmented (Gemma 4)" DAG in the causal-discovery trio is six hand-typed edges, not an LLM output | The hard-coded six-edge data frame with confidences 0.90/0.82/0.78/0.75/0.72/0.71 was deleted; the script now reads the shipped claims file and maps each claim through the extractor, so the LLM-augmented DAG is produced rather than typed. |
| F884A23 | medium | Scientific reproducibility | `0cb0b0a` | The flagship case-study benchmark cannot be re-run by anyone: its input is .gitignore'd and its output path is not the shipped artefact | data-raw/case_cerrado_run.R now writes inst/extdata/case_cerrado_results.rds directly, adopting the convention of the other 46 data-raw scripts, and carries an edaphos_provenance() block; the artefact was re-run and reproduced identical numbers, so the shipped file is now demonstrably the committed script's output rather than a hand copy from a gitignored path. tests/testthat/test-bundle-provenance.R -- which named this exact file as the defect it existed for and then skipped it -- now fails on any bundle without provenance outside an explicit legacy list that can only shrink. The header states plainly what a fresh clone needs: the two-script chain is public and reproducible but costs ~1 h and ~2 GB, and the 674 MB raster cannot be committed. Carrying the embeddings to remove that dependency was considered and rejected in writing: it would buy reproducibility of the output at the cost of making the E arm unfalsifiable. |
| FDA80DD | medium | Scientific reproducibility | `d51b0d6` | Residual kriging (B2) is fit to in-bag rather than OOB forest residuals, manufacturing the README's PICP conclusion | The kriging fit was moved onto out-of-bag residuals in code, and the published conclusion that the in-bag fit had manufactured was withdrawn in the artefact and the prose. |
| FAEC54C | medium | Incomplete implementations | `3f2d005` | al_fit() performs no validation of num.trees against nrow(labeled), producing an opaque ranger error; the guarding test is unseeded and fails ~12% of runs | al_fit(<20 rows>, num.trees = 3) now stops with "[al_fit] num.trees = 3 is too small for out-of-bag quantile regression on 20 labeled rows" instead of the opaque ranger error. |
| FC68E1D | medium | Incomplete implementations | `a809ec9` | foundation_weights_load() requires torch BEFORE resolving the registry, so the placeholder v2 entry reports the wrong reason for failing | Same measurement as FAC0043. |
| FD825FD | medium | Incomplete implementations | `3bd1938` | bhs_fit() returns an all-NaN posterior for a rank-deficient design matrix, and the edge-case test is written to accept it | bhs_fit(dd, y ~ x1 + const, ...) on a design with a constant column now stops with "[bhs_fit] design matrix is rank-deficient: rank 2 for 3 columns. Aliased column(s): const." instead of returning an all-NaN posterior. |
| F21DBBA | medium | Test coverage | `3f2d005` | test-foundation-weights.R:29-36 asserts an error message that is unreachable without torch (live ERROR 2) -- green on CI, red on CRAN | The unreachable expectation was fixed at the source the finding preferred: foundation_weights_load() now runs its argument validation before the torch gate, so the n_channels error is raised with or without torch. |
| F2C0D91 | medium | Test coverage | `3f2d005` | al_fit is ~14.5%-flaky by construction: test-active-quantum-posterior.R:30-35 has no set.seed and passes num.trees=50 for OOB quantile regression (live ERROR 1) | Fixed at both levels the finding asked for: the test was seeded and given a valid tree count, and the underlying floor was derived in the package rather than hard-coded in the test. |
| FB609A4 | medium | Test coverage | `ac7b9c2` | NEWS.md v3.10.0 test and check claims are not reproducible in any environment the project automates | NEWS.md was reset to a single honest development entry that explicitly retracts the unreproducible test and check claims instead of restating them. |
| FA36407 | low | Code quality | `` | The v3.8.0 friendly-error system covers ~5% of failure sites and exactly the 6 files that got a test; 136 raw stop() and 13 divergent torch gates bypass it | withdrawn: Closed as not a defect, per the register's own PARTIALLY_TRUE correction and the audit of this batch. The finding describes style and consistency debt in error-message plumbing and names no failure mode; the .stopf/.assert_* helpers produce nicer messages where adopted and plain messages elsewhere, which is a matter of taste rather than a defect. Adoption has also grown rather than stalled since the finding was written. |
| F363935 | low | CRAN readiness | `` | pkgdown reference index selects on `has_concept("pilar1")` but no Rd file has a `\concept{}` tag | withdrawn: Closed as not a defect, confirming the register's REFUTED verdict by re-derivation rather than inheritance. The premise is true - _pkgdown.yml:125 is still - has_concept(pilar1) and no man/*.Rd carries a matching \concept{} tag - but the consequence is false: in pkgdown 2.2.0, section_topics() calls select_topics() without check = TRUE, so the zero-match abort branch is unreachable and the selector is silently ignored. The pkgdown build does fail at HEAD, for two unrelated reasons tracked under FE42047. |
| FEA55C5 | low | Release consistency | `ac7b9c2` | 32 of the last 33 NEWS releases have no git tag, violating the project's own documented release policy | The set of untagged NEWS releases no longer exists: commit ac7b9c2 reset NEWS.md to a single 0.9.0 development section, which is also the commit that withdraws the fabricated 43-release history. |
| F9EDEBA | low | Roadmap promises | `ac7b9c2` | Pilar 7 was promised as INLA/Stan and delivered as a hand-rolled Gibbs sampler; the substitution is never disclosed | The INLA/Stan promise was the Deferred (explicit roadmap entries) block in NEWS.md, and commit ac7b9c2 deleted it; git log -S confirms 45e24d2 added that block and ac7b9c2 removed it. Nothing else in the repository promises an INLA or Stan backend for Pillar 7. |
| F3CACF8 | low | Incomplete implementations | `99cd6a1` | Off-by-one in the RcppArmadillo Gibbs sampler's w_post_mean accumulation makes the rcpp backend disagree with the R backend it claims to reproduce | The off-by-one in the RcppArmadillo Gibbs accumulation was fixed and verified against the R backend it claims to reproduce. |
| F0EEC2D | non-issue | Incomplete implementations | `` | .batchbald_aleatoric_var() silently falls back to in-sample random-forest residuals whenever any OOB prediction is NA | withdrawn: Closed as not a defect, matching the register's own REFUTED verdict. The code is unchanged and reads exactly as quoted, but the in-sample fallback branch is unreachable for any model al_fit() can produce: al_fit -> .fit_core always calls ranger with quantreg = TRUE, and ranger itself refuses to fit when min OOB count is under 10, so rg$predictions never contains NA and the length test at R/active_batchbald.R:71 always passes. The campaign made it less reachable still, by adding the derived num.trees floor .al_min_trees_for_quantreg() at R/active_fit.R:13-20. No failure mode exists to trigger the described bias. |

### All open findings

| ID | Sev | Verdict | Area | Kind | Effort | Finding |
| --- | --- | --- | --- | --- | --- | --- |
| FF20A54 | blocker | partial | Release consistency | incomplete-implementation | hours | "R CMD check: 0 errors / 0 notes" is false: two test errors reproduce in this tree, and one of them fires specifically in the torch-less CRAN environment that cran-comments.md swears is clean |
| FE42047 | high | partial | CI & infra | bug | hours | pkgdown workflow cannot succeed: `has_concept("pilar1")` matches zero topics and 4 navbar links point at pages never built |
| F52C0B8 | high | partial | CRAN readiness | inconsistency | hours | cran-comments.md is self-contradictory and every quantitative claim in it is stale or wrong |
| FDE7C43 | high | partial | CRAN readiness | tech-debt | hours | Installed size will NOTE: inst/extdata 9.98 MB + man/figures 2.3 MB, of which a 1.9 MB PNG logo |
| F36D2FE | high | partial | Release consistency | process-gap | hours | The "v3.11.0" work is committed and self-referenced in shipped code, but no version exists: no DESCRIPTION bump, no NEWS section, no tag |
| F5F7D9A | high | confirmed | Release consistency | doc-gap | hours | The "1 345 tests" figure is unreproducible, mis-attributed, and the NEWS test-count chain contains two arithmetic breaks |
| F10D9DC | high | confirmed | Incomplete implementations | incomplete-implementation | minutes | edaphos-cerrado-moco-v2 ships as an all-NA placeholder row in the exported public registry, keyed to a nonexistent package version 3.11.0 |
| F873468 | high | confirmed | Incomplete implementations | bug | hours | foundation_build_cerrado_stack() silently writes a truncated stack to the cache when any geodata fetch fails, then reuses it forever |
| F8EC452 | high | partial | Test coverage | process-gap | hours | No CI leg has ever executed the torch code paths: 74 test blocks / 223 expectations / ~3,140 LOC unexercised |
| F29E750 | medium | confirmed | CI & infra | doc-gap | hours | Two competing release checklists contradict each other and describe a deploy action the pkgdown workflow does not use; referenced artefacts do not exist |
| F3D7BED | medium | partial | CI & infra | process-gap | days | 33 of 43 NEWS.md releases have no git tag and there is no release-automation workflow, contradicting CONTRIBUTING's tagging promise |
| F5E91CE | medium | partial | CI & infra | tech-debt | days | Dockerfile is not a reproducibility artefact: builds from GitHub main, unpinned libtorch, R 4.4.1 in no CI leg, v2.1.0 metadata, missing Suggests |
| F6F101E | medium | partial | CI & infra | process-gap | hours | CI builds vignettes, but 3 of 14 self-truncate to a one-line stub without libtorch -- and CONTRIBUTING tells contributors to skip vignette building entirely |
| FD3C0C1 | medium | confirmed | CI & infra | bug | minutes | Chunk option in pilar4-simclr vignette calls `reticulate::` unguarded with broken `&&`/`\|\|` precedence -- hard error in exactly the Docker configuration |
| F0E4DC1 | medium | partial | Code quality | incomplete-implementation | hours | Pillars 8/9/10 default backend="r" never trains the architecture it is named after, while DESCRIPTION/README mark them "implemented" |
| F7EC076 | medium | confirmed | Code quality | tech-debt | hours | Twelve copies of skip_if_no_torch() in three divergent flavours, orphaning the helper-torch.R that was added to replace them |
| FCF64DC | medium | confirmed | Code quality | inconsistency | days | Naming schism: pilar/pillar, ordinal/domain module names, al_* vs active_*, and five undocumented cryptic export prefixes |
| FD27999 | medium | confirmed | Code quality | missing-work | days | Twelve exported functions are never referenced anywhere in tests/, including the entire advertised tile-source pipeline |
| F4484D7 | medium | partial | CRAN readiness | inconsistency | days | 5 of 14 vignettes are written in Portuguese while DESCRIPTION declares `Language: en-US` |
| F4EC093 | medium | confirmed | CRAN readiness | incomplete-implementation | minutes | `src/Makevars.win` documents a Unix `src/Makevars` that does not exist |
| F83F26A | medium | confirmed | CRAN readiness | inconsistency | hours | RELEASE-CHECKLIST-v3.10.0.md instructs the maintainer to upload two artefacts that do not exist, and asserts a green state contradicted by the live test run |
| F00AF5C | medium | confirmed | Release consistency | tech-debt | hours | Two overlapping release checklists disagree with each other and both claim to be the authoritative list of remaining steps |
| FB9DA9E | medium | partial | Release consistency | doc-gap | days | The 84 KB README documents nothing after v2.8.0; its only 3.x reference is the version badge |
| FBB414A | medium | confirmed | Release consistency | missing-work | hours | .zenodo.json carries no version field at all and its description is frozen at v1.8.0 |
| FC9610C | medium | partial | Release consistency | missing-work | hours | The only DOI badge is a concept DOI the repo itself says resolves to v0.2.0, and nothing after v1.5.0 was ever deposited |
| FF84B54 | medium | confirmed | Release consistency | inconsistency | hours | Two parallel version schemes collide inside a single README table: "v1.x roadmap lines" are interleaved with package 3.x versions, and v3.0.0 means two different things |
| F2E57CE | medium | confirmed | Roadmap promises | bug | minutes | Step 4 of the v1.3.2 hand-off (wire_up_v2_doi.R) matches nothing and silently writes the timestamp into the `url` field |
| F492008 | medium | confirmed | Roadmap promises | bug | hours | Four pkgdown navbar links point at articles pkgdown never builds, and man/edaphos-package.Rd tells users to open a vignette that is not in the package |
| FD3DBCB | medium | confirmed | Roadmap promises | process-gap | hours | Two competing release checklists, one stale, pointing at a tarball path that does not exist |
| FD528FC | medium | confirmed | Roadmap promises | incomplete-implementation | days | Three exported functions with .Rd pages and pkgdown entries are permanent stop() stubs |
| FF7221D | medium | partial | Roadmap promises | missing-work | hours | v1.3.2 (MoCo v2 200k-step encoder) is 43 % short of target and the checkpoint exists nowhere in the repository |
| F0F5D47 | medium | confirmed | Scientific reproducibility | inconsistency | hours | Pretrained-weight DOI is real but the v2 registry row is all-NA while claiming a nonexistent version; CITATION.cff and .zenodo.json are many releases stale and assign one DOI to ten releases |
| F366B1F | medium | confirmed | Scientific reproducibility | doc-gap | hours | README's headline benchmark tables are two to four release cycles stale, and the current 6-method result exists only in NEWS.md |
| F5672C5 | medium | confirmed | Scientific reproducibility | doc-gap | hours | DESCRIPTION's "every vignette runs offline" is false: four advertised vignettes are not vignettes, and the Pilar 4 × Pilar 6 vignette evaluates nothing |
| F71D795 | medium | confirmed | Incomplete implementations | incomplete-implementation | hours | The spBayes backend is advertised as an equal peer in README/NEWS/man but predict(), as_edaphos_posterior() and al_query_bhs() all fail on it |
| F9046AE | medium | confirmed | Incomplete implementations | doc-gap | minutes | bhs_fit()'s rcpp backend is absent from its own @param documentation, and al_query_bhs() rejects it despite the fit being complete |
| FFFC52E | medium | confirmed | Incomplete implementations | bug | minutes | causal_iv bootstrap silently discards failed 2SLS replicates and rewrites B to the survivor count |
| F86487C | medium | confirmed | Test coverage | doc-gap | hours | R/pilar7_bayesian_hierarchical.R:270-272 cites a test that does not perform the verification it claims |
| FA6ECC8 | medium | confirmed | Test coverage | missing-work | hours | The RcppArmadillo BHS Gibbs backend has no real numerical-agreement test: one scalar mean at 0.2 tolerance, w_post_mean never compared, no edge cases |
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
| FFBBEBB | low | partial | Release consistency | inconsistency | hours | Dockerfile self-identifies as v2.1.0 and pins a 2026-04-23 CRAN snapshot, but installs HEAD |
| F1A720B | low | confirmed | Roadmap promises | missing-work | weeks | v1.8.3 (expand LLM gold standard from 72 to 300 claims) is untouched — still 30 abstracts / 72 claims |
| F2FC8F9 | low | partial | Roadmap promises | doc-gap | minutes | V1_3_2_HANDOFF.md instructs the maintainer to cd into a directory named after a different project |
| F3E4CA6 | low | partial | Roadmap promises | doc-gap | hours | Documentation promises that point at content which does not exist: cheatsheets "on the pkgdown site", P8/P9 benchmarks "in vignettes/" |
| F4BEE44 | low | confirmed | Roadmap promises | bug | minutes | package_v2_for_zenodo.R fails with a cryptic stopifnot before its own step-count guard, and drops the resume hint from its error message |
| F4EE43C | low | partial | Roadmap promises | inconsistency | hours | Roadmap table and NEWS were never updated for the last two feature commits; DESCRIPTION 3.10.0 conflicts with the 3.11.0 baked into the weights registry |
| F66D149 | low | partial | Roadmap promises | tech-debt | minutes | Stale dead-end in data-raw/causal_iv_benchmark.R blocks a path that v1.9.1 already delivered |
| FCC0D53 | low | partial | Roadmap promises | missing-work | days | Promised production-scale outputs never produced: the 10k-abstract LLM-KG run and the 6-pillar benchmark wrapper set |
| F37E56E | low | confirmed | Incomplete implementations | bug | hours | foundation_embed_at_coords() converts a failed raster block read into an all-zero patch that is indistinguishable from a real embedding |
| F3A34C0 | low | confirmed | Incomplete implementations | bug | minutes | foundation_build_cerrado_stack() calls digest::digest() unguarded, but digest is Suggests-only -- the exported function dies on a clean install |
| F52B874 | low | partial | Incomplete implementations | doc-gap | minutes | Two exported functions ship without \value in man/, contradicting the NEWS claim of 0 R CMD check notes |
| F649AF8 | low | partial | Incomplete implementations | tech-debt | minutes | Stale forward-looking version markers and dead code left in shipped R/ sources |
| FBDF515 | low | confirmed | Incomplete implementations | bug | hours | quantum_kernel() with the default rcpp backend has only a warning where it needs a hard cap, and silently returns an all-ones kernel for reps <= 0 |
| F1A5FC0 | low | partial | Test coverage | inconsistency | hours | 12 duplicated, semantically divergent torch skip helpers shadow the canonical helper-torch.R; the package's own runtime guards never check torch_is_installed() |
| F3CED48 | low | confirmed | Test coverage | missing-work | hours | 44 print/summary S3 methods, zero snapshot tests, 15 expect_output calls -- half of them behind torch/qiskit gates |

### Detail — blocker and high severity

#### FF20A54 — "R CMD check: 0 errors / 0 notes" is false: two test errors reproduce in this tree, and one of them fires specifically in the torch-less CRAN environment that cran-comments.md swears is clean

`Release consistency` · incomplete-implementation · blocker · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> The two test errors are genuinely fixed (see F0BC16C) and NEWS.md now retracts the claim at :326 rather than repeating it, but the false assertion still ships to users. inst/rosc/submission.md:100-101 still reads: [x] Package builds on R CMD check --as-cran with 0 errors / 0 notes, and inst/ has no .Rinstignore, so that file installs into every user's library. The real log at tools/status/check.log:94 records Status: 2 NOTEs (CRAN incoming feasibility at :14 and detritus in the temp directory at :89). RELEASE-CHECKLIST-v3.10.0.md:3 still asserts code 100 % ready, CI green.

**Impact**

> cran-comments.md is the document a CRAN volunteer reads first. Submitting it as written asserts a check status that the submitting tarball cannot produce, which is the fastest possible route to an archived submission and a damaged maintainer reputation. The unbounded `ranger` import means the failure will also hit every user who installs today, not just CRAN.

**Verification correction**

> Headline CONFIRMED: NEWS.md:71 "R CMD check: 0 errors / 0 notes.", cran-comments.md:5/:20-21 "0 errors | 0 warnings | 0 notes", cran-comments.md:49-52 "base test suite runs without torch"; R/active_fit.R:7 quantreg=TRUE unconditional, al_fit at :52 / .fit_core call at :56, test call at test-active-quantum-posterior.R:34, ranger 0.18.0 installed, DESCRIPTION:83 `ranger,` unbounded vs :80 `deSolve (>= 1.40)` / :84 `Rcpp (>= 1.0.0)`, and R/active_fit.R last touched by f907388. Two sub-claims are wrong: (a) test-foundation-weights.R:29-36 is NOT "the only test in that file with NO torch gate" -- the blocks at :10 and :22 are also ungated (they pass); (b) skip_if_no_torch() is first used at :40, not :38.

**Action**

> Fix both tests: add `skip_if_no_torch()` to tests/testthat/test-foundation-weights.R:29 (or reorder R/foundation_weights.R:294 so argument validation precedes `.moco_require_torch()`), and raise `num.trees` at tests/testthat/test-active-quantum-posterior.R:34 to a value ranger accepts for OOB quantile regression (>=100, matching the sibling test at :17). Add a `ranger (>= x.y.z)` floor to DESCRIPTION:83. Then re-run `R CMD check --as-cran` in a container WITHOUT torch/dagitty/bnlearn/dbarts and paste the real output into cran-comments.md:19-22 instead of a remembered one.

#### FE42047 — pkgdown workflow cannot succeed: `has_concept("pilar1")` matches zero topics and 4 navbar links point at pages never built

`CI & infra` · bug · high · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> Ran pkgdown:::data_reference_index() against HEAD with pkgdown 2.2.0: it aborts on the missing spatial_block_folds topic, then on the five unindexed vignettes. Dead navbar links persist at _pkgdown.yml:77 articles/pilar1-causal-real.html, :81 articles/llm-kg-benchmark.html, :93 articles/pilar3-4d-real.html, :103 articles/pilar5-soilgrids-br.html, whose sources live in articles/, a directory pkgdown does not render.

**Impact**

> `pkgdown::build_site_github_pages()` (pkgdown.yaml:56) fails on the reference index, so the documentation site has never deployed -- corroborated by RELEASE-CHECKLIST-v3.10.0.md:75-98 and RELEASE.md:57-72 both still listing "enable GitHub Pages" as pending. The `url:` in _pkgdown.yml:1 and the site link in SECURITY.md:37 both advertise a site that does not exist. Even if the reference index were fixed, 4 of 18 navbar entries would 404.

**Action**

> Either add `@concept pilar1` (or `@family pilar1`) to the Pilar 1 roxygen blocks in R/causal_*.R and re-document, or delete _pkgdown.yml:124 (the `starts_with("causal_")` selector on line 125 already covers the section). Add `edaphos-package` to a reference section. For the four root `articles/*.Rmd`, either move them into `vignettes/` (and add to the `articles:` index at _pkgdown.yml:219-248, plus `.Rbuildignore` them individually if they must not ship) or delete the four navbar hrefs. Add a `pkgdown` job on pull_request that fails the build so this is caught next time.

#### F52C0B8 — cran-comments.md is self-contradictory and every quantitative claim in it is stale or wrong

`CRAN readiness` · inconsistency · high · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> The self-contradiction is gone - cran-comments.md is now generated by tools/status/render-cran-comments.R from a real check log, its status block is verbatim from tools/status/check.log, and the 0 notes line is replaced by the actual 2 NOTEs - but the finding's headline survives in a new form: the generated numbers are stale again. Its footer declares provenance at commit 35f385f, three commits behind HEAD, and bc59af8 shrank inst/extdata afterwards, so the quoted extdata 4.2Mb is now 2268 KB (2.2 MB) on disk; the test line says 2051 passing and 1 skipped where a live run gives 2095 pass and 14 skip; and the CRAN incoming section still reads Source tarball size: not measured. Regenerating the file closes this.

**Impact**

> cran-comments.md is the first thing a CRAN volunteer reads. A file that contradicts itself in two adjacent sections and misstates file sizes by 26x invites a hostile review of everything else, and the claimed clean check will be trivially disproven by CRAN's own log.

**Verification correction**

> Almost everything holds, but the title's "every quantitative claim" is false and one sub-claim is REFUTED. Verified true: :20-21 "Status: OK / 0 errors | 0 warnings | 0 notes" vs :69-70 "~13 MB" installed above the 5 MB soft cap (that IS the installed-size NOTE, so the two cannot both hold); :30-31 and :33-35 test/skip/warning claims all wrong; `causal_cerrado_real.rds` is 63,521 B = 62 KB vs the claimed 1.6 MB (26x); `du -sk inst/extdata` = 9780 KB vs "~8 MB"; the itemised list omits case_cerrado_results.rds (1,469,189 B), capstone_native_calibration.rds (758,948 B), capstone_campaign_results.rds (556,352 B), temporal_cerrado_results.rds (198,786 B); man/figures is 2364 KB and unmentioned; :4 R 4.5.3 vs local 4.6.1. NOT true: `benchmark_wosis_p4_p5_p7.rds` is 1,959,632 B = 1.87 MB vs claimed 0.7 MB — that is 2.7x, not 26x (the 26x applies only to causal_cerrado_real.rds), and `benchmark_wosis_6pilar.rds` at 4,640,252 B genuinely is ~4.5 MB as claimed. REFUTED: ":52 claims the base test suite runs without `Matrix` — but `Matrix::` is reached at 2 sites with only 1 `requireNamespace` guard." There is exactly one `Matrix::` *call* (R/pilar10_graph_nn.R:148) and it sits inside `if (requireNamespace("Matrix", quietly = TRUE))` at :147; :120 is a comment. cran-comments is correct about Matrix. Severity deflated from blocker: this is a ~20-minute prose/arithmetic fix in an .Rbuildignore'd file, embarrassing but code-neutral.

**Action**

> Delete the hand-written numbers. Run `R CMD check --as-cran` once, paste the verbatim tail of the log into `cran-comments.md`, and generate the size table with `du -b inst/extdata/* man/figures/*` rather than from memory. Drop the "0 notes" line and instead explain the (unavoidable) size NOTE.

#### FDE7C43 — Installed size will NOTE: inst/extdata 9.98 MB + man/figures 2.3 MB, of which a 1.9 MB PNG logo

`CRAN readiness` · tech-debt · high · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> tools/status/check.log:31-36 records installed size is 11.7Mb with doc 4.5Mb, extdata 4.2Mb, help 1.5Mb. On disk at HEAD: du -sk inst/extdata = 2268 KB, man/figures = 716 KB.

**Impact**

> `* checking installed package size ... NOTE` is unavoidable and will be the first thing quoted back. CRAN routinely rejects >10 MB first submissions outright pending justification, and the justification currently on file (cran-comments.md:67-96) misstates the sizes it is justifying.

**Action**

> Three mechanical wins before touching the benchmark bundles: (1) re-encode `man/figures/logo.png` at 240px with `optipng`/`pngquant` — 1.9 MB to ~40 KB; (2) delete unreferenced `inst/extdata/llm_kg_smoke_claims.jsonl` and `man/figures/pillar4-foundation.png`; (3) re-save the five largest `.rds` with `saveRDS(..., compress = "xz")`. Then re-measure and rewrite the cran-comments size section from `du -b` output.

#### F36D2FE — The "v3.11.0" work is committed and self-referenced in shipped code, but no version exists: no DESCRIPTION bump, no NEWS section, no tag

`Release consistency` · process-gap · high · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> R/foundation_weights.R:82 edaphos_version = c(1.2.0, 4.0.0); DESCRIPTION:3 Version: 0.9.0; NEWS.md:1 is the sole heading, edaphos 0.9.0 (development version - not yet released).

**Impact**

> `foundation_weights_list()` tells a user of edaphos 3.10.0 that a registry row requires edaphos 3.11.0, and `?foundation_build_cerrado_stack` documents behaviour "as of v3.11.0" -- a version that does not and may never exist. Anyone bisecting, citing, or reproducing HEAD has no version handle at all: HEAD is 16 commits of unnamed work, two of which (05cb516, 7400a2c) announce version numbers in their subject lines that appear nowhere in the package metadata. The v3.11.0 changes are therefore unreleasable as-is and unciteable.

**Action**

> Decide the number once, then make it consistent in one commit: set DESCRIPTION:3 to `Version: 3.11.0`, prepend a `# edaphos 3.11.0` section to NEWS.md covering 05cb516 (31-channel IV refit), 7400a2c (MoCo v2 hand-off), 272b378 (MPS/CUDA resume fix), 01b7836 (covr workflow), 0adabef (governance docs), fd4ab0b (301-claim corpus), and tag it `git tag -a v3.11.0`. If v3.11.0 is not to be released, revert the v3.11.0 strings in R/foundation_weights.R:82, R/foundation_embed_coords.R:186,204,220 and re-roxygenise so man/ stops claiming a nonexistent version.

#### F5F7D9A — The "1 345 tests" figure is unreproducible, mis-attributed, and the NEWS test-count chain contains two arithmetic breaks

`Release consistency` · doc-gap · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> Narrowed to one location, and that location is the document written for external reviewers and shipped into the user's library. inst/rosc/submission.md:68-69 still reads: Unit tests: 50+ test files, 1 345 expectations, and :79 still says 14 vignettes covering all 10 pillars (there are 19 in vignettes/). NEWS.md:326-331 explicitly withdraws the 1 345 figure, so submission.md is now the last surviving instance of it.

**Impact**

> 1345 is defensible ONLY on a machine with torch, dagitty, bnlearn and dbarts installed (the 109 gated blocks would then execute and multiply into expectations) -- but that is nowhere stated, and no environment in the repo reproduces it. As published, the number is unverifiable by any reader and demonstrably wrong in the environment cran-comments.md itself designates as the base case. inst/rosc/submission.md:69's "50+ test files" understates 68, and calling 1345 "expectations" in one file and "unit tests" in another means the project does not know which quantity it is quoting.

**Verification correction**

> none — independently measured: 68 `test-*.R` files, 460 `test_that(` blocks, 1089 `expect_` calls, 75 `skip_if_not_installed(`. README.md:12 badge `tests-1345%20pass`, NEWS.md:72, cran-comments.md:30-35, inst/rosc/submission.md:69 all verified verbatim. Arithmetic breaks verified: NEWS.md:299 (3.6.0)=1274, NEWS.md:242 (3.7.0)=1282 but 1274+7=1281 (off by 1); NEWS.md:195 (3.8.0)=1308 but 1282+20=1302 (off by 6). The Ollama attribution is verified impossible: `grep -rn 'skip_on_cran|skip_if_offline|skip_on_ci' tests/testthat/` returns exactly one hit (test-quantum-kernel-rcpp.R:46). Commit 4b15fb7 "fix(ci/windows): suppress cosmetic sweep() warning in test-pilar8-no-edge.R:42" exists in `git rev-list v3.10.0..HEAD`, confirming the blamed warning was already suppressed. README.md:1672 "**109+ unit and integration tests**" confirmed self-contradictory with the 1345 badge.

**Action**

> Pick one measured quantity and state the environment with it, e.g. "460 test_that blocks / 1089 expectations; 1022 pass + 109 skipped without torch/dagitty/bnlearn/dbarts (R 4.6.1 aarch64-darwin)". Regenerate the README.md:12 badge from that number, delete or correct the contradictory README.md:1672 "109+", fix the +7/+20 arithmetic at NEWS.md:242 and NEWS.md:195, and rewrite cran-comments.md:30-35 to report the true skip count and the true warning source (test-pilar7-bhs-edge.R:61, not Pilar 8 sweep).

#### F10D9DC — edaphos-cerrado-moco-v2 ships as an all-NA placeholder row in the exported public registry, keyed to a nonexistent package version 3.11.0

`Incomplete implementations` · incomplete-implementation · high · effort: minutes · verdict: **CONFIRMED**

**Evidence**

> The v2 registry row is still an all-NA placeholder in an exported function: R/foundation_weights.R:67 (url), :71 (sha256), :75 (doi) and :80 (published_at) are NA_character_ with the same filled-after-the-Zenodo-upload comments, and two further fields, norm_stats_url (:95-96) and norm_stats_status (:98-101), are NA and pending. The nonexistent version it is keyed to changed number rather than going away: :82 is now edaphos_version = c(1.2.0, 4.0.0) against DESCRIPTION:3 Version: 0.9.0.

**Impact**

> `foundation_weights_list()` is an exported catalogue documented (R/foundation_weights.R:87-100) as describing "every pretrained encoder published by the `edaphos` project". Half its rows describe an artefact that does not exist, with a `license = "CC-BY-4.0"` and a full hyperparameter spec that make it look publishable. Users reading the table, or scripting over it, cannot distinguish published from aspirational except by NA-checking four columns. The `edaphos_version = "3.11.0"` column tells a user the weights need a package release that is not on CRAN, GitHub, or in NEWS.

**Action**

> Either (a) drop the v2 row from `.foundation_weights_registry()` until the Zenodo deposit exists and re-add it in the release that publishes it, or (b) add an explicit `status` column (`"published"` / `"pending"`) so the placeholder is machine-readable, document it in the `@return` block at R/foundation_weights.R:100, and change `edaphos_version` to the version that will actually ship it. Separately, replace the v3.11.0 references in R/foundation_embed_coords.R:186,204,220 with 3.10.0 and re-roxygenise so man/foundation_build_cerrado_stack.Rd stops advertising a nonexistent release.

#### F873468 — foundation_build_cerrado_stack() silently writes a truncated stack to the cache when any geodata fetch fails, then reuses it forever

`Incomplete implementations` · bug · high · effort: hours · verdict: **CONFIRMED**

**Evidence**

> Half fixed. The build path now asserts the channel count: .stack_expected_layers() at R/foundation_embed_coords.R:309 and the guard at :625-633 stop before writing when the fetched layer count does not match the schema. The cache-hit path is untouched and it is the half the title names: :495-498 still does if (!force && file.exists(stack_path)) { message(Using cached stack); return(terra::rast(stack_path)) } with no terra::nlyr() check, so any short stack already written under a schema-keyed filename is still returned forever with only an informational message.

**Impact**

> A transient WorldClim outage during the first call yields a 7-layer stack (5 SoilGrids + 2 SRTM) cached under the filename `cerrado_stack_v1_encoder_<hash>.tif`, which claims to be the v1_encoder schema. Every subsequent call returns that poisoned cache with only an informational "Using cached stack" message -- `force = TRUE` is the only escape and the user has no signal they need it. Feeding it to the 31-channel v1 encoder produces a torch conv2d channel-mismatch error far from the cause; feeding it to any user code that indexes layers positionally silently reads the wrong covariate. The docstring at :202-204 says this rewrite exists specifically to stop the IV benchmark falling back to a synthetic stack, so a silently-truncated real stack is the exact failure mode it was built to prevent.

**Action**

> After line 361 in R/foundation_embed_coords.R, assert the schema's channel count before writing: `expected <- if (schema == "v1_encoder") 31L else 10L; if (terra::nlyr(stk) != expected) stop(sprintf("schema '%s' expects %d layers but only %d could be fetched (%s). Re-run when the sources are reachable.", schema, expected, terra::nlyr(stk), paste(names(layers), collapse=", ")))`. Also convert the five `message("      [warn] ", ...)` calls to `warning(...)` so partial failures are visible to `withCallingHandlers` and to test suites, and validate `terra::nlyr()` on the cache-hit path at line 245 before returning.

#### F8EC452 — No CI leg has ever executed the torch code paths: 74 test blocks / 223 expectations / ~3,140 LOC unexercised

`Test coverage` · process-gap · high · effort: hours · verdict: **PARTIALLY_TRUE**

**Evidence**

> .github/workflows/R-CMD-check.yaml:33 adds - {os: ubuntu-latest, r: release, torch: true}; :41 TORCH_INSTALL: ${{ matrix.config.torch && 1 || 0 }}; a cached torch::install_torch() step and a post-check step that fails the leg if any torch test skipped. test-coverage.yaml:33-52 unchanged.

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

- **FD3C0C1** (CI & infra, minutes) — Chunk option in pilar4-simclr vignette calls `reticulate::` unguarded with broken `&&`/`||` precedence -- hard error in exactly the Docker configuration
  - Replace the chunk option at vignettes/pilar4-simclr-embeddings.Rmd:361 with `eval=.torch_ok` (semantically identical, no reticulate dependency), or if the Python path is genuinely intended write `eval=.torch_ok && requireNamespace("reticulate", quietly = TRUE) && reticulate::py_available()`. Add `reticulate` to the Dockerfile install list, or leave it out and confirm the vignette renders. Add a grep-based lint (or an explicit item in the release checklist) for `[a-zA-Z]+::` appearing in a chunk option without a preceding `requireNamespace` in the same expression.

- **F0E4DC1** (Code quality, hours) — Pillars 8/9/10 default backend="r" never trains the architecture it is named after, while DESCRIPTION/README mark them "implemented"
  - Either (a) rename the pure-R paths to what they are — `backend = "elm"` / `"random-features"` — and state in DESCRIPTION, README.md:375-381 and R/pillars_roadmap.R that pillars 8/9/10 require torch for the full architecture; or (b) implement backprop for the frozen layers. Option (a) is hours of edits and is honest; option (b) is weeks. Do NOT submit to CRAN/rOpenSci with the current wording. At minimum, add a `message()` at R/pilar8_neural_operators.R:106, R/pilar9_diffusion_models.R:171 and R/pilar10_graph_nn.R:193 when `backend == "r"` naming the limitation.

- **F7EC076** (Code quality, hours) — Twelve copies of skip_if_no_torch() in three divergent flavours, orphaning the helper-torch.R that was added to replace them
  - Delete all 12 local definitions and rename the 52 undotted call sites to `.skip_if_no_torch()`. Adopt variant (b)'s tensor allocation inside helper-torch.R:7 (it is the only sound check) while keeping the `isTRUE()` wrapper. Then grep-assert in CI that `skip_if_no_torch <- function` appears nowhere under tests/ so the duplication cannot come back.

- **FCF64DC** (Code quality, days) — Naming schism: pilar/pillar, ordinal/domain module names, al_* vs active_*, and five undocumented cryptic export prefixes
  - Three mechanical passes, none behaviour-changing. (1) `git mv` the 7 R/pilar*.R files and 17 test files to domain names matching pillars 1-6 (bhs_*.R, neural_operators*.R, diffusion*.R, graph_nn*.R) and fix the two user-facing print strings at R/bridges_active_learning_v3.R:313 and R/bridges_structure_v3.R:225 to "Pillar". (2) Extend R/pillars_roadmap.R:8-15 from six rows to ten, retitle :1 from "six pillars" to "ten pillars", and add the `bhs_*`/`no_*`/`dm_*`/`gnn_*`/`qf_*` namespace entries; either rename `active_learning_posterior` to `al_posterior` (with an alias for back-compat) or amend the `al_*` claim in R/pillars_roadmap.R:14 and README.md:379. (3) Rename the four shadowing parameters to `fit` or `object` (R/bridges_active_learning_v3.R:260, :174; R/bridges_structure_v3.R:50, :196) and re-roxygenise. Consider renaming the `no_*` prefix to `fno_*`/`don_*`.

- **FD27999** (Code quality, days) — Twelve exported functions are never referenced anywhere in tests/, including the entire advertised tile-source pipeline
  - Add offline tests for the cheap half first: argument validation and returned-descriptor schema for each `foundation_tile_source_*` (they should be pure constructors — assert the returned list's fields and that a bad CRS/bbox errors) and for `foundation_build_cerrado_stack` with a stubbed source. Gate the network-touching halves behind `skip_on_cran()` + `skip_if_offline()`. Separately, reconsider whether `edaphos_zenodo_release` belongs in R/ at all — it is release tooling, not a soil-mapping algorithm, and shipping it as a public export means CRAN users can POST to Zenodo; moving it to inst/scripts/ removes both the test debt and the API-surface cost.

- **F4484D7** (CRAN readiness, days) — 5 of 14 vignettes are written in Portuguese while DESCRIPTION declares `Language: en-US`
  - Decide one way: either translate the 5 Portuguese vignettes to English (and fix `organised`->`organized`, `synthesised`->`synthesized` in DESCRIPTION:8,27), or move them out of `vignettes/` into `articles/` and drop them from the tarball. Then add `spelling` to Suggests plus `tests/spelling.R` so `inst/WORDLIST` is actually enforced instead of being 20 KB of shipped dead weight.

- **F4EC093** (CRAN readiness, minutes) — `src/Makevars.win` documents a Unix `src/Makevars` that does not exist
  - Add `src/Makevars` containing `PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)` (the standard RcppArmadillo skeleton), which makes `Makevars.win`'s comment true and removes the platform-dependent link assumption.

- **F83F26A** (CRAN readiness, hours) — RELEASE-CHECKLIST-v3.10.0.md instructs the maintainer to upload two artefacts that do not exist, and asserts a green state contradicted by the live test run
  - Replace the hard-coded artefact paths with the commands that produce them (`devtools::build()`, and whatever script built `zenodo_release.zip` — it is not in `tools/`). Rename/renumber the checklist for the actual next version, add a NEWS.md `# edaphos 3.11.0` section for the HEAD~1 work, and gate the header claim on a passing `devtools::test()`.

- **F00AF5C** (Release consistency, hours) — Two overlapping release checklists disagree with each other and both claim to be the authoritative list of remaining steps
  - Delete RELEASE.md (its v2.9.1 content is superseded), rename the survivor to a version-free `RELEASE-CHECKLIST.md`, and change .Rbuildignore:24 to `^RELEASE-CHECKLIST.*\.md$` so it stays excluded across releases. Reconcile the install-size numbers to one figure and fold RELEASE.md:16-18's concept-DOI-resolves-to-v0.2.0 warning into the surviving checklist.

- **FB9DA9E** (Release consistency, days) — The 84 KB README documents nothing after v2.8.0; its only 3.x reference is the version badge
  - Either add Pillar 7-10 sections and TOC entries and retitle README.md:371 to "The ten pillars at a glance" (updating the anchor at README.md:10 and the TOC entry at README.md:210), or drop the "10/10 pillars" badge until the README backs it. Delete the stale "🆕" prefixes at README.md:147 and :230, correct README.md:1674-1675 to the real check status (see finding #4), and change "six" to "seven" at README.md:364.

- **FBB414A** (Release consistency, hours) — .zenodo.json carries no version field at all and its description is frozen at v1.8.0
  - Add `"version": "3.10.0"` (or 3.11.0 per finding #1) and `"publication_date"` to .zenodo.json, and replace the .zenodo.json:3 description with the current 10-pillar text from DESCRIPTION:8-28 plus the v1.9.x-v3.10.0 highlights already written in cran-comments.md:105-132. Then the manual steps at RELEASE-CHECKLIST-v3.10.0.md:63-65 become unnecessary.

- **FC9610C** (Release consistency, hours) — The only DOI badge is a concept DOI the repo itself says resolves to v0.2.0, and nothing after v1.5.0 was ever deposited
  - Execute the Zenodo deposit (RELEASE-CHECKLIST-v3.10.0.md:51-71) so a version DOI exists, then add a version-DOI badge alongside the concept-DOI badge at README.md:7 and record the minted id in CITATION.cff. Add a release-publishing workflow so README.md:8 has Releases to report. Until the deposit exists, either remove RELEASE.md:16-18's known-stale badge or annotate it in the README as "concept DOI (all versions)" so readers do not mistake it for the current release.

- **FF84B54** (Release consistency, hours) — Two parallel version schemes collide inside a single README table: "v1.x roadmap lines" are interleaved with package 3.x versions, and v3.0.0 means two different things
  - Split the table in two: a "Released" table keyed strictly on DESCRIPTION versions (with every 2.6.0-3.10.0 row filled in, and Pilar 10 corrected from v2.8.0 to v2.6.0 at README.md:1713), and a separate "Open research promises" list that uses names rather than version numbers (e.g. "MoCo v2 200k-step re-benchmark", "CRAN + rOpenSci submission") so no roadmap item can ever collide with a release number again. Mark the three completed rows (README.md:1714-1716) as done and stop using v1.x strings in commit subjects for work landing in 3.x.

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

- **F366B1F** (Scientific reproducibility, hours) — README's headline benchmark tables are two to four release cycles stale, and the current 6-method result exists only in NEWS.md
  - Promote the v3.4.0 six-method table from `NEWS.md:421-428` into `README.md`, replacing or clearly superseding `README.md:243-255`, and stamp each README table with the artefact and version it came from (e.g. "computed at v3.4.0 from `inst/extdata/benchmark_wosis_6pilar.rds`"). Correct "56 covariates" → 59 and disclose `lon`/`lat`/`year`. Correct the quantum caption to state the 250-row per-fold training cap and n = 1081. Regenerate the `inst/extdata` size table with `file.size()` and add the two benchmark bundles. Fix `README.md:841`.

- **F5672C5** (Scientific reproducibility, hours) — DESCRIPTION's "every vignette runs offline" is false: four advertised vignettes are not vignettes, and the Pilar 4 × Pilar 6 vignette evaluates nothing
  - Decide per document: move the four `articles/*.Rmd` into `vignettes/` (they read only `inst/extdata`, so they should build offline), or remove them from the `README.md:1644-1662` table and from the "Used by" column at `:1615-1632`, replacing `vignette("llm-kg-benchmark")` at `:702` with a pkgdown URL. Enable the two chunks in `vignettes/pilar4-pilar6-quantum.Rmd` — the `benchmark-table` chunk only needs `readRDS(system.file(...))` and should evaluate offline. Add `getting-started` to the vignette table. Add a CI check that every `vignette("...")` string in `README.md` resolves in the built package.

- **F71D795** (Incomplete implementations, hours) — The spBayes backend is advertised as an equal peer in README/NEWS/man but predict(), as_edaphos_posterior() and al_query_bhs() all fail on it
  - Minimum: add a `backend` guard to `as_edaphos_posterior.edaphos_bhs` at R/pilar7_bayesian_hierarchical.R:412 mirroring the one at :355 so it fails with a readable message; fix the stale "for v2.3.0" text in the :356 message to name the current version; and add an explicit `\note{}` to man/bhs_fit.Rd, man/predict.edaphos_bhs.Rd and README.md:272 stating that only `gibbs`/`rcpp` support prediction, posterior extraction and active-learning queries. Better: have the spBayes branch populate `w_post_mean` from `fit_sp$p.w.recover.samples` and `phi_hat` from `median(theta_draws[,"phi"])`, which would make all three methods work.

- **F9046AE** (Incomplete implementations, minutes) — bhs_fit()'s rcpp backend is absent from its own @param documentation, and al_query_bhs() rejects it despite the fit being complete
  - Add `"rcpp"` to the `@param backend` block at R/pilar7_bayesian_hierarchical.R:68-70 (describing the RcppArmadillo fast path) and re-roxygenise. Relax R/bridges_active_learning_v3.R:263 to `if (!bhs_fit$backend %in% c("gibbs", "rcpp"))` and add a test in tests/testthat/test-bridges-v3.R that `al_query_bhs()` succeeds on a `backend = "rcpp"` fit.

- **FFFC52E** (Incomplete implementations, minutes) — causal_iv bootstrap silently discards failed 2SLS replicates and rewrites B to the survivor count
  - In R/causal_iv.R:360-372, record both counts and warn: keep `B_requested`, compute `n_failed <- B - length(draws)`, add `if (n_failed > 0) warning(sprintf("%d of %d bootstrap replicates failed to fit 2SLS (weak or collinear instruments after resampling); the posterior uses %d draws.", n_failed, B, length(draws)))`, `stop()` when `length(draws) < 2`, and store both `B_requested` and `B_effective` in the metadata list at :369 instead of silently reassigning `B`.

- **F86487C** (Test coverage, hours) — R/pilar7_bayesian_hierarchical.R:270-272 cites a test that does not perform the verification it claims
  - Either implement the claimed check -- keep a `.bhs_gibbs_dense()` reference implementation as an internal (not exported) function and assert `expect_equal(draws_fast, draws_dense, tolerance = 1e-10)` under a fixed seed in test-pilar7-bhs-fastpath.R -- or delete the unsupported sentence at R/pilar7_bayesian_hierarchical.R:270-272 and replace it with what the test actually contracts.

- **FA6ECC8** (Test coverage, hours) — The RcppArmadillo BHS Gibbs backend has no real numerical-agreement test: one scalar mean at 0.2 tolerance, w_post_mean never compared, no edge cases
  - Replace the scalar check in tests/testthat/test-pilar7-bhs-rcpp.R:37-56 with a draw-by-draw comparison: run both backends with the same `seed` and assert `expect_equal(fit_r$beta_draws, fit_cpp$beta_draws, tolerance = 1e-8)` plus the same for sigma2_draws, tau2_draws and w_post_mean. If that fails, the C++ header comment at src/bhs_gibbs_rcpp.cpp:24-25 is wrong and should be corrected -- either way the ambiguity must be resolved. Add `backend = "rcpp"` variants of the 10 blocks in test-pilar7-bhs-edge.R (parameterise the file over both backends), and reconcile `arma::solve` at src/bhs_gibbs_rcpp.cpp:91 with `lm.fit` at R/pilar7_bayesian_hierarchical.R:238.

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
| FFBBEBB | Release consistency | hours | Dockerfile self-identifies as v2.1.0 and pins a 2026-04-23 CRAN snapshot, but installs HEAD |
| F1A720B | Roadmap promises | weeks | v1.8.3 (expand LLM gold standard from 72 to 300 claims) is untouched — still 30 abstracts / 72 claims |
| F2FC8F9 | Roadmap promises | minutes | V1_3_2_HANDOFF.md instructs the maintainer to cd into a directory named after a different project |
| F3E4CA6 | Roadmap promises | hours | Documentation promises that point at content which does not exist: cheatsheets "on the pkgdown site", P8/P9 benchmarks "in vignettes/" |
| F4BEE44 | Roadmap promises | minutes | package_v2_for_zenodo.R fails with a cryptic stopifnot before its own step-count guard, and drops the resume hint from its error message |
| F4EE43C | Roadmap promises | hours | Roadmap table and NEWS were never updated for the last two feature commits; DESCRIPTION 3.10.0 conflicts with the 3.11.0 baked into the weights registry |
| F66D149 | Roadmap promises | minutes | Stale dead-end in data-raw/causal_iv_benchmark.R blocks a path that v1.9.1 already delivered |
| FCC0D53 | Roadmap promises | days | Promised production-scale outputs never produced: the 10k-abstract LLM-KG run and the 6-pillar benchmark wrapper set |
| F37E56E | Incomplete implementations | hours | foundation_embed_at_coords() converts a failed raster block read into an all-zero patch that is indistinguishable from a real embedding |
| F3A34C0 | Incomplete implementations | minutes | foundation_build_cerrado_stack() calls digest::digest() unguarded, but digest is Suggests-only -- the exported function dies on a clean install |
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

### Phase 1 — Scientific integrity

_In a research package the empirical claims are the product._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | F0F5D47 | medium | hours | Pretrained-weight DOI is real but the v2 registry row is all-NA while claiming a nonexistent version; CITATION.cff and .zenodo.json are many releases stale and assign one DOI to ten releases |
| [ ] | F366B1F | medium | hours | README's headline benchmark tables are two to four release cycles stale, and the current 6-method result exists only in NEWS.md |
| [ ] | F5672C5 | medium | hours | DESCRIPTION's "every vignette runs offline" is false: four advertised vignettes are not vignettes, and the Pilar 4 × Pilar 6 vignette evaluates nothing |

### Phase 2 — Version coherence

_One version number, asserted in one place, tagged once._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | F36D2FE | high | hours | The "v3.11.0" work is committed and self-referenced in shipped code, but no version exists: no DESCRIPTION bump, no NEWS section, no tag |
| [ ] | FB9DA9E | medium | days | The 84 KB README documents nothing after v2.8.0; its only 3.x reference is the version badge |
| [ ] | F00AF5C | medium | hours | Two overlapping release checklists disagree with each other and both claim to be the authoritative list of remaining steps |
| [ ] | FBB414A | medium | hours | .zenodo.json carries no version field at all and its description is frozen at v1.8.0 |
| [ ] | FC9610C | medium | hours | The only DOI badge is a concept DOI the repo itself says resolves to v0.2.0, and nothing after v1.5.0 was ever deposited |
| [ ] | FF84B54 | medium | hours | Two parallel version schemes collide inside a single README table: "v1.x roadmap lines" are interleaved with package 3.x versions, and v3.0.0 means two different things |

### Phase 3 — Close the ten-pillar promise

_DESCRIPTION claims ten pillars; the shipped docs document six._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | F873468 | high | hours | foundation_build_cerrado_stack() silently writes a truncated stack to the cache when any geodata fetch fails, then reuses it forever |
| [ ] | F10D9DC | high | minutes | edaphos-cerrado-moco-v2 ships as an all-NA placeholder row in the exported public registry, keyed to a nonexistent package version 3.11.0 |
| [ ] | FD528FC | medium | days | Three exported functions with .Rd pages and pkgdown entries are permanent stop() stubs |
| [ ] | F492008 | medium | hours | Four pkgdown navbar links point at articles pkgdown never builds, and man/edaphos-package.Rd tells users to open a vignette that is not in the package |
| [ ] | FD3DBCB | medium | hours | Two competing release checklists, one stale, pointing at a tarball path that does not exist |
| [ ] | FF7221D | medium | hours | v1.3.2 (MoCo v2 200k-step encoder) is 43 % short of target and the checkpoint exists nowhere in the repository |
| [ ] | F71D795 | medium | hours | The spBayes backend is advertised as an equal peer in README/NEWS/man but predict(), as_edaphos_posterior() and al_query_bhs() all fail on it |
| [ ] | F2E57CE | medium | minutes | Step 4 of the v1.3.2 hand-off (wire_up_v2_doi.R) matches nothing and silently writes the timestamp into the `url` field |
| [ ] | F9046AE | medium | minutes | bhs_fit()'s rcpp backend is absent from its own @param documentation, and al_query_bhs() rejects it despite the fit being complete |
| [ ] | FFFC52E | medium | minutes | causal_iv bootstrap silently discards failed 2SLS replicates and rewrites B to the survivor count |

### Phase 4 — CRAN submission

_Only meaningful once phases 0-3 hold._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | FE42047 | high | hours | pkgdown workflow cannot succeed: `has_concept("pilar1")` matches zero topics and 4 navbar links point at pages never built |
| [ ] | FDE7C43 | high | hours | Installed size will NOTE: inst/extdata 9.98 MB + man/figures 2.3 MB, of which a 1.9 MB PNG logo |
| [ ] | F3D7BED | medium | days | 33 of 43 NEWS.md releases have no git tag and there is no release-automation workflow, contradicting CONTRIBUTING's tagging promise |
| [ ] | F5E91CE | medium | days | Dockerfile is not a reproducibility artefact: builds from GitHub main, unpinned libtorch, R 4.4.1 in no CI leg, v2.1.0 metadata, missing Suggests |
| [ ] | F4484D7 | medium | days | 5 of 14 vignettes are written in Portuguese while DESCRIPTION declares `Language: en-US` |
| [ ] | F29E750 | medium | hours | Two competing release checklists contradict each other and describe a deploy action the pkgdown workflow does not use; referenced artefacts do not exist |
| [ ] | F6F101E | medium | hours | CI builds vignettes, but 3 of 14 self-truncate to a one-line stub without libtorch -- and CONTRIBUTING tells contributors to skip vignette building entirely |
| [ ] | F83F26A | medium | hours | RELEASE-CHECKLIST-v3.10.0.md instructs the maintainer to upload two artefacts that do not exist, and asserts a green state contradicted by the live test run |
| [ ] | FD3C0C1 | medium | minutes | Chunk option in pilar4-simclr vignette calls `reticulate::` unguarded with broken `&&`/`\|\|` precedence -- hard error in exactly the Docker configuration |
| [ ] | F4EC093 | medium | minutes | `src/Makevars.win` documents a Unix `src/Makevars` that does not exist |

### Phase 5 — Code quality and tech debt

_Non-blocking, but cheaper to fix before the API is frozen by CRAN._

| Done | ID | Sev | Effort | Item |
| --- | --- | --- | --- | --- |
| [ ] | F8EC452 | high | hours | No CI leg has ever executed the torch code paths: 74 test blocks / 223 expectations / ~3,140 LOC unexercised |
| [ ] | FCF64DC | medium | days | Naming schism: pilar/pillar, ordinal/domain module names, al_* vs active_*, and five undocumented cryptic export prefixes |
| [ ] | FD27999 | medium | days | Twelve exported functions are never referenced anywhere in tests/, including the entire advertised tile-source pipeline |
| [ ] | FB6D884 | medium | days | 12 exported functions are never called by any test, including the entire tile-download layer and a function that recursively deletes a directory |
| [ ] | FBCB1E4 | medium | days | The v3.8.0 friendly-error work covers 4 of 169 exports; .assert_type/.stopf adopted in 6 of 70 R/ files |
| [ ] | F0E4DC1 | medium | hours | Pillars 8/9/10 default backend="r" never trains the architecture it is named after, while DESCRIPTION/README mark them "implemented" |
| [ ] | F7EC076 | medium | hours | Twelve copies of skip_if_no_torch() in three divergent flavours, orphaning the helper-torch.R that was added to replace them |
| [ ] | F86487C | medium | hours | R/pilar7_bayesian_hierarchical.R:270-272 cites a test that does not perform the verification it claims |
| [ ] | FA6ECC8 | medium | hours | The RcppArmadillo BHS Gibbs backend has no real numerical-agreement test: one scalar mean at 0.2 tolerance, w_post_mean never compared, no edge cases |
| [ ] | FC5841E | medium | minutes | Three of four wall-clock assertions run on CRAN: only 1 skip_on_cran() exists in the whole 460-block suite |

### Unphased

| Done | ID | Sev | Area | Item |
| --- | --- | --- | --- | --- |
| [ ] | F0CBFC4 | low | CI & infra | test-coverage has no threshold gate, no codecov.yml, and diverges from R-CMD-check on TORCH_INSTALL; reported coverage has an invisible ~75% ceiling |
| [ ] | F6330AE | low | CI & infra | pkgdown site loads mermaid from a third-party CDN with no integrity attribute, on a surface SECURITY.md declares in scope |
| [ ] | FA46190 | low | CI & infra | Documented quality gates (spell check, URL check, lint) exist in prose and templates but in no workflow; `_R_CHECK_FORCE_SUGGESTS_` is never relaxed across 40 Suggests |
| [ ] | FAACA6C | low | CI & infra | `needs: website` and `needs: coverage` are no-ops: DESCRIPTION declares no Config/Needs/* fields |
| [ ] | FAF9367 | low | CI & infra | .Rbuildignore hygiene: version-pinned checklist pattern, duplicated entry, dead README.Rmd rule |
| [ ] | FDA19FA | low | CI & infra | No dependency pinning outside the Dockerfile; floating action tags in a job granted `contents: write` |
| [ ] | F434C69 | low | Code quality | %\|\|% is copy-pasted into 7 files; the definition that actually wins is decided by alphabetical collation, not by design |
| [ ] | F503F9C | low | Code quality | quantum_kernel_rcpp allocates nX * 2^n complex states but its only guard is a warning keyed on n alone |
| [ ] | F594BF7 | low | Code quality | Dead code, an undocumented non-dotted internal, and three comment/code contradictions in the pillar 7-10 modules |
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
| [ ] | FFBBEBB | low | Release consistency | Dockerfile self-identifies as v2.1.0 and pins a 2026-04-23 CRAN snapshot, but installs HEAD |
| [ ] | F1A720B | low | Roadmap promises | v1.8.3 (expand LLM gold standard from 72 to 300 claims) is untouched — still 30 abstracts / 72 claims |
| [ ] | F2FC8F9 | low | Roadmap promises | V1_3_2_HANDOFF.md instructs the maintainer to cd into a directory named after a different project |
| [ ] | F3E4CA6 | low | Roadmap promises | Documentation promises that point at content which does not exist: cheatsheets "on the pkgdown site", P8/P9 benchmarks "in vignettes/" |
| [ ] | F4BEE44 | low | Roadmap promises | package_v2_for_zenodo.R fails with a cryptic stopifnot before its own step-count guard, and drops the resume hint from its error message |
| [ ] | F4EE43C | low | Roadmap promises | Roadmap table and NEWS were never updated for the last two feature commits; DESCRIPTION 3.10.0 conflicts with the 3.11.0 baked into the weights registry |
| [ ] | F66D149 | low | Roadmap promises | Stale dead-end in data-raw/causal_iv_benchmark.R blocks a path that v1.9.1 already delivered |
| [ ] | FCC0D53 | low | Roadmap promises | Promised production-scale outputs never produced: the 10k-abstract LLM-KG run and the 6-pillar benchmark wrapper set |
| [ ] | F37E56E | low | Incomplete implementations | foundation_embed_at_coords() converts a failed raster block read into an all-zero patch that is indistinguishable from a real embedding |
| [ ] | F3A34C0 | low | Incomplete implementations | foundation_build_cerrado_stack() calls digest::digest() unguarded, but digest is Suggests-only -- the exported function dies on a clean install |
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

To close a finding, add three fields to its entry — `"resolved": true`,
`"resolved_in": "<commit>"` and a `"resolution"` string holding the
measurement that no longer reproduces it. It then moves out of the work order
and into "Closed since the audit" above, with that measurement quoted. The
original `evidence` block describes the audited commit and stays untouched, so
the register keeps saying what was true then as well as what is true now.

