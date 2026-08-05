## Pillar 2: the closed form, the asymptote, and the horizon operator.
##
## Three defects of the original implementation are pinned here.
##
## 1. `piml_profile_predict()` integrated the ODE numerically for every call.
##    The equation is separable and has an analytic solution, so the integrator
##    was strictly worse: slower and less accurate. These tests hold the closed
##    form to the integrator's own answer.
##
## 2. `y_inf` was reported and documented as "the deep asymptote". It is not.
##    The rate lambda(z) = lambda0 exp(-mu z) decays with depth, so the exponent
##    saturates and the profile only traverses 1 - exp(-kappa) of the y0 -> y_inf
##    gap. On the shipped pedon y_inf is -2.9 g/kg, an impossible negative
##    carbon, while the profile actually settles at +0.5.
##
## 3. Horizon values are layer averages; fitting a point evaluation at the
##    mid-depth is a mis-specified observation operator.

test_that("the closed form agrees with numerical integration of the ODE", {
  skip_if_not_installed("deSolve")
  # A decaying profile, an ascending one (argillic clay), and one with a
  # near-zero mu where the expm1 branch switches.
  cases <- list(
    list(lambda0 = 0.02915, mu = 0.01171, y_inf = -2.863, y0 = 37.16),
    list(lambda0 = 0.008,   mu = 0.03,    y_inf = 55,     y0 = 12),
    list(lambda0 = 0.02,    mu = 1e-9,    y_inf = 4,      y0 = 30)
  )
  z <- c(0, 5, 15, 25, 40, 60, 80, 100, 150, 200)
  for (p in cases) {
    cf <- edaphos:::.piml_solution(z, p)
    nu <- as.numeric(deSolve::ode(y = c(y = p$y0), times = z,
                                  func = edaphos:::.piml_dydz, parms = p,
                                  method = "lsoda")[, 2])
    expect_equal(cf, nu, tolerance = 1e-4)
  }
})

test_that("the mu -> 0 limit is the plain exponential, not a division by zero", {
  p <- list(lambda0 = 0.02, mu = 0, y_inf = 4, y0 = 30)
  z <- c(0, 10, 50, 100)
  expect_equal(edaphos:::.piml_solution(z, p),
               p$y_inf + (p$y0 - p$y_inf) * exp(-p$lambda0 * z))
  # and it is continuous across the branch cut
  p_eps <- p; p_eps$mu <- 1e-9
  expect_equal(edaphos:::.piml_solution(z, p_eps),
               edaphos:::.piml_solution(z, p), tolerance = 1e-7)
})

test_that("y_inf is not the asymptote, and .piml_asymptote is", {
  p <- list(lambda0 = 0.02915, mu = 0.01171, y_inf = -2.863, y0 = 37.16)
  a <- edaphos:::.piml_asymptote(p)
  # the limit of the solution, approached from very deep
  expect_equal(a, unname(edaphos:::.piml_solution(1e6, p)), tolerance = 1e-6)
  # and it is emphatically NOT y_inf: opposite sign on this pedon
  expect_gt(a, 0)
  expect_lt(p$y_inf, 0)
  expect_gt(abs(a - p$y_inf), 3)
  # the identity y(Inf) = y_inf + (y0 - y_inf) exp(-kappa)
  kappa <- p$lambda0 / p$mu
  expect_equal(a, p$y_inf + (p$y0 - p$y_inf) * exp(-kappa))
  # when the rate does NOT decay (mu <= 0) the profile does reach y_inf
  expect_equal(edaphos:::.piml_asymptote(list(lambda0 = 0.02, mu = 0,
                                              y_inf = 4, y0 = 30)), 4)
})

