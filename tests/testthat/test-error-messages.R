## Tests for the user-facing error messages.  Contract:
##
##   1. The new `.stopf()` and `.assert_type()` helpers prepend the
##      caller name and append a "Hint:" line when one is provided.
##   2. `bhs_fit()`, `gnn_build_graph()`, `dm_fit()`, and
##      `no_deeponet_fit()` produce helpful errors on common
##      misuses (wrong type, missing column, dimension mismatch).

# ---------------------------------------------------------------------------
# Helper unit tests
# ---------------------------------------------------------------------------

test_that(".stopf: prepends caller name and appends hint", {
  caller <- function() edaphos:::.stopf("bad %s", "value", hint = "do X")
  e <- tryCatch(caller(), error = function(e) e)
  expect_match(conditionMessage(e), "\\[caller\\] bad value")
  expect_match(conditionMessage(e), "Hint: do X")
})

test_that(".stopf: works without hint", {
  caller <- function() edaphos:::.stopf("nope")
  e <- tryCatch(caller(), error = function(e) e)
  expect_match(conditionMessage(e), "\\[caller\\] nope")
  expect_false(grepl("Hint:", conditionMessage(e)))
})

test_that(".assert_type: emits expected/got message on failure", {
  caller <- function() edaphos:::.assert_type(FALSE, "x",
                                                  "a number", "letters")
  e <- tryCatch(caller(), error = function(e) e)
  expect_match(conditionMessage(e),
                 "`x` must be a number, got letters")
})

test_that(".assert_type: invisible TRUE on success", {
  expect_silent(edaphos:::.assert_type(TRUE, "x", "a number", "5"))
})

# ---------------------------------------------------------------------------
# bhs_fit() user-facing entry
# ---------------------------------------------------------------------------

test_that("bhs_fit: rejects non-data.frame `data` with hint", {
  e <- tryCatch(
    bhs_fit(list(y = 1), y ~ x, c("lon", "lat")),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "data.frame|`data` must be a data frame")
  expect_match(conditionMessage(e), "as.data.frame")
})

test_that("bhs_fit: rejects non-formula `formula` with hint", {
  e <- tryCatch(
    bhs_fit(data.frame(y = 1, x = 1, lon = 0, lat = 0),
              "y ~ x", c("lon", "lat")),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "must be a formula")
})

test_that("bhs_fit: rejects malformed coords with hint", {
  e <- tryCatch(
    bhs_fit(data.frame(y = 1, x = 1, lon = 0, lat = 0),
              y ~ x, c("only_one")),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "length-2 character")
})

test_that("bhs_fit: missing coord columns flagged by name", {
  e <- tryCatch(
    bhs_fit(data.frame(y = 1, x = 1, easting = 0, northing = 0),
              y ~ x, c("lon", "lat")),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "lon|lat")
})

# ---------------------------------------------------------------------------
# gnn_build_graph() user-facing entry
# ---------------------------------------------------------------------------

test_that("gnn_build_graph: missing lon/lat lists which", {
  e <- tryCatch(
    gnn_build_graph(data.frame(x = 1:3, y = 1:3, z = 1:3), k = 2L),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "missing coordinate column")
  expect_match(conditionMessage(e), "lon|lat")
})

test_that("gnn_build_graph: rejects non-data.frame", {
  e <- tryCatch(
    gnn_build_graph(matrix(1:6, 3, 2), k = 2L),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "data frame|matrix")
})

test_that("gnn_build_graph: rejects k <= 0", {
  e <- tryCatch(
    gnn_build_graph(data.frame(lon = 1:3, lat = 1:3, x = 1:3), k = 0L),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "positive integer|`k`")
})

# ---------------------------------------------------------------------------
# dm_fit() user-facing entry
# ---------------------------------------------------------------------------

test_that("dm_fit: rejects non-3D stack with helpful message", {
  e <- tryCatch(
    dm_fit(matrix(stats::rnorm(20), 4L, 5L)),
    error = function(e) e
  )
  expect_match(conditionMessage(e),
                 "3-D array|3D array|n_patches, H, W")
})

test_that("dm_fit: rejects non-matrix conditioning", {
  patches <- array(stats::rnorm(8 * 4 * 4), dim = c(8L, 4L, 4L))
  e <- tryCatch(
    dm_fit(patches, conditioning = c(1, 2, 3),
             T = 5L, epochs = 2L, hidden = 4L, seed = 1L),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "matrix|as.matrix")
})

