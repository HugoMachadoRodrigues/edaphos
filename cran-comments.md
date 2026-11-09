<!-- GENERATED FILE -- DO NOT EDIT BY HAND.
     Regenerate:  Rscript tools/status/facts.R --check-log=<log>
                  Rscript tools/status/render-cran-comments.R
     Every figure below is read from a real R CMD check log. -->

# cran-comments for edaphos 2.0.0

## Resubmission

This is the second resubmission of 2.0.0.

### Pretest of 2026-11-08: 2 NOTEs on Windows, 2 on Debian

* **Overall checktime 15 min > 10 min (Windows), and `al_query_batchbald`
  example > 5 s (Debian) / > 10 s (Windows).** Measured cause and changes:
  * The example's 6-12 s was not BatchBALD (0.06 s) but the first call of
    `clhs`, whose namespace load pulls in `sf`, `raster` and `ggplot2`. That
    load also left a large heap, which made each of the 180 `gc()` calls
    that `R CMD check` makes between examples about ten times slower. The
    example now draws its 30 starting sites with `sample()`. Moved into
    `\donttest{}`: six more slow examples; seven that demonstrate optional
    `ggplot2` or `terra` output; and 20 whose body already ran only when
    libtorch is installed, but whose guard loaded the `torch` namespace
    and so enlarged the heap on every machine.
  * `skip_on_cran()` now guards tests that start Python through
    `reticulate` only to find that qiskit is absent, BART MCMC fits,
    spatial-model refits, a test that sleeps through a real retry backoff,
    tests that load `clhs`, and every remaining test block that took more
    than 0.5 s on a Windows runner. All of them still run on every GitHub
    Actions leg.
  * Eight of the 19 vignettes evaluate their code except in a CRAN-mode
    `R CMD check` (`_R_CHECK_PACKAGE_NAME_` set and `NOT_CRAN` not `"true"`);
    a ninth, `pillar6-quantum`, skips only its qiskit chunks there. The HTML
    in the tarball is built with full evaluation, and its text is identical
    to the previous submission's. GitHub Actions sets `NOT_CRAN=true` and
    evaluates every vignette.
  * Measured on a GitHub Actions `windows-latest` R-devel runner with a
    CRAN-mode check (`NOT_CRAN` unset, no libtorch, no manual or remote
    incoming checks, no `--run-donttest` pass): 504 s for the previous
    submission, 342 s for this one. Examples 128 s to 53 s, tests 81 s to
    59 s, vignette rebuild 124 s to 54 s. The local check below took 283 s,
    against 652 s for the previous submission.
* **Invalid URL (timeout) for `proceedings.neurips.cc` in README.md.** The
  link to Ho, Jain and Abbeel (2020) now points to the same paper on arXiv.
  No `papers.nips.cc` or `proceedings.neurips.cc` links remain.
* **Possibly misspelled words in DESCRIPTION.** Unchanged and correct:
  Cerrado (a Brazilian biome), Cinelli, Hazlett, Kalman, McBratney, Mendonca,
  Minasny and Velickovic are proper names; contrastive, convolutional,
  denoising, pedogenetic, pedometry and pretraining are standard technical
  terms.

### Pretest of 2026-11-07

* **Debian: installation ERROR, `undefined symbol: dgelsd_`.** Added
  `src/Makevars` with `PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)`.
* **Invalid file URIs in README.md** (`LICENSE.md`, `cran-comments.md`,
  `tools/status/check.log`). These files are not in the tarball; the links
  now point to the files on GitHub.

## Test environments

* Darwin 27.2.0, aarch64-apple-darwin23, R 4.6.2 (Diversified Portfolio)

GitHub Actions `R-CMD-check` also runs:

* {os: macos-latest,   r: 'release'}
* {os: windows-latest, r: 'release'}
* {os: ubuntu-latest,  r: 'devel',   http-user-agent: 'release'}
* {os: ubuntu-latest,  r: 'release'}
* {os: ubuntu-latest,  r: 'oldrel-1'}
* {os: ubuntu-latest,  r: 'release', torch: true}

## R CMD check results

`R CMD build . && R CMD check --as-cran` reported:

```
Status: 2 NOTEs
```

### NOTEs (2)

* **checking CRAN incoming feasibility**
  * CRAN reports this as a New submission. The two redirecting URLs it flagged at baseline have been fixed.
  * Origin: informational
  * Nothing to fix: 'New submission' is accurate. edaphos has GitHub and Zenodo releases (2.0.0 is DOI 10.5281/zenodo.24017391) but has never been on CRAN.
* **checking HTML version of manual**
  * The local HTML Tidy is older than R requires, so HTML validation was skipped.
  * Origin: environment
  * None needed in the package.

### INFOs (1)

* **checking installed package size**
  * Installed size 6.9 MB, above CRAN's 5 MB guidance, which CRAN's incoming check reports as a NOTE. The source tarball is 4.2 MB.
  * Origin: informational
  * Measured on the 2.0.0 tarball: inst/doc 2.9 MB, of which 55% is base64 figure data inlined by rmarkdown::html_vignette (already at 60 dpi; two widget diagrams are static SVG since 2.0.0); man 1.8 MB; inst/extdata 1.0 MB. Finding FDE7C43 (extdata at 9.98 MB and a 1.9 MB logo) is resolved. Shrinking further means dropping figures or shipping fewer rendered vignettes, a trade-off left to the maintainer rather than a defect.

## Installed size

Verbatim from the check log:

```
  installed size is  7.0Mb
  sub-directories of 1Mb or more:
    doc       2.9Mb
    extdata   1.0Mb
    help      1.6Mb
```

The installed size is 6.9 MB: rendered vignettes (inst/doc, 2.9 MB, about half of it inlined figures), help pages (1.6 MB) and committed result bundles that the vignettes read instead of recomputing (inst/extdata, 1.0 MB). The source tarball is 4.2 MB.

Git-tracked payload that ships in the tarball: 5.0 MB across 629 tracked files.

## CRAN incoming feasibility

This is a new submission. The package has not been on CRAN before.

Source tarball size: _not measured_.

## Tests

`testthat` on the checking machine: **2679 passing**, 19 skipped, 0 failing, 0 erroring, across 114 test files (750 `test_that` blocks, 2140 expectations in source).

The skips are `skip_if_not_installed()` gates on optional Suggests; 0 of the 103 gate sites in the suite are for packages absent from the checking machine.

## Downstream dependencies

None: this is a new submission, so there are no reverse dependencies.

---

Generated by `tools/status/render-cran-comments.R` from `check.log` (sha256 `5881cee4a6057c4c`) at commit `3f3181a`.