test_that("the Gauss-Legendre rule is exact on polynomials up to degree 2n-1", {
  gl <- edaphos:::.piml_gauss_legendre(8L)
  expect_equal(sum(gl$w), 2)                       # integral of 1 over [-1,1]
  expect_equal(sum(gl$w * gl$x), 0, tolerance = 1e-12)
  expect_equal(sum(gl$w * gl$x^2), 2 / 3)          # exact
  expect_equal(sum(gl$w * gl$x^14), 2 / 15)        # degree 14 = 2*8 - 2
})

test_that("the layer operator returns the depth-average, not the mid-point", {
  p <- list(lambda0 = 0.02915, mu = 0.01171, y_inf = -2.863, y0 = 37.16)
  zu <- c(0, 20, 50); zl <- c(20, 50, 100)
  lay <- edaphos:::.piml_layer_mean(zu, zl, p)
  # brute-force average on a fine grid
  brute <- vapply(seq_along(zu), function(i) {
    g <- seq(zu[i], zl[i], length.out = 20001)
    mean(edaphos:::.piml_solution(g, p))
  }, numeric(1))
  # the grid average is the cruder of the two; 1e-5 is its own accuracy
  expect_equal(lay, brute, tolerance = 1e-5)
  # The profile is convex, so the layer average sits ABOVE the mid-point value.
  mid <- edaphos:::.piml_solution((zu + zl) / 2, p)
  expect_true(all(lay > mid))
  # The bias follows the mid-point rule, f''(z_mid) * h^2 / 24: quadratic in
  # thickness at a FIXED depth, but governed by curvature, which collapses with
  # depth. So the correction is concentrated in the surface horizons, not the
  # deep ones -- it moves y0, not the asymptote.
  hh <- 1e-3
  curv <- (edaphos:::.piml_solution((zu + zl) / 2 + hh, p) -
             2 * mid +
             edaphos:::.piml_solution((zu + zl) / 2 - hh, p)) / hh^2
  # leading order only, so a few percent off on the thickest horizon
  expect_equal(lay - mid, curv * (zl - zu)^2 / 24, tolerance = 0.05)
  # thicker at the same depth => larger bias
  thick <- edaphos:::.piml_layer_mean(0, 50, p) - edaphos:::.piml_solution(25, p)
  thin  <- edaphos:::.piml_layer_mean(0, 10, p) - edaphos:::.piml_solution(5, p)
  expect_gt(thick, thin)
  # but a deep thick horizon is biased LESS than a shallow thin one
  deep_thick <- edaphos:::.piml_layer_mean(150, 200, p) -
    edaphos:::.piml_solution(175, p)
  expect_lt(deep_thick, thin)
})

test_that("fits stay in the physically admissible region", {
  # Real WoSIS-like profiles used to fit mu < 0 -- a decay rate that GROWS
  # exponentially with depth -- and negative surface carbon. The positive
  # parameterisation makes both unrepresentable.
  set.seed(11)
  cases <- list(
    list(z = c(5, 15, 30, 60, 100),  y = c(25, 18, 12, 8, 6.5)),
    list(z = c(10, 30, 60, 120),     y = c(8.1, 7.9, 7.6, 7.5)),   # nearly flat
    list(z = c(5, 20, 45, 90, 150),  y = c(41, 15, 6, 3.1, 2.6)),  # very steep
    list(z = c(15, 40, 80, 150),     y = c(120, 180, 240, 265))    # ascending
  )
  for (cs in cases) {
    f <- piml_profile_fit(cs$z, cs$y)
    expect_gt(f$params$lambda0, 0)
    expect_gt(f$params$mu, 0)
    expect_gt(f$params$y0, 0)
    expect_gt(edaphos:::.piml_asymptote(f$params), 0)
    expect_lt(f$rmse, 0.1 * diff(range(cs$y)))
  }
})

test_that("a non-positive observation is refused, not silently fitted", {
  expect_error(piml_profile_fit(c(5, 20, 50), c(25, 0, 7)), "positive")
  expect_error(piml_profile_fit(c(5, 20, 50), c(25, -3.4, 7)), "positive")
})

