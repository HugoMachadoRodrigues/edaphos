# ---------------------------------------------------------------------------
# The pseudo-inverse fallback must not depend on an unchecked Suggests.
#
# Five call sites in R/causal_iv.R and R/causal_active_learning.R wrote
#   tryCatch(solve(M), error = function(e) MASS::ginv(M))
# with no requireNamespace() around the fallback. MASS is in Suggests, so it
# is not installed by default; it is also a "recommended" package, so it
# ships with virtually every R build and the calls work in practice. That is
# why five unguarded copies survived. On an R built
# --without-recommended-packages, a singular design produced "there is no
# package called 'MASS'" instead of a message naming the actual problem.
# ---------------------------------------------------------------------------

test_that(".safe_inverse matches solve() where solve() works", {
  set.seed(3)
  M <- crossprod(matrix(stats::rnorm(60), 20L, 3L))
  expect_equal(edaphos:::.safe_inverse(M), solve(M))
})

test_that(".safe_inverse falls back to a pseudo-inverse on a singular matrix", {
  skip_if_not_installed("MASS")
  # Column 2 is exactly twice column 1, so the cross-product is singular by
  # construction and solve() must fail.
  X <- cbind(1:8, 2 * (1:8), stats::rnorm(8))
  M <- crossprod(X)
  expect_error(solve(M))
  inv <- edaphos:::.safe_inverse(M)
  expect_equal(inv, MASS::ginv(M))
  # A pseudo-inverse satisfies M %*% M+ %*% M == M, which is the property
  # that makes it usable here; asserting only its dimensions would pass
  # against almost any wrong answer.
  expect_equal(M %*% inv %*% M, M, tolerance = 1e-6)
})

test_that("a singular matrix without MASS gives an actionable error", {
  # Simulate MASS being absent. The message must name the singularity AND
  # the package, because "there is no package called 'MASS'" tells a user
  # neither what went wrong nor that their design is rank-deficient.
  X <- cbind(1:8, 2 * (1:8), stats::rnorm(8))
  M <- crossprod(X)
  testthat::local_mocked_bindings(
    requireNamespace = function(package, ...) {
      if (identical(package, "MASS")) FALSE else base::requireNamespace(package, ...)
    },
    .package = "base"
  )
  err <- tryCatch(edaphos:::.safe_inverse(M, "test design"), error = function(e) e)
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "singular")
  expect_match(conditionMessage(err), "MASS")
  expect_match(conditionMessage(err), "test design", fixed = TRUE)
})
