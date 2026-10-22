# Fit a Bayesian hierarchical spatial linear model (Pilar 7)

The v2.3.0 activation of the Pilar 7 scaffold. Fits a Bayesian spatial
linear model `y_i = x_i' beta + w_i + eps_i` with a latent
exponential-correlation Gaussian process on the residual field and
returns full posterior draws.

## Usage

``` r
bhs_fit(
  data,
  formula,
  coords = c("lon", "lat"),
  backend = c("gibbs", "rcpp", "spBayes"),
  nmcmc = 2000L,
  burn = NULL,
  thin = 1L,
  prior_var_beta = 1000,
  prior_ig_a = 2,
  prior_ig_b = 1,
  phi_range = NULL,
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- data:

  A data frame with the response + covariates + spatial coordinates.

- formula:

  A `response ~ covariates` formula.

- coords:

  Character length-2 (default `c("lon", "lat")`) giving the coordinate
  columns.

- backend:

  One of `"gibbs"` (pure-R Gibbs sampler, default, no external deps),
  `"rcpp"` (the same sampler with an RcppArmadillo inner loop), or
  `"spBayes"` (dispatches to
  [`spBayes::spLM`](https://finleya.github.io/spBayes/reference/spLM.html)
  when available).

  **`"spBayes"` fits but cannot predict.**
  [`predict.edaphos_bhs()`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_bhs.md)
  refuses on that backend, so a fit made with it supports posterior
  inspection – `beta_draws`, `sigma2_draws`, `tau2_draws`,
  [`print()`](https://rdrr.io/r/base/print.html), the spatial variance
  share – but not kriging at new sites. `bhs_fit()` warns about this
  before it starts sampling rather than after. Use `"gibbs"` or `"rcpp"`
  if you need predictions.

- nmcmc:

  Integer; number of MCMC iterations. Default `2000L`.

- burn:

  Integer; burn-in to discard. Default `nmcmc %/% 2`.

- thin:

  Integer; keep every `thin`-th post-burn draw. Default `1L`.

- prior_var_beta:

  Numeric; Gaussian prior variance on `beta`.

- prior_ig_a, prior_ig_b:

  Shape and scale of the inverse-Gamma priors on `sigma^2` and `tau^2`.

- phi_range:

  Numeric length-2; bracket for the profile-MLE of the GP rate parameter
  `phi`. Default `NULL`, meaning **derive it from the data** as
  `c(3 / max(dist), 3 / min(dist))`. `phi` is a **rate**, entering the
  correlation as \\\rho(d) = \exp(-\phi d)\\, so its units are
  1/distance and a fixed constant cannot suit both a 750 m grid and a
  2,000 km biome – which is why the previous default of `c(0.01, 10)`
  decided the answer on both.

  The derived endpoints are the two places where `phi` stops being
  identifiable: at the upper end the practical range `3 / phi` is
  shorter than the closest pair of observations, so the correlation has
  decayed to nothing between any two of them and the field is a nugget;
  at the lower end the range exceeds the domain, so the field is
  constant across it and confounded with the intercept. Landing on an
  endpoint is then a statement about the data rather than about the
  bracket, and `bhs_fit()` warns and records it in `phi_railed` /
  `phi_rail_edge`. Supply a bracket explicitly to override;
  `phi_range_source` on the returned object records which happened.

- seed:

  Optional RNG seed.

- verbose:

  Logical.

## Value

An `edaphos_bhs` S3 object. Among its fields, `phi_hat` is the
profile-MLE of the rate, and `phi_railed` / `phi_rail_edge` record
whether that MLE landed on an endpoint of `phi_range` and which one. The
warning alone is not enough: a downstream script that reads `phi_hat` or
the spatial variance fraction needs to branch on whether the data or the
bracket produced them. `spatial` carries `spatial_share`, its complement
`nugget_sill_ratio`, the practical range `3 / phi`, the
nearest-neighbour `min_spacing`, and `range_below_spacing` – TRUE when
the correlation has decayed to 0.05 inside the closest pair of
observations, in which case the latent field and the nugget are the same
white noise and the share is not interpretable.

## References

Banerjee, S., Carlin, B. P. and Gelfand, A. E. (2014). *Hierarchical
Modeling and Analysis for Spatial Data*, 2nd edition. Chapman and
Hall/CRC, Boca Raton.
[doi:10.1201/b17115](https://doi.org/10.1201/b17115)

Rue, H., Martino, S. and Chopin, N. (2009). Approximate Bayesian
inference for latent Gaussian models by using integrated nested Laplace
approximations. *Journal of the Royal Statistical Society: Series B*
**71**, 319-392.
[doi:10.1111/j.1467-9868.2008.00700.x](https://doi.org/10.1111/j.1467-9868.2008.00700.x)

Cressie, N. and Wikle, C. K. (2011). *Statistics for Spatio-Temporal
Data*. Wiley, Hoboken.

## Examples

``` r
data(br_cerrado)

# A contiguous 13 x 13 block of the Cerrado grid: 169 sites, 0.0080 deg
# apart in longitude and 0.0068 in latitude.  bhs_fit() wants the
# coordinates under lon / lat.
ux  <- sort(unique(br_cerrado$x)); uy <- sort(unique(br_cerrado$y))
blk <- br_cerrado[br_cerrado$x %in% ux[10:22] &
                  br_cerrado$y %in% uy[10:22], ]
names(blk)[names(blk) == "x"] <- "lon"
names(blk)[names(blk) == "y"] <- "lat"

