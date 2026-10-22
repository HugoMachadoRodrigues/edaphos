# Predict at new sites from a fitted Bayesian hierarchical spatial model

Bayesian kriging: for each posterior draw of `(beta, sigma^2, tau^2)` we
sample the latent GP at new locations conditional on the observed latent
field, then add iid noise. Returns posterior mean and quantiles at each
`newdata` row.

## Usage

``` r
# S3 method for class 'edaphos_bhs'
predict(
  object,
  newdata,
  quantiles = c(0.025, 0.5, 0.975),
  n_draws = 500L,
  draws = FALSE,
  ...
)
```

## Arguments

- object:

  An `edaphos_bhs` fit.

- newdata:

  A data frame with covariates + coordinates matching the training
  schema.

- quantiles:

  Quantile levels to return. Default `c(0.025, 0.5, 0.975)`.

- n_draws:

  Integer; how many posterior samples to use (capped by the actual
  number available in the fit). Default `500L`.

- draws:

  Logical; when `TRUE`, attach the predictive draws themselves as
  `attr(result, "draws")`, an `n_draws x nrow(newdata)` matrix. The
  summaries are a lossy view of them: the predictive is a scale mixture
  of normals, one component per posterior draw of \\(\beta, \sigma^2,
  \tau^2)\\, and a caller that rebuilds `rnorm(n, mean, sd)` from the
  summary is scoring a Gaussian rather than this model. The package's
  own cross-pillar benchmark did exactly that until the draws were
  exposed here; on the WoSIS Cerrado archive the substitution moved
  PICP90 by 0.6 percentage points. Default `FALSE`, so no existing
  caller sees a different object.

- ...:

  Unused.

## Value

A data frame with `newdata` rows plus columns `mean`, `sd`, and one
column per quantile; with `draws = TRUE`, additionally carrying the
draws matrix in the `"draws"` attribute.

## Examples

``` r
data(br_cerrado)

# A contiguous 13 x 13 block of the Cerrado grid, 40 cells held out.
ux  <- sort(unique(br_cerrado$x)); uy <- sort(unique(br_cerrado$y))
blk <- br_cerrado[br_cerrado$x %in% ux[10:22] &
                  br_cerrado$y %in% uy[10:22], ]
names(blk)[names(blk) == "x"] <- "lon"
names(blk)[names(blk) == "y"] <- "lat"
set.seed(7)
ho    <- sample(nrow(blk), 40L)
train <- blk[-ho, ]; test <- blk[ho, ]

fit <- bhs_fit(train, soc ~ elev + slope + twi + map_mm + ndvi,
               nmcmc = 800L, phi_range = c(0.1, 2000), seed = 1L)

# Every posterior draw is used twice -- once for x0'beta, once for the
# kriging correction -- and observation noise is added on top, so
# predict() is random.  Seed it, or the number you quote moves.
set.seed(11)
pred <- predict(fit, test, n_draws = 300L)
head(pred, 3)
#>       mean       sd      q025     q500     q975
#> 1 18.31077 4.248321  9.740263 18.33473 26.75854
#> 2 22.90039 4.195185 14.829055 22.72259 31.10368
#> 3 19.50207 3.836376 12.281883 19.70297 27.04538

# Quantile columns are named from the requested probabilities scaled by
# 1000: 0.025 -> q025, 0.5 -> q500, 0.95 -> q950.
names(predict(fit, test[1:3, ], quantiles = c(0.05, 0.5, 0.95),
              n_draws = 50L))
#> [1] "mean" "sd"   "q050" "q500" "q950"

# Held-out accuracy against the training mean and against OLS on the
# same covariates, with the coverage of the nominal 95% band.
round(c(bhs  = sqrt(mean((pred$mean - test$soc)^2)),
        null = sqrt(mean((mean(train$soc) - test$soc)^2)),
        ols  = sqrt(mean((predict(lm(soc ~ elev + slope + twi + map_mm +
                                     ndvi, data = train),
                                  test) - test$soc)^2)),
        picp95 = mean(test$soc >= pred$q025 & test$soc <= pred$q975)), 3)
#>    bhs   null    ols picp95 
#>  4.408  5.548  4.340  0.925 

# The kriging correction is the only reason to prefer this over lm(), so
# check it is doing something.  phi came back interior to its bracket
# here -- 804, no warning -- and that is necessary, not sufficient: the
# implied correlation range is 0.0012 degrees, a fifth of the distance
# to the nearest other profile, so the "spatial" field handed 94% of the
# residual variance correlates 0.004 with the closest site.
d <- as.matrix(dist(as.matrix(train[, c("lon", "lat")])))
s2 <- mean(fit$sigma2_draws); t2 <- mean(fit$tau2_draws)
round(c(phi = fit$phi_hat, range_deg = 1 / fit$phi_hat,
        min_spacing = min(d[d > 0]),
        corr_at_min_spacing = exp(-fit$phi_hat * min(d[d > 0])),
        spatial_share = s2 / (s2 + t2)), 4)
#>                 phi           range_deg         min_spacing corr_at_min_spacing 
#>            804.1422              0.0012              0.0068              0.0042 
#>       spatial_share 
#>              0.9382 

# What that costs shows up in the predictive sd.  Ask for a prediction
# AT five training coordinates and it is 1.33, because r0 = 1 there and
# the model is recalling those profiles' own measurements.  Move half a
# grid cell -- 0.004 deg, about 440 m -- and it is 4.02, the same as
# three degrees outside the block and the same as the marginal
# sqrt(sigma^2 + tau^2).
half <- train[1:5, ]; half$lon <- half$lon + 0.004
far  <- train[1:5, ]; far$lon  <- far$lon  + 3
set.seed(3); p_at   <- predict(fit, train[1:5, ], n_draws = 300L)
set.seed(3); p_half <- predict(fit, half, n_draws = 300L)
set.seed(3); p_far  <- predict(fit, far,  n_draws = 300L)
round(c(sd_at_site = mean(p_at$sd), sd_half_cell = mean(p_half$sd),
        sd_3deg = mean(p_far$sd), marginal = sqrt(s2 + t2)), 4)
#>   sd_at_site sd_half_cell      sd_3deg     marginal 
#>       1.3294       4.0171       4.0345       3.9860 

# The narrow band at a training site is recall, not skill, and a map is
# made between the nodes.  Quote the second number, and read it next to
# the held-out picp95 above.

# `n_draws` is capped at the draws the fit kept, and it buys precision
# in the summaries rather than width: at 300 draws a site's posterior
# mean moves by up to 0.66 g/kg between two calls, at 50 draws by 1.69.
mc_gap <- function(nd) {
  set.seed(1); a <- predict(fit, test[1:10, ], n_draws = nd)
  set.seed(2); b <- predict(fit, test[1:10, ], n_draws = nd)
  max(abs(a$mean - b$mean))
}
round(c(kept = nrow(fit$beta_draws), gap_300 = mc_gap(300L),
        gap_50 = mc_gap(50L)), 3)
#>    kept gap_300  gap_50 
#> 400.000   0.663   1.689 

# `newdata` must carry the coordinate columns under their training
# names as well as every covariate; neither omission gets a friendly
# message.
try(predict(fit, test[, c("elev", "slope", "twi", "map_mm", "ndvi")]))
#> Error in `[.data.frame`(newdata, , coord_cols, drop = FALSE) : 
#>   undefined columns selected
```
