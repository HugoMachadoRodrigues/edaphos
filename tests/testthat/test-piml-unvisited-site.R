# ---------------------------------------------------------------------------
# Table 11's claims, bound to piml_unvisited_site.rds.
#
# The manuscript says: at an unvisited site, covariates beat the population
# curve modestly; neighbours do not help and adding them to the covariates
# makes it worse; the site's own horizons are several times better than any
# prediction without them. Each sentence fails here if the bundle stops
# supporting it.
# ---------------------------------------------------------------------------

uv <- function() {
  p <- system.file("extdata", "piml_unvisited_site.rds", package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata", "piml_unvisited_site.rds")
  skip_if_not(file.exists(p), "piml_unvisited_site.rds not built")
  readRDS(p)
}
row <- function(t, m) t[t$method == m, ]

test_that("covariates beat the population curve, modestly", {
  t <- uv()$table
  cv <- row(t, "covariates"); pop <- row(t, "population")
  expect_lt(cv$mae_log, pop$mae_log)
  expect_lt(cv$p_vs_population, 0.05)
  expect_gt(cv$wins_vs_population, cv$n / 2)
  # "only modestly": under a fifth of the error removed
  expect_gt(cv$mae_log / pop$mae_log, 0.8)
})

test_that("neighbours do not help, alone or added to covariates", {
  t <- uv()$table
  pop <- row(t, "population")
  expect_gt(row(t, "nearest")$mae_log, pop$mae_log)
  expect_gt(row(t, "knn10")$mae_log, pop$mae_log)
  expect_gt(row(t, "cov+knn")$mae_log, row(t, "covariates")$mae_log)
})

test_that("held-out profiles are never closer than the buffer", {
  u <- uv()
  expect_gte(unname(u$d_nearest_km[1]), u$buffer_km)
})

test_that("the site's own horizons are several times better", {
  u <- uv()
  expect_gt(row(u$table, "covariates")$mae_log / u$reference$mae_log, 3)
})