# phi is a RATE: it enters the correlation as exp(-phi * d), so 3 / phi is
# a practical correlation range in the units of `coords` -- degrees here.
#
# The likelihood on this block keeps improving as the range shrinks, so
# whatever you cap phi at is what you get back. That is why a CONSTANT
# bracket cannot be a sensible default: it decides the answer. The default
# is now derived from the data, and its upper end is the closest pair of
# observations -- the point past which the correlation has decayed to
# nothing between any two of them, so there is nothing left to estimate.
fit_auto  <- bhs_fit(blk, soc ~ elev + slope, nmcmc = 600L, seed = 1L)
#> Warning: bhs_fit(): the profile-MLE of phi (440) is at the upper end of phi_range = c(23.86, 440), derived from the data. The bracket is derived from the data, and its upper end is the closest pair of sites: a practical range shorter than that has decayed to nothing between any two observations, so this survey cannot distinguish the field from a nugget. Widening the bracket would not help; a denser survey would. phi is a rate (1/distance) in the units of `coords`.
fit_wide  <- bhs_fit(blk, soc ~ elev + slope, nmcmc = 600L, seed = 1L,
                     phi_range = c(0.1, 2000))
#> Warning: bhs_fit(): the profile-MLE of phi (2000) is at the upper end of phi_range = c(0.1, 2000), supplied. Widen phi_range and refit; the spatial variance fraction is not trustworthy until phi is interior. phi is a rate (1/distance) in the units of `coords`.
fit_huge  <- bhs_fit(blk, soc ~ elev + slope, nmcmc = 600L, seed = 1L,
                     phi_range = c(0.1, 1e5))
#> Warning: bhs_fit(): the profile-MLE of phi (1e+05) is at the upper end of phi_range = c(0.1, 1e+05), supplied. Widen phi_range and refit; the spatial variance fraction is not trustworthy until phi is interior. phi is a rate (1/distance) in the units of `coords`.
fit_auto
#> <edaphos_bhs>  (Pilar 7 -- Bayesian Hierarchical Spatial)
#>   backend : gibbs
#>   n_obs   : 169
#>   p (covariates + intercept) : 3
#>   MCMC draws kept : 300
#>   phi (profile-MLE) : 439.9999
#>   beta posterior means:
#>     (Intercept)          52.1543 (sd 5.3841)
#>     elev                 -0.0263 (sd 0.0063)
#>     slope                -0.5666 (sd 0.0722)
#>   sigma^2 posterior mean : 0.7577
#>   tau^2   posterior mean : 20.2302
#>   spatial share sigma^2/(sigma^2 + tau^2) : 0.036
#>   practical range 3/phi : 0.006818 (nearest-neighbour spacing 0.006818, same units as coords)
#>   <-- phi railed at the upper end of its bracket; the bracket, not
#>       the data, set the correlation rate

# That is not a cosmetic complaint.  Under the two hand-picked brackets the
# spatial share of the residual variance, sigma^2 / (sigma^2 + tau^2),
# comes out around 0.89 -- the same data and formula reporting a strong
# latent field, on a correlation range far shorter than the grid spacing.
# The derived bracket stops at the spacing and the share falls to about
# 0.04, which is the honest reading: this block is nearly all nugget.
round(c(phi_auto = fit_auto$phi_hat, phi_wide = fit_wide$phi_hat,
        phi_huge = fit_huge$phi_hat,
        share_auto = fit_auto$spatial$spatial_share,
        share_wide = fit_wide$spatial$spatial_share,
        share_huge = fit_huge$spatial$spatial_share), 4)
#>    phi_auto    phi_wide    phi_huge  share_auto  share_wide  share_huge 
#>    439.9999   1999.9999  99999.9970      0.0361      0.8862      0.8862 

# All three still rail, and that is now informative rather than arbitrary:
# `$phi_range_source` says whether the bracket was derived or supplied, and
# `$range_below_spacing` says whether the fitted range survived to the
# closest pair. Only the hand-picked ones fail that test.
vapply(list(fit_auto, fit_wide, fit_huge),
       function(f) f$spatial$range_below_spacing, logical(1))
#> [1] FALSE  TRUE  TRUE

# The tie-breaker is not the likelihood, it is the geometry.  At
# phi = 2000 the correlation between the two CLOSEST sites in the block
# is 1e-06: exp(-phi * d) has decayed to nothing well inside one grid
# cell, so w and eps are the same white noise and their split is
# arbitrary.  An "89% spatial" fit whose correlation range is 55 m on a
# 750 m grid is reporting a nugget under another name.
d <- as.matrix(dist(as.matrix(blk[, c("lon", "lat")])))
round(c(range_deg = 1 / fit_wide$phi_hat, min_spacing = min(d[d > 0]),
        corr_at_min_spacing = exp(-fit_wide$phi_hat * min(d[d > 0]))), 6)
#>           range_deg         min_spacing corr_at_min_spacing 
#>            0.000500            0.006818            0.000001 

# Which is also why the beta posterior sits on top of OLS: with the
# correlation matrix effectively the identity, generalised least squares
# has nothing to weight.  Both slopes agree to well under a third of a
# posterior sd.
o <- lm(soc ~ elev + slope, data = blk)
round(rbind(bhs = colMeans(fit_wide$beta_draws), ols = coef(o),
            post_sd = apply(fit_wide$beta_draws, 2L, sd)), 4)
#>         (Intercept)    elev   slope
#> bhs         52.6592 -0.0265 -0.5879
#> ols         53.6279 -0.0279 -0.5701
#> post_sd      5.0989  0.0056  0.0698

# `nmcmc` is the raw chain; `burn` (half of it by default) and `thin`
# decide how much survives, and every downstream interval -- including
# predict()'s -- is built from those kept draws alone.
c(nmcmc = fit_wide$nmcmc, burn = fit_wide$burn,
  kept = nrow(fit_wide$beta_draws))
#> nmcmc  burn  kept 
#>   600   300   300 
```
