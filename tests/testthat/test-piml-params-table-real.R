## The shipped Pillar-2 parameter table must come from a real posterior.
##
## It previously did not. data-raw/capstone_campaign_run.R called coef() on an
## `edaphos_piml_bayes` object; no such method exists, so coef() returned NULL,
## a tryCatch fallback substituted three hard-coded constants, and the table's
## "confidence intervals" were the mean multiplied by 0.75 and 1.25 (0.80/1.20
## for the last row). The parameter NAMES were wrong too -- k1, k2 and sigma are
## not parameters of dy/dz = -lambda0 * exp(-mu*z) * (y - y_inf).
##
## These tests pin the three properties that distinguish a real posterior
## summary from a fabricated one.

test_that("the shipped PIML parameter table names the model's actual parameters", {
  f <- system.file("extdata", "capstone_campaign_results.rds", package = "edaphos")
  skip_if(f == "", "capstone bundle not installed")
  tab <- readRDS(f)$piml_params_table
  expect_s3_class(tab, "data.frame")
  expect_setequal(tab$param,
                  c("lambda0", "mu", "y_inf", "y0", "kappa", "y_asym"))
  # y_inf must not be advertised as the deep asymptote: the profile never
  # reaches it. The attainable value is y_asym, and on this pedon the two
  # differ in sign.
  expect_false(grepl("asymptote", tab$meaning[tab$param == "y_inf"],
                     ignore.case = TRUE))
  expect_lt(tab$mean[tab$param == "y_inf"], 0)
  expect_gt(tab$mean[tab$param == "y_asym"], 0)
  # and the attainable value must be identified: strictly positive interval.
  expect_gt(tab$ci_lo[tab$param == "y_asym"], 0)
  # the fabricated version named parameters the ODE does not have
  expect_false(any(c("k1", "k2", "sigma") %in% tab$param))
  expect_true(all(c("mean", "ci_lo", "ci_hi") %in% names(tab)))
})

test_that("its intervals are posterior quantiles, not the mean times a constant", {
  f <- system.file("extdata", "capstone_campaign_results.rds", package = "edaphos")
  skip_if(f == "", "capstone bundle not installed")
  tab <- readRDS(f)$piml_params_table

  expect_true(all(tab$ci_lo <= tab$mean), info = "lower bound above the mean")
  expect_true(all(tab$ci_hi >= tab$mean), info = "upper bound below the mean")

  # The tell-tale of the fabricated table: ci/mean identical on every row.
  # A real posterior gives a different relative width per parameter, because
  # the parameters are not equally well identified.
  r_lo <- tab$ci_lo / tab$mean
  expect_gt(stats::sd(r_lo), 0.01)
  expect_false(isTRUE(all.equal(r_lo, rep(0.75, length(r_lo)), tolerance = 1e-6)))
})

test_that("the table reproduces a live Laplace fit of the shipped pedon", {
  f <- system.file("extdata", "capstone_campaign_results.rds", package = "edaphos")
  skip_if(f == "", "capstone bundle not installed")
  B <- readRDS(f)
  p <- B$piml_profile_obs
  skip_if(is.null(p), "pedon observations not in bundle")

  fit <- piml_profile_fit_bayesian(p$depth_mid, p$soc_g_kg,
                                   method = "laplace", seed = 7L)
  s <- summary(fit)
  tab <- B$piml_params_table[match(s$parameter, B$piml_params_table$param), ]

  expect_equal(tab$mean,  s$mean,  tolerance = 1e-6)
  expect_equal(tab$ci_lo, s$q2.5,  tolerance = 1e-6)
  expect_equal(tab$ci_hi, s$q97.5, tolerance = 1e-6)
})

test_that("print.edaphos_causal_effect names the estimand it was asked for", {
  skip_if_not_installed("dagitty")
  set.seed(1)
  n <- 200
  d <- data.frame(z = stats::rnorm(n))
  d$x <- 0.7 * d$z + stats::rnorm(n)
  d$y <- 0.5 * d$x + 0.9 * d$z + stats::rnorm(n)
  dag <- dagitty::dagitty("dag{ z -> x  z -> y  x -> y }")

  tot <- causal_estimate_effect(d, dag, "x", "y", effect = "total")
  dir <- causal_estimate_effect(d, dag, "x", "y", effect = "direct")
  expect_identical(tot$effect_type, "total")
  expect_identical(dir$effect_type, "direct")

  expect_match(paste(utils::capture.output(print(tot)), collapse = " "),
               "total effect")
  expect_match(paste(utils::capture.output(print(dir)), collapse = " "),
               "direct effect")

  # An object from before effect_type existed must not be labelled either way.
  legacy <- tot; legacy$effect_type <- NULL
  expect_match(paste(utils::capture.output(print(legacy)), collapse = " "),
               "adjusted effect")
})
