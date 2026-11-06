## Summary

<!-- 1-3 bullets on what this PR changes and why. -->

## Type of change

<!-- Pick the closest match. -->

* [ ] feat (new exported function / pillar / bridge)
* [ ] fix (bugfix; no public-API change)
* [ ] perf (faster but same outputs)
* [ ] refactor (internal restructure)
* [ ] docs / test (no R/ source change)
* [ ] BREAKING (public API change -- justify in the body)

## Affected pillar(s)

<!-- e.g. Pillar 1 Causal, Pillar 7 BHS, P10×P1 bridge, ... -->

## Test plan

* [ ] `devtools::test()` passes locally
* [ ] `devtools::check(args = c("--no-manual", "--no-build-vignettes"))` passes
* [ ] Added a `tests/testthat/test-*.R` file or new `test_that()` for new behaviour
* [ ] No new warnings in `devtools::spell_check()` (or added to `inst/WORDLIST`)
* [ ] If compiled code changed: numerical-equivalence test added under `tests/testthat/test-*-rcpp.R`

## NEWS.md

* [ ] Prepended a versioned entry under the next planned release

## Reviewer notes

<!-- Anything specific you want me to look at? Trade-offs you considered? -->