test_that("horizon boundaries change the fit and are echoed back", {
  z  <- c(5, 15, 30, 60, 100)
  zu <- c(0, 10, 20, 40, 80); zl <- c(10, 20, 40, 80, 120)
  y  <- c(25, 18, 12, 8, 6.5)
  f_pt  <- piml_profile_fit(z, y)
  f_lay <- piml_profile_fit(z, y, top = zu, bottom = zl)
  expect_null(f_pt$top)
  expect_equal(f_lay$top, zu)
  expect_equal(f_lay$bottom, zl)
  # the layer fit's residuals are against layer averages
  expect_equal(f_lay$fitted, edaphos:::.piml_layer_mean(zu, zl, f_lay$params))
  # and it is a genuinely different estimate
  expect_false(isTRUE(all.equal(f_pt$params$y0, f_lay$params$y0,
                                tolerance = 1e-3)))
  # malformed boundaries are an error, not a silent fallback
  expect_error(piml_profile_fit(z, y, top = zu), "bottom")
  expect_error(piml_profile_fit(z, y, top = zl, bottom = zu), "bottom > top")
})

test_that("the shipped pedon's attainable deep value is identified", {
  f <- system.file("extdata", "capstone_campaign_results.rds",
                   package = "edaphos")
  skip_if(f == "", "capstone bundle not installed")
  p <- readRDS(f)$piml_profile_obs
  skip_if(is.null(p), "pedon observations not in bundle")
  fit <- piml_profile_fit_bayesian(p$depth_mid, p$soc_g_kg,
                                   top = p$top, bottom = p$bottom,
                                   method = "laplace", seed = 7L)
  s <- summary(fit)
  ya <- s[s$parameter == "y_asym", ]
  yi <- s[s$parameter == "y_inf", ]
  # The attainable value is bounded away from zero...
  expect_gt(ya$q2.5, 0)
  # ...while y_inf, the coordinate this package used to report as the answer,
  # is not identified: its interval is several times wider and reaches into
  # impossible territory (negative carbon).
  expect_gt((yi$q97.5 - yi$q2.5) / (ya$q97.5 - ya$q2.5), 4)
  expect_lt(yi$q2.5, 0)
})

test_that("the shipped pedon is a real WoSIS profile, not typed-in numbers", {
  f <- system.file("extdata", "capstone_campaign_results.rds",
                   package = "edaphos")
  skip_if(f == "", "capstone bundle not installed")
  B <- readRDS(f)
  p <- B$piml_profile_obs
  skip_if(is.null(p), "pedon observations not in bundle")
  # It carries horizon boundaries, which a typed-in mid-depth vector did not.
  expect_true(all(c("top", "bottom", "depth_mid", "soc_g_kg") %in% names(p)))
  expect_true(all(p$bottom > p$top))
  # It is traceable to a profile in the shipped WoSIS extract.
  w <- system.file("extdata", "piml_wosis_cerrado.rds", package = "edaphos")
  skip_if(w == "", "WoSIS extract not installed")
  W <- readRDS(w)
  expect_true(!is.null(B$piml_profile_id))
  expect_true(B$piml_profile_id %in% W$profiles$profile_id)
  src <- W$horizons[W$horizons$profile_id == B$piml_profile_id, ]
  src <- src[order(src$top), ]
  expect_equal(p$soc_g_kg, src$soc_g_kg)
  expect_equal(p$top, src$top)
  # and it reaches well past the 100 cm of the pedon it replaced
  expect_gt(max(p$bottom), 300)
  expect_gte(nrow(p), 7L)
})

