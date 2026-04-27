# NA

## Summary

## Type of change

feat (new exported function / pillar / bridge)

fix (bugfix; no public-API change)

perf (faster but same outputs)

refactor (internal restructure)

docs / test (no R/ source change)

BREAKING (public API change – justify in the body)

## Affected pillar(s)

## Test plan

[`devtools::test()`](https://devtools.r-lib.org/reference/test.html)
passes locally

`devtools::check(args = c("--no-manual", "--no-build-vignettes"))`
passes

Added a `tests/testthat/test-*.R` file or new `test_that()` for new
behaviour

No new warnings in
[`devtools::spell_check()`](https://devtools.r-lib.org/reference/spell_check.html)
(or added to `inst/WORDLIST`)

If compiled code changed: numerical-equivalence test added under
`tests/testthat/test-*-rcpp.R`

## NEWS.md

Prepended a versioned entry under the next planned release

## Reviewer notes
