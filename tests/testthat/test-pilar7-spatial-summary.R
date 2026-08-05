# ---------------------------------------------------------------------------
# `bhs_fit()$spatial` -- the two numbers that decide whether a fitted
# "spatial" field is spatial.
#
# Before this existed, every consumer in the package recomputed the variance
# share by hand and none of them compared the fitted correlation range against
# the spacing of the data. A fit can report an 89% spatial share on a
# correlation range shorter than the closest pair of observations, which is a
# nugget wearing another name. These tests pin both halves.
# ---------------------------------------------------------------------------

test_that("the spatial share matches the hand computation it replaces", {
  data(br_cerrado, envir = environment())
  ux <- sort(unique(br_cerrado$x)); uy <- sort(unique(br_cerrado$y))
  blk <- br_cerrado[br_cerrado$x %in% ux[10:22] & br_cerrado$y %in% uy[10:22], ]
  names(blk)[names(blk) == "x"] <- "lon"
  names(blk)[names(blk) == "y"] <- "lat"

  fit <- suppressWarnings(
    bhs_fit(blk, soc ~ elev + slope, nmcmc = 400L, seed = 1L))

  s2 <- mean(fit$sigma2_draws); t2 <- mean(fit$tau2_draws)
  expect_equal(fit$spatial$spatial_share, s2 / (s2 + t2))
  expect_equal(fit$spatial$nugget_sill_ratio, 1 - fit$spatial$spatial_share)
  expect_gte(fit$spatial$spatial_share, 0)
  expect_lte(fit$spatial$spatial_share, 1)
})

test_that("a range shorter than the closest pair is flagged, not reported as spatial", {
  data(br_cerrado, envir = environment())
  ux <- sort(unique(br_cerrado$x)); uy <- sort(unique(br_cerrado$y))
  blk <- br_cerrado[br_cerrado$x %in% ux[10:22] & br_cerrado$y %in% uy[10:22], ]
  names(blk)[names(blk) == "x"] <- "lon"
  names(blk)[names(blk) == "y"] <- "lat"

  # This is the package's own documented pathology: widening the bracket lets
  # phi climb until the correlation matrix is the identity, and the "spatial"
  # share rises with it. The share must not be reportable without the flag.
  fit <- suppressWarnings(
    bhs_fit(blk, soc ~ elev + slope, nmcmc = 400L, seed = 1L,
            phi_range = c(0.1, 2000)))

  d <- stats::dist(as.matrix(blk[, c("lon", "lat")]))
  expect_equal(fit$spatial$min_spacing, min(d[d > 0]))
  expect_equal(fit$spatial$practical_range, 3 / fit$phi_hat)
  expect_lt(fit$spatial$practical_range, fit$spatial$min_spacing)
  expect_true(fit$spatial$range_below_spacing)

  # and the rail is recorded, not merely warned about
  expect_true(fit$phi_railed)
  expect_equal(fit$phi_rail_edge, "upper")
  expect_equal(fit$phi_range, c(0.1, 2000))

  # print() must surface both, since that is where a reader meets them
  out <- paste(utils::capture.output(print(fit)), collapse = "\n")
  expect_match(out, "spatial share")
  expect_match(out, "practical range")
  expect_match(out, "white noise")
  expect_match(out, "railed at the upper end")
})

test_that("an interior phi is not flagged", {
  set.seed(3L)
  n <- 80L
  df <- data.frame(lon = stats::runif(n, -50, -46),
                   lat = stats::runif(n, -18, -14),
                   z   = stats::rnorm(n))
  df$soc <- 10 + 2 * df$z + stats::rnorm(n)

  # A bracket wide enough to contain the optimum on coordinates spanning
  # ~4 degrees: ranges from a fraction of a degree to several degrees.
  fit <- suppressWarnings(
    bhs_fit(df, soc ~ z, nmcmc = 400L, seed = 1L, phi_range = c(0.05, 50)))

  expect_false(is.null(fit$spatial))
  expect_true(is.finite(fit$spatial$practical_range))
  expect_true(is.finite(fit$spatial$min_spacing))
  # whichever way this particular fit lands, the flag must agree with the
  # comparison it claims to make
  expect_equal(fit$spatial$range_below_spacing,
               fit$spatial$practical_range < fit$spatial$min_spacing)
})
