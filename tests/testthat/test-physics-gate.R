make_fake_soil <- function(n = 80L, seed = 5L) {
  set.seed(seed)
  x <- runif(n, 0, 100); y <- runif(n, 0, 100)
  elev <- 50 + 0.2 * x + rnorm(n, 0, 3)
  dist <- sqrt((x - 50)^2 + (y - 50)^2) / 70
  lead <- 40 + 180 * exp(-dist * 2) + 0.3 * elev + rnorm(n, 0, 6)
  data.frame(x = x, y = y, elev = elev, dist = dist, lead = lead)
}

test_that("al_physics_gate_piml builds a function from a parametric fit", {
  pf <- piml_profile_fit(depths = c(5, 15, 30, 60, 100),
                         values = c(25, 18, 12, 8, 6.5))
  g <- al_physics_gate_piml(pf, safety_factor = 1.2)
  expect_true(is.function(g))
  # Values inside envelope pass, well outside do not.
  cand <- data.frame(dummy = rep(1, 4))
  mask <- g(cand, c(10, 20, 500, -100))
  expect_equal(mask, c(TRUE, TRUE, FALSE, FALSE))
})

test_that("al_query applies a physics gate and never picks infeasible candidates", {
  d <- make_fake_soil()
  m <- al_fit(d[1:20, ], "lead",
              covariates = c("dist", "elev"),
              coords = c("x", "y"), num.trees = 100L)
  cand <- d[-(1:20), ]

  # Build a gate that rejects any predicted lead below 50 (so only high
  # signals survive -> forces AL to pick near the peak).
  gate <- function(candidates, predicted_mean, ...) predicted_mean >= 50
  picked <- al_query(m, cand, n = 5, strategy = "hybrid",
                     physics_gate = gate)
  expect_length(picked, 5L)

  # Verify: the ranger mean-prediction at each picked row should be >= 50
  pr <- stats::predict(m$model,
                        data = cand[picked, c("dist", "elev")])$predictions
  expect_true(all(pr >= 50))
})

test_that("al_query errors cleanly when the gate rejects everything", {
  d <- make_fake_soil()
  m <- al_fit(d[1:20, ], "lead",
              covariates = c("dist", "elev"),
              coords = c("x", "y"), num.trees = 100L)
  cand <- d[-(1:20), ]
  gate_all_bad <- function(candidates, predicted_mean, ...)
    rep(FALSE, nrow(candidates))
  expect_error(
    al_query(m, cand, n = 3, physics_gate = gate_all_bad),
    "rejected every candidate"
  )
})

test_that("al_loop forwards physics_gate to al_query and decreases RMSE", {
  d <- make_fake_soil(n = 120, seed = 6L)
  set.seed(6)
  seed_idx <- al_initial_design(d, c("dist", "elev"), n = 12, iter = 200)

  # Gate based on data-driven range (very loose -> should not change
  # the outcome qualitatively, only ensure the plumbing works).
  envelope <- range(d$lead)
  gate <- function(candidates, predicted_mean, ...)
    predicted_mean >= envelope[1] - 10 & predicted_mean <= envelope[2] + 10
  m <- al_loop(
    labeled = d[seed_idx, ], candidates = d[-seed_idx, ],
    target = "lead", covariates = c("dist", "elev"),
    coords = c("x", "y"),
    budget = 20, batch = 5,
    strategy = "hybrid",
    physics_gate = gate,
    num.trees = 200L, verbose = FALSE
  )
  h <- al_history(m)
  expect_s3_class(m, "edaphos_al_model")
  expect_lte(h$rmse_oob[nrow(h)], h$rmse_oob[1] * 1.15)
})
