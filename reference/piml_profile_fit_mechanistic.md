# Fit the depth profile derived from a steady-state carbon balance (Pillar 2b)

Fits \$\$v \frac{dC}{dz} = I(z) - kC, \qquad I(z) = I_0 e^{-z/z_r},\$\$
the advection-reaction limit of the standard soil-carbon depth balance
with bioturbation neglected, plus a mineral-associated floor.
Equivalently \$\$\frac{dC}{dz} = -\lambda\\\bigl(C - \[A + B
e^{-z/z_r}\]\bigr), \qquad \lambda = k/v,\\ B = I_0/k,\$\$ a relaxation
with a **constant** rate toward a **depth-varying** target.

## Usage

``` r
piml_profile_fit_mechanistic(
  depths,
  values,
  y_surface = NULL,
  top = NULL,
  bottom = NULL,
  family = c("lognormal", "gaussian", "gamma"),
  reg = 0.001,
  control = list(maxit = 4000)
)
```

## Arguments

- depths:

  Numeric vector of horizon mid-depths (cm).

- values:

  Numeric vector of concentrations, same length, strictly positive.

- y_surface:

  Optional fixed surface value; if supplied it is not estimated.

- top, bottom:

  Optional horizon boundaries. When supplied each datum is compared to
  the model's depth-average over its horizon (analytic here, since every
  term is an exponential) rather than to a point evaluation.

- family:

  Observation family, as in
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md).
  Defaults to `"lognormal"`: soil carbon is positive and right-skewed,
  and a Gaussian on g/kg weights every horizon by the same absolute
  error, so a profile spanning 30 to 2 g/kg is fitted almost entirely by
  its topsoil.

- reg:

  L2 shrinkage toward the data-driven start, on the log scale.

- control:

  [`stats::optim`](https://rdrr.io/r/stats/optim.html) control list.

## Value

An `edaphos_piml_mech` object with `params` (`A`, `B`, `lambda`, `z_r`,
`y0`), `rmse`, `fitted`, `converged`, and the inputs.

## Details

This is the mechanistic counterpart to
[`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md).
The two differ in where the depth-dependence sits:
[`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)
attenuates the *rate* with depth, which no process produces and which
pushes its equilibrium coordinate outside the admissible range; this
model attenuates the *target*, following root input, and every parameter
is positive with a literature prior.

On accuracy the two are a tie, and the honest statement of that took two
attempts. Under a Gaussian likelihood this model appeared to win
decisively on leave-the-deepest-horizon-out prediction across the 875
monotone profiles in `inst/extdata/piml_wosis_cerrado.rds` (p = 2e-6).
Correcting the likelihood for BOTH models removed the difference: RMSE
1.483 against 1.507, winning on 454 of 875 profiles against 421, paired
Wilcoxon p = 0.25. The Gaussian had been penalising the attenuating-rate
form more heavily, because weighting every horizon by the same absolute
error hurts the model whose flexibility lies in the deep tail.

Prefer this model because it can be defended, not because it predicts
better. On the nine-horizon pedon shipped with the package it does fit
markedly better (RMSE 0.44 against 2.52 g/kg), but one pedon is one
pedon.

## What this model does not identify

`lambda` is the ratio \\k/v\\ of the decomposition rate constant to the
advection velocity, and `B` is the ratio \\I_0/k\\ of the surface root
input to the same rate constant. A depth profile alone cannot separate
them: doubling both \\k\\ and \\v\\ leaves every prediction unchanged.
The fitted numbers are therefore *ratios with soil-physical meaning*,
not decomposition rates, and reporting `lambda` as a turnover rate would
be wrong. Separating \\k\\ from \\v\\ needs an independent constraint —
radiocarbon ages, a chronosequence, or a measured erosion or deposition
rate — none of which is in this package.

The same applies to the neglected bioturbation term: setting \\D = 0\\
is an assumption about the depth range, valid below the mixed surface
layer, and it is not testable from a single profile.

## References

Elzein A, Balesdent J (1995). Mechanistic simulation of vertical
distribution of carbon concentrations and residence times in soils.
*Soil Science Society of America Journal* 59:1328–1335.

Jackson RB, Canadell J, Ehleringer JR, Mooney HA, Sala OE, Schulze ED
(1996). A global analysis of root distributions for terrestrial biomes.
*Oecologia* 108:389–411.

Braakhekke MC, Beer C, Hoosbeek MR, et al. (2011). SOMPROF: a vertically
explicit soil organic matter model. *Ecological Modelling*
222:1712–1730.

## See also

[`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)
for the attenuating-rate form, and
[`vignette("pilar2-piml-profile")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar2-piml-profile.md)
for the comparison.

## Examples

``` r
# A simulated Cerrado-shaped profile. This package ships no real soil
# data; see [edaphos_example_profiles()] for what these values are.
H <- edaphos_example_profiles(what = "horizons")
h <- H[H$profile_id == H$profile_id[1], ]
fit <- piml_profile_fit_mechanistic(h$depth_mid, h$soc_g_kg,
                                    top = h$top, bottom = h$bottom)
fit
#> <edaphos_piml_mech>
#>   v dC/dz = I0 exp(-z/z_r) - k C     (steady-state advection-reaction)
#>   dC/dz   = -lambda (C - [A + B exp(-z/z_r)]),  lambda = k/v, B = I0/k
#>   y0    = 45.98      A (deep floor) = 0.2467   
#>   B     = 31.49      z_r = 43.25     cm   lambda = 0.1734 /cm
#>   implied Jackson beta = 0.9771
#>   n obs = 5 (layer)       rmse = 0.4507   converged = TRUE
```
