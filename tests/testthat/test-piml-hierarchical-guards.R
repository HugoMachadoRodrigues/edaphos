# ---------------------------------------------------------------------------
# Two guards on the hierarchical Neural ODE.
#
# This model marches its state by RK4 over an UNCONSTRAINED network, so
# nothing in it prevents a strictly positive property from being predicted
# negative -- and its own documented example did exactly that, returning
# -2.56 g/kg at 60 cm and -10.46 at 200 cm. Its physics gate then built an
# acceptance envelope entirely from those same predictions, with no reference
# to any measured value, so a fit that came out low rejected candidates the
# training data call ordinary: 6 of 8 on that example, every one of them
# inside the observed range of the response.
#
# Neither is fixed by making the network better. They are fixed by refusing to
# return impossible numbers silently, and by anchoring the gate to data.
# ---------------------------------------------------------------------------


fit_small <- function(epochs = 40L) {
  data(br_cerrado, envir = environment())
  set.seed(1L)
  sub <- br_cerrado[sample(nrow(br_cerrado), 5L), ]
  zs <- c(5, 15, 30, 60)
  rows <- do.call(rbind, lapply(seq_len(nrow(sub)), function(i) {
    y0 <- sub$soc[i]; l0 <- 0.02 + 0.004 * sub$twi[i]; mu <- 0.02
    yi <- 0.3 * y0
    data.frame(id = i, depth = zs,
               soc = yi + (y0 - yi) * exp(-(l0 / mu) * (1 - exp(-mu * zs))),
               twi = sub$twi[i], elev = sub$elev[i])
  }))
  list(fit = piml_hierarchical_fit(rows, "id", "depth", "soc",
                                   c("twi", "elev"), epochs = epochs,
                                   seed = 1L, verbose = FALSE),
       covs = rows[!duplicated(rows$id), c("twi", "elev")])
}

test_that("the fit records the observed range, which both guards need", {
  skip_if_no_torch()
  s <- fit_small()
  expect_true(all(c("value_range", "value_positive") %in% names(s$fit)))
  expect_length(s$fit$value_range, 2L)
  expect_lt(s$fit$value_range[1], s$fit$value_range[2])
  expect_true(s$fit$value_positive)
})

test_that("a negative prediction is clamped AND announced, not silently returned", {
  skip_if_no_torch()
  s <- fit_small()
  # Far past the deepest training horizon (60 cm), where an unconstrained
  # vector field has nothing holding it above zero.
  deep <- c(60, 400, 800)

  expect_warning(
    raw <- piml_hierarchical_predict(s$fit, s$covs, deep, clamp = FALSE),
    "are negative")
  expect_true(any(raw < 0))

  expect_warning(
    cl <- piml_hierarchical_predict(s$fit, s$covs, deep, clamp = TRUE),
    "were negative")
  expect_false(any(cl < 0))
  # the clamp must only touch the offending entries
  ok <- raw >= 0
  expect_equal(cl[ok], raw[ok])

  # the warning has to carry the size of the problem, or it is not a warning
  w <- tryCatch(piml_hierarchical_predict(s$fit, s$covs, deep),
                warning = function(w) conditionMessage(w))
  expect_match(w, "worst")
  expect_match(w, "no positivity constraint")
})

test_that("the gate rejects the impossible and keeps what the data call ordinary", {
  skip_if_no_torch()
  s <- fit_small()
  g <- al_physics_gate_piml_hierarchical(s$fit)
  rng <- s$fit$value_range

  # Impossible: negative carbon must never pass, whatever the network says.
  expect_false(suppressWarnings(g(s$covs[1, , drop = FALSE], -5)))

  # Ordinary: a value sitting inside the observed range must pass, even when
  # this small fit's own predicted envelope is narrower than that range. This
  # is the half that was broken.
  mid <- mean(rng)
  expect_true(all(suppressWarnings(g(s$covs, rep(mid, nrow(s$covs))))))

  # And the envelope is genuinely at least the observed range
  just_inside <- rng[2] - 1e-6 * diff(rng)
  expect_true(all(suppressWarnings(g(s$covs, rep(just_inside, nrow(s$covs))))))

  # Far outside it, rejection is still possible -- the gate has not been
  # widened into uselessness.
  expect_false(all(suppressWarnings(
    g(s$covs, rep(rng[2] * 10, nrow(s$covs))))))
})
