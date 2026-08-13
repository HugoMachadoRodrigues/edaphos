# Predict depth profiles for new locations from covariates

Predict depth profiles for new locations from covariates

## Usage

``` r
piml_hierarchical_predict(object, new_covariates, newdepths, clamp = TRUE)
```

## Arguments

- object:

  A `edaphos_piml_hierarchical`.

- new_covariates:

  Data frame with at least the covariate columns used at training time
  (one row per location).

- newdepths:

  Numeric vector of depths.

- clamp:

  Logical, default `TRUE`. When the training response was strictly
  positive and the model returns negative predictions, clamp them to
  zero and warn. The model has **no structural positivity** – the state
  is integrated by RK4 over an unconstrained network – so a negative
  prediction means the fit has gone wrong, and the clamp is a guard
  against publishing impossible numbers rather than a repair. `FALSE`
  returns them unmodified, still with a warning.

## Value

Numeric matrix, one row per location in `new_covariates`, one column per
depth in `newdepths`.

## Examples

``` r
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {
  data(br_cerrado)
  # The five noise-free ODE pedons of ?piml_hierarchical_fit.
  sites <- br_cerrado[c(1, 400, 900, 1400, 1900), ]
  hz <- c(5, 15, 30, 60)
  pedons <- do.call(rbind, lapply(1:5, function(i) {
    y0   <- sites$soc[i]
    lam0 <- 0.02 + 0.004 * sites$twi[i]
    data.frame(pedon = paste0("P", i), depth = hz,
               soc = 0.30 * y0 + 0.70 * y0 *
                     exp(-(lam0 / 0.02) * (1 - exp(-0.02 * hz))),
               twi = sites$twi[i], ndvi = sites$ndvi[i],
               map_mm = sites$map_mm[i])
  }))

  # Hold pedon P4 out.  Its twi, ndvi and map_mm all sit INSIDE the
  # range of the four training pedons, so predicting it is
  # interpolation in covariate space, not extrapolation.
  train <- pedons[pedons$pedon != "P4", ]
  held  <- pedons[pedons$pedon == "P4", ]
  print(vapply(c("twi", "ndvi", "map_mm"), function(v)
    held[1L, v] > min(train[[v]]) && held[1L, v] < max(train[[v]]),
    TRUE))
  fit <- piml_hierarchical_fit(
    train, "pedon", "depth", "soc",
    covariate_cols = c("twi", "ndvi", "map_mm"),
    epochs = 20L, lr = 0.05, n_steps = 2L, seed = 1L)

  # One row of covariates in, one row of the profile out.  No
  # horizon of the new location is needed -- or used.
  unseen <- piml_hierarchical_predict(fit, held[1, ], hz)
  print(dim(unseen))
  print(round(rbind(pred = as.numeric(unseen), obs = held$soc), 2))

  # The baseline any location-free prediction must beat is the
  # depthwise mean of the training pedons.  Four pedons and 20
  # epochs lose to it by a factor of five, and 60 cm comes back
  # NEGATIVE: the ODE form is learned by an MLP, not imposed, so
  # nothing keeps a profile positive or monotone.  This is what a
  # five-pedon hierarchical fit is -- an interface, not a model.
  seen  <- piml_hierarchical_predict(fit,
             train[train$pedon == "P1", ][1, ], hz)
  dmean <- as.numeric(
    tapply(train$soc, train$depth, mean)[as.character(hz)])
  print(round(c(
    trained_on_this_pedon = sqrt(mean((as.numeric(seen) -
                            train$soc[train$pedon == "P1"])^2)),
    held_out_pedon        = sqrt(mean((as.numeric(unseen) -
                            held$soc)^2)),
    depthwise_mean        = sqrt(mean((dmean - held$soc)^2))), 2))

  # `newdepths` need not be sorted: the integrator sorts, marches
  # and un-sorts, so column j always belongs to newdepths[j].
  p1 <- piml_hierarchical_predict(fit, held[1, ], c(5, 15, 30, 60))
  p2 <- piml_hierarchical_predict(fit, held[1, ], c(60, 5, 30, 15))
  print(all.equal(as.numeric(p1), as.numeric(p2[, c(2, 4, 3, 1)])))

  # Depths are divided by the deepest TRAINING horizon, so asking
  # for 100 or 200 cm marches the network past everything it saw.
  # It answers anyway, and the answer leaves the observed range.
  print(fit$depth_scale)
  print(round(
    piml_hierarchical_predict(fit, held[1, ], c(60, 100, 200)), 2))
  print(round(range(train$soc), 2))
}
```
