# Quantum Kernel Ridge Regression on foundation embeddings

Fits
[`quantum_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_fit.md)
on the top-n PCs of foundation-model embeddings (rescaled to
`[-pi, pi]`). Returns an object that wraps both the PCA reduction and
the quantum KRR fit so
[`predict()`](https://rdrr.io/r/stats/predict.html) handles the full
forward pipeline.

## Usage

``` r
qf_krr_fit(embeddings, y, n_pcs = 8L, reps = 2L, lambda = 0.1)
```

## Arguments

- embeddings:

  Per-observation embedding matrix.

- y:

  Response vector (regression target).

- n_pcs, reps, lambda:

  See
  [`qf_embed_reduce()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_embed_reduce.md)
  and
  [`quantum_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_fit.md).

## Value

An `edaphos_qf_krr` object.

## Examples

``` r
# Stand-in MoCo encoder output over 200 Cerrado pixels; the
# target is the bundled SOC column (g/kg, 0-5 cm).
set.seed(42)
covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
sub  <- br_cerrado[sample(nrow(br_cerrado), 200L), ]
Z    <- scale(as.matrix(sub[, covs]))
W    <- matrix(rnorm(5L * 64L), 5L, 64L)
emb  <- tanh(Z %*% W) + matrix(rnorm(200L * 64L, 0, 0.1), 200L, 64L)
y    <- sub$soc
tr   <- 1:140; te <- 141:200

fit <- qf_krr_fit(emb[tr, ], y[tr], n_pcs = 6L, reps = 2L,
                  lambda = 0.1)
fit
#> <edaphos_qf_krr>  (Pillar 4 x Pillar 6 bridge)
#>   n_pcs  = 6  (qubits = 6)
#>   reps   = 2
#>   lambda = 0.100
#>   n_train = 140
pred <- predict(fit, emb[te, ])

# The only number that matters is next to the achievable null --
# predicting the training mean at every unseen pixel.
c(qf_krr = edaphos_rmse(y[te], pred),
  train_mean = edaphos_rmse(y[te], rep(mean(y[tr]), length(te))))
#>     qf_krr train_mean 
#>   7.449385   7.208675 
# 7.45 vs 7.21 g/kg: the fit is WORSE than the mean, and
edaphos_r2(y[te], pred)                       # -0.074, i.e. < 0
#> [1] -0.07443565

# Two diagnostics that have to be read side by side to see why.
# In sample the fit is near-perfect; out of sample its predictions
# barely move off the training mean.  With a 6-qubit Gram matrix
# this close to the identity (see qf_kernel_compare()), KRR can
# only memorise: every test pixel is near-orthogonal to every
# training pixel, so the kernel expansion contributes ~ nothing
# and prediction falls back on the intercept.
c(rmse_in_sample = fit$fit$rmse,              # 0.63
  rmse_held_out  = edaphos_rmse(y[te], pred)) # 7.45
#> rmse_in_sample  rmse_held_out 
#>      0.6322467      7.4493853 
c(sd_pred = sd(pred), sd_truth = sd(y[te]))   # 1.11 vs 7.25
#>  sd_pred sd_truth 
#> 1.113525 7.247360 

# Fewer qubits concentrate less, but do not rescue it: over
# n_pcs 3-6, reps 1-2 and lambda 1e-3..1 the best held-out R2
# this fixture produced was 0.012 -- the training mean, again.
fit4 <- qf_krr_fit(emb[tr, ], y[tr], n_pcs = 4L, reps = 2L,
                   lambda = 1)
edaphos_r2(y[te], predict(fit4, emb[te, ]))   # 0.012
#> [1] 0.01240346

# Trap in predict(): the PCA centre, rotation and pi-rescale all
# come from the TRAINING rows, so a held-out pixel can encode
# outside the [-pi, pi] the feature map was scaled for.  Nothing
# errors and nothing warns -- the encoding just extrapolates, and
# the stored bounds are the only way to notice:
rng <- range(fit$reduction$range_min, fit$reduction$range_max)
rng                              # training PC span, pre-rescale
#> [1] -8.441388  8.382292

# Keep column names on newdata as well: an unnamed matrix against
# a named training embedding falls back to positional alignment
# and warns "NAs introduced by coercion".
```
