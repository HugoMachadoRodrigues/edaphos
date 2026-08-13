# A literature prior for the pedogenetic ODE, independent of the data

The default prior used by
[`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md)
centres three of its hyperparameters on the response being fitted (the
deepest observation, the shallowest observation, and `sd(obs)`). That is
empirical Bayes: the data enter both the likelihood and the prior,
intervals narrow, and a prior-sensitivity check against it is partly a
check of the data against themselves.

## Usage

``` r
piml_prior_literature(
  y_asym_mean = 3,
  y_asym_sd = 1.2,
  y0_mean = 25,
  y0_sd = 0.8,
  z_scale = 35,
  kappa_mean = 3,
  sigma_scale = 2
)
```

## Arguments

- y_asym_mean, y_asym_sd:

  Prior mean and log-scale spread for the attainable deep concentration,
  in the property's units. The default, 3 g/kg, is the order of
  magnitude of deep (\>1 m) mineral-associated organic carbon in deeply
  weathered tropical soils.

- y0_mean, y0_sd:

  Prior mean and log-scale spread for the surface concentration. The
  default, 25 g/kg, is a Cerrado topsoil value.

- z_scale:

  Depth scale in cm over which the decay rate itself decays, used to
  centre `mu`. The default, 35 cm, follows the Jackson et al. (1996)
  tropical-savanna rooting parameter beta = 0.972 via
  `z = -1/log(beta)`.

- kappa_mean:

  Prior mean for the total relaxation `lambda0/mu`. `kappa = 3` means
  the profile closes 95% of its gap.

- sigma_scale:

  Scale of the half-t(3) prior on the observation noise, in the
  property's units. The default, 2 g/kg, reflects laboratory plus
  short-range spatial variability rather than the spread of this
  profile.

## Value

A list in the form
[`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md)
expects for its `prior` argument.

## Details

This constructor builds a prior from published values instead, so the
two can be compared and the circularity measured rather than assumed
harmless.

## References

Jackson RB, Canadell J, Ehleringer JR, Mooney HA, Sala OE, Schulze ED
(1996). A global analysis of root distributions for terrestrial biomes.
*Oecologia* 108:389-411.

## Examples

``` r
# Compare the empirical-Bayes default against a non-circular prior on the
# pedon shipped with the package.
B <- readRDS(system.file("extdata", "capstone_campaign_results.rds",
                         package = "edaphos"))
p <- B$piml_profile_obs
a <- piml_profile_fit_bayesian(p$depth_mid, p$soc_g_kg,
                               top = p$top, bottom = p$bottom, seed = 7L)
b <- piml_profile_fit_bayesian(p$depth_mid, p$soc_g_kg,
                               top = p$top, bottom = p$bottom,
                               prior = piml_prior_literature(), seed = 7L)
# If the two disagree, the default's data-dependence is doing real work.
round(cbind(empirical_bayes = summary(a)$mean,
            literature      = summary(b)$mean), 4)
#>      empirical_bayes literature
#> [1,]          0.0105     0.0108
#> [2,]          0.0048     0.0058
#> [3,]         -2.2916    -4.1070
#> [4,]         24.2147    24.7398
#> [5,]          3.0343     2.3725
#> [6,]          2.2205     2.4540
#> [7,]          0.1684     0.1741
```