test_that("the physics gate never certifies a negative concentration", {
  # The envelope is widened by (safety_factor - 1) * span on each side, and
  # that widening -- not the choice of endpoint -- is what drove the floor
  # negative on 247 of 300 real WoSIS pedons, passing an SOC of -5 g/kg on 73
  # of them. The parametric branch is by construction a fit to a positive
  # property, so zero is a hard floor unless the caller overrides it.
  f <- system.file("extdata", "piml_wosis_cerrado.rds", package = "edaphos")
  skip_if(f == "", "WoSIS extract not installed")
  D <- readRDS(f)
  set.seed(3)
  pids <- sample(unique(D$horizons$profile_id), 40)
  for (pid in pids) {
    h <- D$horizons[D$horizons$profile_id == pid, ]
    fit <- tryCatch(piml_profile_fit(h$depth_mid, h$soc_g_kg,
                                     top = h$top, bottom = h$bottom),
                    error = function(e) NULL)
    if (is.null(fit)) next
    g <- al_physics_gate_piml(fit, safety_factor = 1.2)
    expect_false(g(NULL, -1e-6))
    expect_false(g(NULL, -5))
  }
  # `lower` clamps INWARDS only, by documented design: it can raise the floor
  # but never widen the envelope downwards. So the zero floor cannot be undone
  # by passing a negative `lower`, and a positive one still bites.
  fit <- piml_profile_fit(c(5, 20, 50), c(25, 14, 7))
  expect_false(al_physics_gate_piml(fit, 1.2, lower = -100)(NULL, -5))
  expect_false(al_physics_gate_piml(fit, 1.2, lower = 10)(NULL, 5))
  expect_true(al_physics_gate_piml(fit, 1.2, lower = 10)(NULL, 15))
})

test_that("piml_prior_literature is independent of the data it is used on", {
  a <- piml_prior_literature()
  b <- piml_prior_literature()
  expect_identical(a, b)
  # None of its fields may be a function of any response: constructing it
  # takes no data at all.
  expect_true(all(vapply(a, is.numeric, TRUE)))
  expect_true(all(is.finite(unlist(a))))
  # It has the same shape the sampler expects.
  d <- edaphos:::.piml_bayes_default_prior(c(5, 20, 50), c(25, 14, 7), NULL)
  expect_setequal(names(a), names(d))
})

test_that("causal_dag_test falsifies the shipped graph on both tests", {
  skip_if_not_installed("dagitty")
  f <- system.file("extdata", "causal_cerrado_real_v2.rds", package = "edaphos")
  skip_if(f == "", "causal bundle not installed")
  d <- readRDS(f)$profiles
  d$soc_topsoil_gkg <- d$soc; d$wc_bio_01 <- d$mat; d$wc_bio_12 <- d$map
  d$wc_landcover_trees <- d$trees; d$soilgrids_clay <- d$clay
  d$soilgrids_sand <- d$sand; d$soilgrids_bdod <- d$bdod

  tst <- causal_dag_test(causal_cerrado_real_dag(), d)
  expect_s3_class(tst, "edaphos_dag_test")
  expect_gt(tst$n_tests, 30)
  # The graph fails its own test. This is the paper's negative result, and it
  # is pinned so that a change to the graph or the bundle cannot quietly turn
  # a falsified graph into a passing one.
  expect_gt(tst$n_rejected / tst$n_tests, 0.5)
  expect_gt(tst$max_abs_r, 0.5)
  # Nodes with no data column are reported, not silently dropped.
  expect_true(length(tst$nodes_without_data) > 0)
  expect_false(any(tst$nodes_without_data %in% names(d)))

  # The spatial variant must be genuinely different, and less severe: pooling
  # spatially autocorrelated profiles overstates the effective sample size.
  skip_if_not_installed("mgcv")
  tsp <- causal_dag_test(causal_cerrado_real_dag(), d, coords = c("lon", "lat"))
  expect_false(is.na(tsp$n_rejected_spatial))
  expect_lt(tsp$n_rejected_spatial, tsp$n_rejected)
  # but the graph still fails
  expect_gt(tsp$n_rejected_spatial / tsp$n_tests, 0.5)
})
