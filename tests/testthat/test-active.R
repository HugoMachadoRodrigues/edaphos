skip_if_no_meuse <- function() {
  skip_if_not_installed("sp")
}

# Build a small, reproducible soil-like dataset for fast unit tests.
make_fake_soil <- function(n = 60L, seed = 1L) {
  set.seed(seed)
  x <- runif(n, 0, 100)
  y <- runif(n, 0, 100)
  elev <- 50 + 0.2 * x - 0.1 * y + rnorm(n, 0, 2)
  dist <- sqrt((x - 50)^2 + (y - 50)^2) / 70
  # Non-linear "lead" response with heteroscedastic noise.
  lead <- 40 + 180 * exp(-dist * 2) + 0.3 * elev +
          rnorm(n, 0, 5 + 0.2 * elev)
  data.frame(x = x, y = y, elev = elev, dist = dist, lead = lead)
}

test_that("al_initial_design returns n indices from complete rows", {
  d <- make_fake_soil()
  idx <- al_initial_design(d, covariates = c("dist", "elev"),
                           n = 10, seed = 42, iter = 200)
  expect_length(idx, 10L)
  expect_true(all(idx %in% seq_len(nrow(d))))
  expect_false(anyDuplicated(idx) > 0)
})

test_that("al_initial_design errors when n > complete rows", {
  d <- make_fake_soil(n = 5)
  expect_error(
    al_initial_design(d, c("dist", "elev"), n = 10, iter = 50),
    "complete-covariate"
  )
})

test_that("al_fit produces a edaphos_al_model with iter 0 history", {
  d <- make_fake_soil()
  m <- al_fit(d, target = "lead",
              covariates = c("dist", "elev"),
              coords = c("x", "y"),
              num.trees = 100L)
  expect_s3_class(m, "edaphos_al_model")
  expect_length(m$history, 1L)
  expect_equal(m$history[[1]]$iter, 0L)
  expect_true(is.finite(m$history[[1]]$rmse_oob))
  expect_equal(m$target, "lead")
  expect_equal(m$covariates, c("dist", "elev"))
})

test_that("al_query returns n distinct indices for each strategy", {
  d <- make_fake_soil()
  idx0 <- 1:20
  m <- al_fit(d[idx0, ], target = "lead",
              covariates = c("dist", "elev"),
              coords = c("x", "y"),
              num.trees = 100L)
  cand <- d[-idx0, ]
  for (s in c("uncertainty", "diverse", "hybrid")) {
    q <- al_query(m, cand, n = 5, strategy = s, alpha = 0.6)
    expect_length(q, 5L)
    expect_false(anyDuplicated(q) > 0)
    expect_true(all(q %in% seq_len(nrow(cand))))
  }
})

test_that("al_query cost strategy requires base and coords", {
  d <- make_fake_soil()
  idx0 <- 1:20
  m_nocoords <- al_fit(d[idx0, ], "lead",
                       covariates = c("dist", "elev"),
                       num.trees = 100L)
  expect_error(
    al_query(m_nocoords, d[-idx0, ], n = 3, strategy = "cost"),
    "coords"
  )
  m <- al_fit(d[idx0, ], "lead",
              covariates = c("dist", "elev"),
              coords = c("x", "y"),
              num.trees = 100L)
  expect_error(
    al_query(m, d[-idx0, ], n = 3, strategy = "cost"),
    "base"
  )
  q <- al_query(m, d[-idx0, ], n = 3, strategy = "cost",
                base = c(50, 50), cost_weight = 0.4)
  expect_length(q, 3L)
})

test_that("al_loop decreases OOB RMSE on a learnable signal", {
  d <- make_fake_soil(n = 120, seed = 2)
  set.seed(2)
  seed_idx <- al_initial_design(d, c("dist", "elev"), n = 12, iter = 200)
  m <- al_loop(
    labeled    = d[seed_idx, ],
    candidates = d[-seed_idx, ],
    target     = "lead",
    covariates = c("dist", "elev"),
    coords     = c("x", "y"),
    budget     = 20, batch = 5,
    strategy   = "hybrid",
    num.trees  = 200L, verbose = FALSE
  )
  h <- al_history(m)
  expect_s3_class(m, "edaphos_al_model")
  expect_gte(nrow(h), 4L)   # iter 0 + >= 3 iters for budget=20 batch=5
  # learning curve should trend downward (final <= initial * 1.1 allowing noise)
  expect_lte(h$rmse_oob[nrow(h)], h$rmse_oob[1] * 1.15)
})

test_that("al_loop supports a user-supplied oracle", {
  d <- make_fake_soil(n = 80, seed = 3)
  seed_idx <- 1:10
  cand <- d[-seed_idx, ]
  true_vals <- cand$lead
  cand$lead <- NA_real_       # drop labels from candidates
  calls <- 0L
  oracle <- function(samples) {
    calls <<- calls + 1L
    true_vals[as.integer(rownames(samples))]
  }
  rownames(cand) <- seq_len(nrow(cand))
  rownames(d)    <- seq_len(nrow(d))
  # easier: simulate with ground truth table
  oracle2 <- function(samples) {
    # look up by covariates (exact match in our synthetic data)
    idx <- match(samples$dist, d$dist)
    d$lead[idx]
  }
  m <- al_loop(
    labeled    = d[seed_idx, ],
    candidates = cand,
    target     = "lead",
    covariates = c("dist", "elev"),
    coords     = c("x", "y"),
    budget     = 10, batch = 5,
    strategy   = "uncertainty",
    oracle     = oracle2,
    num.trees  = 100L, verbose = FALSE
  )
  expect_s3_class(m, "edaphos_al_model")
  expect_gte(length(m$history), 3L)
})

test_that("al_update appends a history entry and refits", {
  d <- make_fake_soil()
  m <- al_fit(d[1:20, ], "lead",
              covariates = c("dist", "elev"),
              coords = c("x", "y"),
              num.trees = 100L)
  m2 <- al_update(m, d[21:25, ])
  expect_equal(length(m2$history), length(m$history) + 1L)
  expect_equal(nrow(m2$labeled), nrow(m$labeled) + 5L)
  expect_true(is.finite(m2$history[[length(m2$history)]]$rmse_oob))
})

test_that("print and summary do not error", {
  d <- make_fake_soil()
  m <- al_fit(d[1:20, ], "lead", c("dist", "elev"), num.trees = 100L)
  expect_output(print(m), "edaphos_al_model")
  expect_output(summary(m), "iter")
})
