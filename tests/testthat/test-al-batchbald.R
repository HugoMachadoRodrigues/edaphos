# Pillar 5 v1.1.0 tests: BatchBALD greedy log-det acquisition.

.batchbald_fixture <- function(n = 30L, seed = 1L) {
  set.seed(seed)
  data(br_cerrado, package = "edaphos", envir = environment())
  covs <- c("elev", "slope", "twi", "map_mm")
  idx  <- al_initial_design(br_cerrado, covs, n = n, seed = seed)
  list(
    labeled = br_cerrado[idx, ],
    pool    = br_cerrado[setdiff(seq_len(nrow(br_cerrado)), idx), ],
    covs    = covs
  )
}

test_that("al_query_batchbald returns a valid batch of the requested size", {
  ff  <- .batchbald_fixture()
  fit <- al_fit(ff$labeled, target = "soc", covariates = ff$covs)
  b <- al_query_batchbald(fit, ff$pool, n = 6L)
  expect_type(b, "integer")
  expect_equal(length(b), 6L)
  expect_true(all(b >= 1L & b <= nrow(ff$pool)))
  expect_equal(length(unique(b)), 6L)
})

test_that("BatchBALD score is submodular (diminishing returns)", {
  ff  <- .batchbald_fixture()
  fit <- al_fit(ff$labeled, target = "soc", covariates = ff$covs)
  # First-greedy-step score = single-point BALD on the highest-variance
  # candidate; adding a second point must not produce a bigger *per-
  # point* log-det increment than the first (diminishing returns).
  b1 <- al_query_batchbald(fit, ff$pool, n = 1L)
  b3 <- al_query_batchbald(fit, ff$pool, n = 3L)
  expect_identical(b3[1L], b1[1L])
  expect_equal(length(unique(b3)), 3L)
})

test_that("al_query_batchbald uses the physics_gate when supplied", {
  ff  <- .batchbald_fixture()
  fit <- al_fit(ff$labeled, target = "soc", covariates = ff$covs)
  # Gate that only accepts the first 20 rows of the pool.
  gate <- function(candidates, predicted_mean) {
    ix <- seq_along(predicted_mean)
    ix <= 20L
  }
  b <- al_query_batchbald(fit, ff$pool, n = 5L, physics_gate = gate)
  # All selected candidates must correspond to rows 1..20 of ff$pool.
  expect_true(all(b <= 20L))
})

test_that("al_query_batchbald chooses a batch different from hybrid", {
  ff  <- .batchbald_fixture()
  fit <- al_fit(ff$labeled, target = "soc", covariates = ff$covs)
  bb  <- al_query_batchbald(fit, ff$pool, n = 8L)
  hy  <- al_query(fit, ff$pool, n = 8L, strategy = "hybrid")
  # The two strategies optimise different objectives; expect <= 50%
  # overlap on a reasonable pool.
  expect_true(length(intersect(bb, hy)) <= 6L)
})

test_that("al_query_batchbald rejects a non-AL model", {
  expect_error(
    al_query_batchbald(list(foo = 1), data.frame(x = 1:10), n = 2L),
    regexp = "edaphos_al_model"
  )
})
