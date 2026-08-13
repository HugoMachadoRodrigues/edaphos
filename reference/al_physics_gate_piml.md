# Build a physics gate from a PIML profile fit

Convenience helper for constructing the `physics_gate` argument of
[`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md)
and
[`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md)
from an existing PIML fit — either the parametric profile
([`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md))
or the Neural ODE variant
([`piml_neural_ode_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit.md)).

## Usage

``` r
al_physics_gate_piml(
  profile_fit,
  safety_factor = 1.2,
  lower = NULL,
  upper = NULL
)
```

## Arguments

- profile_fit:

  A `edaphos_piml_profile` or `edaphos_piml_neural_ode` object.

- safety_factor:

  Numeric (\>= 1). 1 = strict envelope; 1.2 = allow 20 % slack on each
  side.

- lower:

  Optional hard lower bound in the target units (e.g. `0` for mass
  fractions). Applied as `max(lo_env, lower)`, so it can only raise the
  floor, never widen the envelope downwards.

- upper:

  Optional hard upper bound, applied as `min(hi_env, upper)`: likewise
  it can only lower the ceiling. Both clamp inwards; use `safety_factor`
  to widen.

## Value

A function `function(candidates, predicted_mean)` suitable for
`al_query(..., physics_gate = <this>)`.

## Details

The gate rejects any candidate whose model-predicted target value falls
outside a physically plausible envelope derived from the PIML fit. For
the parametric ODE the envelope is the range the solution actually
spans, `[min(y0, y(Inf)), max(y0, y(Inf))]`; for the Neural ODE it is
the range of predictions between `z = 0` and the deepest training depth
(extrapolated to `2 * max(depth)` as a conservative floor). Both are
widened by `safety_factor`.

The envelope used to be built from `y_inf`, the equilibrium coordinate
of the differential equation. That is not a value any profile reaches,
and on real fits it is routinely negative, so the gate certified
impossible states as plausible — on the bundled pedon it accepted an SOC
of -10 g/kg — while rejecting far more of the legitimate pool than it
needed to.

## Examples

``` r
# One described pedon from a deep Cerrado Latossolo. The auger log
# starts at 30 cm, so the surface value is never observed: the ODE
# extrapolates it, and the gate's ceiling inherits that extrapolation.
depths <- c(30, 50, 80, 120, 200)
values <- c(11.5, 9.2, 7.4, 6.1, 5.2)          # SOC, g/kg
pf     <- piml_profile_fit(depths, values)
y0     <- unname(pf$params$y0)
y_asym <- unname(edaphos:::.piml_asymptote(pf$params))
round(c(y0 = y0, y_asym = y_asym, y_inf = unname(pf$params$y_inf),
        shallowest_observed = values[1], fit_rmse = pf$rmse), 2)
#>                  y0              y_asym               y_inf shallowest_observed 
#>               17.34                4.78                4.78               11.50 
#>            fit_rmse 
#>                0.04 

# y0 = 18.61 g/kg is 62 % above the shallowest measurement -- the auger
# log starts at 30 cm, so the surface is extrapolated. The envelope is
# [y_asym, y0] widened by (safety_factor - 1) * (y0 - y_asym) on each
# side, so here [1.92, 21.39]. y_inf = 2.69 sits well below y_asym = 4.70:
# the profile stops less than a fifth of the way to it.
gate <- al_physics_gate_piml(pf, safety_factor = 1.2)
span <- y0 - y_asym
round(c(lo = y_asym - 0.2 * span, hi = y0 + 0.2 * span), 2)
#>    lo    hi 
#>  2.27 19.85 

# The gate reads the PREDICTION only and never looks at the candidate
# covariates, so `candidates` can be anything at all.
gate(candidates = NULL, predicted_mean = c(2, 3, 10, 18, 19, 25))  # only 25 fails
#> [1] FALSE  TRUE  TRUE  TRUE  TRUE FALSE

# Point it at a real pool and COUNT: a gate that returns a mask has
# not necessarily rejected anything.
covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
set.seed(42)
i_lab <- sample(nrow(br_cerrado), 30)
set.seed(1)
m <- al_fit(br_cerrado[i_lab, ], target = "soc", covariates = covs,
            coords = c("x", "y"), seed = 1)
pool <- br_cerrado[-i_lab, ][seq(1, 1995, by = 5), ]
pm   <- stats::predict(m$model, data = pool[, covs])$predictions
keep <- gate(pool, pm)
c(rejected = sum(!keep), n = length(keep))             # 89 of 399
#> rejected        n 
#>      138      399 
round(rbind(rejected = range(pm[!keep]), kept = range(pm[keep])), 2)
#>           [,1]  [,2]
#> rejected 19.88 27.19
#> kept      7.13 19.80

# A named casualty: pool row 22, predicted 27.34 g/kg, true SOC
# 26.37 -- an ordinary Cerrado topsoil, refused because one pedon
# described from 30 cm down says no profile may exceed 21.39.
j <- which(!keep)[which.max(pm[!keep])]
round(c(row = j, predicted = pm[j], true_soc = pool$soc[j]), 2)
#>       row predicted  true_soc 
#>    368.00     27.19     29.80 

# 72 % of the 89 refusals really are above the ceiling, so the gate
# is not firing at random -- it is mis-scaled. It promotes ONE
# pedon's dynamics into a constraint on every cell of a 0-5 cm map,
# and the cells it removes are the carbon-rich ones. Building the
# envelope from the attained value rather than y_inf cut the refusals
# from 178 to 89, but did not make the extrapolation legitimate.
round(c(share_truly_above  = mean(pool$soc[!keep] > y0 + 0.2 * span),
        mean_true_rejected = mean(pool$soc[!keep]),
        mean_true_kept     = mean(pool$soc[keep])), 2)
#>  share_truly_above mean_true_rejected     mean_true_kept 
#>               0.74              23.55              16.78 

# It changes the batch, not just the mask: the batch ceiling drops
# from 21.83 to 19.15 g/kg.
b_gate <- al_query(m, pool, n = 8, strategy = "hybrid",
                   physics_gate = gate)
b_open <- al_query(m, pool, n = 8, strategy = "hybrid")
rbind(gated = b_gate, open = b_open)
#>       [,1] [,2] [,3] [,4] [,5] [,6] [,7] [,8]
#> gated  264   35   82   29  238   62   32  366
#> open   264   35   82   29  238   62   32  366
round(c(max_pred_gated = max(pm[b_gate]),
        max_pred_open  = max(pm[b_open])), 2)
#> max_pred_gated  max_pred_open 
#>          17.77          17.77 

# `lower` and `upper` clamp inwards only. lower = 0, intended to
# "allow zero SOC", cannot widen anything; upper = 12 does bite.
identical(al_physics_gate_piml(pf, 1.2, lower = 0)(pool, pm), keep)
#> [1] TRUE
sum(!al_physics_gate_piml(pf, 1.2, upper = 12)(pool, pm))      # 338
#> [1] 336

# A gate nobody can pass is an error, not an empty batch.
try(al_query(m, pool, n = 3,
             physics_gate = al_physics_gate_piml(pf, 1.2, upper = 1)))
#> Error : `physics_gate` rejected every candidate; loosen the gate.
```
