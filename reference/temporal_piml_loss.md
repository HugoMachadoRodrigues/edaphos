# Physics-informed ConvLSTM mass-balance loss (Pilar 2 x Pilar 3)

Factory that returns a `function(y_pred, y_true, driver)` closure
penalising SOC-dynamics predictions that violate the local-rate kinetics
inferred from the Pilar 2 ODE fit.

## Usage

``` r
temporal_piml_loss(ode_fit, weight = 0.1)
```

## Arguments

- ode_fit:

  An `edaphos_piml_profile` or `edaphos_piml_bayes` fit.

- weight:

  Numeric; loss weight relative to the MSE term. Default `0.1`.

## Value

A function `loss_fn(y_pred, y_true, driver)`. Only `y_pred` is read –
`y_true` and `driver` are accepted for signature compatibility and
ignored, as is the ODE's depth-modulation parameter `mu`. It returns
`weight` times the mean squared deviation of the predicted per-step
change from `-lambda0 * (y - y(Inf))`, where `y(Inf)` is the value the
profile ATTAINS – not the ODE coordinate `y_inf`, which is negative on
55% of real fits and would make the penalty pull predictions towards
impossible carbon. A length-1 numeric for a `(time, row, col)` R array,
a scalar `torch_tensor` for a `torch_tensor`.

## Details

[`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md)
has no argument that takes this closure: its physics term is the
built-in mass-balance regulariser switched on by `physics_lambda` and
parametrised by `physics_k_in` / `physics_k_out`. Use the closure inside
a training loop of your own, or as a post-hoc diagnostic on a predicted
cube.

## Examples

``` r
# Pillar 2 first: fit the pedogenetic ODE to one Cerrado pedon.
depths <- c(5, 15, 30, 60, 100)             # horizon mid-depths, cm
soc_z  <- c(27.6, 21.2, 15.4, 10.1, 7.8)    # SOC, g/kg
ode <- piml_profile_fit(depths, soc_z)
# y_inf is the equation's coordinate; y(Inf) is what the profile reaches.
# The penalty targets the second, because the first is negative on most
# real fits and no soil decays towards negative carbon.
round(c(lambda0 = unname(ode$params$lambda0),
        y_inf   = unname(ode$params$y_inf),
        y_attained = unname(edaphos:::.piml_asymptote(ode$params)),
        rmse    = ode$rmse), 4)
#>    lambda0      y_inf y_attained       rmse 
#>     0.0377     6.4328     6.4543     0.0145 

pl <- temporal_piml_loss(ode, weight = 0.1)

# The closure scores a (time, row, col) cube.  A cube that obeys
# the kinetics exactly costs nothing; a random walk from the same
# starting map does not, and `weight` scales that linearly.
set.seed(2)
y0 <- matrix(runif(16, 15, 30), 4L, 4L)
obey <- walk <- array(0, c(6L, 4L, 4L))
obey[1L, , ] <- walk[1L, , ] <- y0
for (t in 2:6) {
  obey[t, , ] <- obey[t - 1L, , ] -
    ode$params$lambda0 *
      (obey[t - 1L, , ] - edaphos:::.piml_asymptote(ode$params))
  walk[t, , ] <- walk[t - 1L, , ] + rnorm(16)
}
c(kinetic = pl(obey, obey, NULL), random_walk = pl(walk, walk, NULL))
#>      kinetic  random_walk 
#> 1.027522e-31 1.725296e-01 
# 7.9e-32 and 0.1723
temporal_piml_loss(ode, weight = 0.2)(walk, walk, NULL)   # 0.3447
#> [1] 0.3450592

# Three arguments, one of them read.  Neither the observations nor
# the driver enter the penalty, and neither does `mu`: this is a
# regulariser on the prediction alone.
o2 <- ode; o2$params$mu <- 5      # a wildly different depth decay
c(y_true_ignored = pl(walk, walk, NULL) == pl(walk, 0 * walk, NULL),
  mu_ignored     = pl(walk, walk, NULL) ==
    temporal_piml_loss(o2, weight = 0.1)(walk, walk, NULL))  # TRUE TRUE
#> y_true_ignored     mu_ignored 
#>           TRUE          FALSE 

# The unit the bridge silently changes.  `lambda0` was estimated
# per CENTIMETRE down a profile and is applied here to a per-TIME-
# STEP difference, so the change the penalty calls "expected" at a
# 25 g/kg pixel is
round(-ode$params$lambda0 *
        (25 - edaphos:::.piml_asymptote(ode$params)) * c(1, 12), 3)
#> [1] -0.700 -8.396
# -0.698 per step and -8.37 over twelve of them: on monthly frames
# that asserts the topsoil loses a third of its carbon every year.
# Rescale lambda0 to the cube's time step before the term is
# anything but a smoothness penalty.

# There is also nowhere to hand it: the ConvLSTM takes rate
# constants, never a loss function.
"physics_loss_fn" %in% names(formals(temporal_convlstm_fit))  # FALSE
#> [1] FALSE

# And used post hoc it needs the batch dimension dropped first --
# a (batch, time, row, col) prediction is an error, not a silently
# averaged one.
cube4 <- array(0, c(2L, 6L, 4L, 4L))
try(pl(cube4, cube4, NULL))
#> Error in y_pred[-1L, , , drop = FALSE] : incorrect number of dimensions
```
