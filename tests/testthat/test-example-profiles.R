## edaphos_example_profiles() is what every example in the package calls
## first, and until now no test called it. What it promises, from its help
## page: simulated data that says it is simulated, a regular coordinate
## lattice so no point can coincide with a survey site, horizons that belong
## to the listed profiles, and a row cap that does what it says.

test_that("profiles are flagged synthetic and sit on a regular lattice", {
  p <- suppressMessages(edaphos_example_profiles())
  expect_s3_class(p, "data.frame")
  expect_true(isTRUE(attr(p, "synthetic")))
  expect_gt(nrow(p), 0L)
  expect_false(anyDuplicated(p$profile_id) > 0L)

  # A lattice: every coordinate takes one of a few evenly spaced values.
  for (v in list(p$lon, p$lat)) {
    u <- sort(unique(v))
    expect_lt(length(u), nrow(p))
    expect_lt(diff(range(diff(u))), 1e-8)
  }
})

test_that("horizons belong to listed profiles and are ordered within each", {
  p <- suppressMessages(edaphos_example_profiles())
  h <- suppressMessages(edaphos_example_profiles(what = "horizons"))
  expect_true(isTRUE(attr(h, "synthetic")))
  expect_true(all(h$profile_id %in% p$profile_id))
  expect_true(all(h$bottom > h$top))
  expect_equal(h$depth_mid, (h$top + h$bottom) / 2)
})

test_that("n caps the rows, resets row names, and is a no-op when too large", {
  all_p <- suppressMessages(edaphos_example_profiles())
  five  <- suppressMessages(edaphos_example_profiles(n = 5L))
  expect_equal(nrow(five), 5L)
  expect_identical(rownames(five), as.character(1:5))
  expect_equal(five$profile_id, all_p$profile_id[1:5])

  big <- suppressMessages(edaphos_example_profiles(n = nrow(all_p) + 100L))
  expect_equal(nrow(big), nrow(all_p))
})

test_that("what = 'all' returns the whole fixture, metadata included", {
  fx <- suppressMessages(edaphos_example_profiles(what = "all"))
  expect_true(all(c("profiles", "horizons", "pedon", "meta") %in% names(fx)))
  expect_equal(fx$meta$seed, 20260901L)
})

test_that("an element a fixture lacks is an error that names what exists", {
  expect_error(
    suppressMessages(edaphos_example_profiles("soildata_like", what = "pedon")),
    "no element 'pedon'.*horizons")
})

test_that("the simulated-data notice is printed once per session, not per call", {
  env <- edaphos:::.edaphos_fixture_env
  old <- env$announced
  on.exit(env$announced <- old, add = TRUE)
  env$announced <- FALSE
  expect_message(edaphos_example_profiles(n = 1L), "SIMULATED")
  expect_silent(edaphos_example_profiles(n = 1L))
})
