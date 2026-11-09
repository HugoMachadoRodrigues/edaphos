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