test_that("dm_fit: cond row count mismatch produces actionable error", {
  patches <- array(stats::rnorm(8 * 4 * 4), dim = c(8L, 4L, 4L))
  bad_cond <- matrix(stats::rnorm(15), 5L, 3L)
  e <- tryCatch(
    dm_fit(patches, conditioning = bad_cond,
             T = 5L, epochs = 2L, hidden = 4L, seed = 1L),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "one row per patch|n=8")
})

# ---------------------------------------------------------------------------
# no_deeponet_fit() user-facing entry
# ---------------------------------------------------------------------------

test_that("no_deeponet_fit: rejects non-matrix targets with hint", {
  e <- tryCatch(
    no_deeponet_fit(c(5, 10), c(1, 2, 3),
                       matrix(stats::rnorm(4), 2L, 2L)),
    error = function(e) e
  )
  expect_match(conditionMessage(e), "targets|matrix")
})

test_that("no_deeponet_fit: depths/targets dimension mismatch", {
  e <- tryCatch(
    no_deeponet_fit(c(5, 10),
                       matrix(stats::rnorm(6), 2L, 3L),
                       matrix(stats::rnorm(4), 2L, 2L)),
    error = function(e) e
  )
  expect_match(conditionMessage(e),
                 "columns|disagree|3 entries|3 columns")
})

# ---------------------------------------------------------------------------
# Entry points that used to answer a mistake with raw stopifnot() text
# ("nrow(X) == length(y) is not TRUE"), or with a mislabelled message.
# Each message must name the function, the argument and what was wrong.
# ---------------------------------------------------------------------------

test_that("quantum_krr_fit: names the argument and the mismatch", {
  X <- matrix(stats::runif(20), 10L); y <- stats::rnorm(10L)
  expect_error(quantum_krr_fit(X, y[1:5]),
               "\\[quantum_krr_fit\\] `X` has 10 rows but `y` has 5 values")
  expect_error(quantum_krr_fit(X, y, lambda = -1),
               "`lambda` must be a single positive number, got -1")
  X2 <- X; X2[1] <- NA
  expect_error(quantum_krr_fit(X2, y), "must be finite.*Hint")
  # A character column used to be coerced to NA with only a warning.
  expect_error(quantum_krr_fit(data.frame(a = letters[1:10]), y),
               "`X` must be a numeric matrix.*character")
})

test_that("piml_profile_fit: names the argument and the problem", {
  expect_error(piml_profile_fit(c(5, 15, 30), c(20, 12)),
               "\\[piml_profile_fit\\] `depths` has 3 values but `values` has 2")
  expect_error(piml_profile_fit(c(-5, 15, 30), c(20, 12, 8)),
               "depths must be >= 0.*got -5")
  expect_error(piml_profile_fit(c(5, 15, 30), c(20, NA, 8)),
               "must be finite.*Hint")
  expect_error(piml_profile_fit(c("5", "15", "30"), c(20, 12, 8)),
               "`depths` must be numeric, got character")
})

test_that("causal_estimate_effect: an unknown exposure is called an exposure", {
  skip_if_not_installed("dagitty")
  data(br_cerrado, package = "edaphos", envir = environment())
  # It used to say "Covariates not found in data: nope".
  expect_error(causal_estimate_effect(br_cerrado, causal_cerrado_dag(),
                                      exposure = "nope", outcome = "soc"),
               "exposure `nope` is not a column of `data`")
  expect_error(causal_estimate_effect(br_cerrado, causal_cerrado_dag(),
                                      exposure = "map_mm", outcome = "carbon"),
               "outcome `carbon` is not a column of `data`")
  expect_error(causal_estimate_effect(as.list(1:3), causal_cerrado_dag(),
                                      exposure = "map_mm", outcome = "soc"),
               "`data` must be a data frame, got list")
})

test_that("temporal_convlstm_fit: a wrongly shaped sequence says which shape", {
  skip_if_no_torch()
  expect_error(temporal_convlstm_fit(array(0, c(2, 2)), array(0, c(1, 4, 4))),
               "5 dimensions.*got 2.*temporal_cube_to_tensor")
})
