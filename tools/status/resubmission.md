## Resubmission

This is a resubmission. The CRAN incoming pretests of 2026-11-07 reported:

* **Debian: installation ERROR, `undefined symbol: dgelsd_`.** The package had
  a `src/Makevars.win` but no `src/Makevars`, so on Linux the RcppArmadillo
  code was not linked against LAPACK and BLAS. Added `src/Makevars` with
  `PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)`.
* **Invalid file URIs in README.md** (`LICENSE.md`, `cran-comments.md`,
  `tools/status/check.log`). These files are not in the tarball. The links now
  point to the files on GitHub.
* **Possibly misspelled words in DESCRIPTION.** Cerrado (a Brazilian biome),
  Cinelli, Hazlett, Kalman, McBratney, Mendonca, Minasny and Velickovic are
  proper names; contrastive, convolutional, denoising, pedogenetic and
  pedometry are standard technical terms. "pre-training" is now written
  "pretraining".

On the maintainer's network `papers.nips.cc` and `proceedings.neurips.cc`
time out (libcurl error 28). The two `papers.nips.cc` links in README.md now
point to the same papers on arXiv. The remaining
`proceedings.neurips.cc` link (Ho, Jain and Abbeel, 2020) passes the URL check
on GitHub Actions and was not flagged by the previous CRAN pretest.
