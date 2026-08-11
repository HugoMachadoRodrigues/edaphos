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
                  c("lambda0", "mu", "y_inf", "y0", "kappa", "y_asym", "sigma"))
  # y_inf must not be advertised as the deep asymptote: the profile never
  # reaches it.
  expect_false(grepl("asymptote", tab$meaning[tab$param == "y_inf"],
                     ignore.case = TRUE))
  # The attainable value is identified and strictly positive...
  expect_gt(tab$mean[tab$param == "y_asym"], 0)
  expect_gt(tab$ci_lo[tab$param == "y_asym"], 0)
  # ...while y_inf is not: its interval reaches into impossible territory
  # (a negative carbon concentration).
  expect_lt(tab$ci_lo[tab$param == "y_inf"], 0)
  # the fabricated version named parameters the ODE does not have
  expect_false(any(c("k1", "k2") %in% tab$param))
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

test_that("the table reproduces a live fit of the shipped pedon, by the method it declares", {
  skip_on_cran()
  f <- system.file("extdata", "capstone_campaign_results.rds", package = "edaphos")
  skip_if(f == "", "capstone bundle not installed")
  B <- readRDS(f)
  p <- B$piml_profile_obs
  skip_if(is.null(p), "pedon observations not in bundle")

  # The bundle records which path produced it, and the refit must use that
  # path rather than a hard-coded one. This test caught the switch from
  # Laplace to MCMC by failing on every row -- which is what it is for, but it
  # only works if the method is read from the bundle instead of pinned here.
  method <- B$piml_method %||% "laplace"
  expect_true(method %in% c("laplace", "mcmc"))

  # Horizon boundaries are part of the shipped pedon now that it is a real
  # WoSIS profile, and the bundle was built with the layer operator; refitting
  # without them would not reproduce it.
  fit <- piml_profile_fit_bayesian(p$depth_mid, p$soc_g_kg,
                                   top = p$top, bottom = p$bottom,
                                   method = method, seed = 7L)
  s <- summary(fit)
  tab <- B$piml_params_table[match(s$parameter, B$piml_params_table$param), ]

  expect_equal(tab$mean,  s$mean,  tolerance = 1e-6)
  expect_equal(tab$ci_lo, s$q2.5,  tolerance = 1e-6)
  expect_equal(tab$ci_hi, s$q97.5, tolerance = 1e-6)
})

test_that("the reported path is MCMC and carries its convergence diagnostics", {
  f <- system.file("extdata", "capstone_campaign_results.rds", package = "edaphos")
  skip_if(f == "", "capstone bundle not installed")
  B <- readRDS(f)
  skip_if(is.null(B$piml_params_table), "params table not in bundle")

  # Laplace was the reported path and it misrepresents this posterior: five of
  # seven intervals come out narrower, the observation noise by a factor of
  # 1.8. A regression to it would be silent without this.
  expect_equal(B$piml_method, "mcmc")
  expect_true(all(c("rhat", "ess") %in% names(B$piml_params_table)))
  # NO na.rm. I wrote these two lines with it, and on an all-NA column
  # max(..., na.rm = TRUE) is -Inf and min(..., na.rm = TRUE) is +Inf, so both
  # assertions passed vacuously on exactly the table they exist to police.
  expect_false(anyNA(B$piml_params_table$rhat))
  expect_false(anyNA(B$piml_params_table$ess))
  expect_true(all(is.finite(B$piml_params_table$rhat)))
  expect_lt(max(B$piml_params_table$rhat), 1.01)
  expect_gt(min(B$piml_params_table$ess), 400)
  expect_true(isTRUE(B$piml_converged))

  # and the comparison the manuscript reports has to be in the bundle,
  # because a claim that an approximation is too confident needs its evidence
  lc <- B$piml_laplace_vs_mcmc
  expect_false(is.null(lc))
  expect_true(all(c("width_ratio", "mean_mcmc", "mean_laplace") %in% names(lc)))
  expect_gt(sum(lc$width_ratio > 1.05), 3)
  # the identified quantity should be the one that does NOT move
  expect_lt(abs(lc$width_ratio[lc$parameter == "y_asym"] - 1), 0.1)
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
