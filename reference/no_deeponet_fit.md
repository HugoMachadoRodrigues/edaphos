# Fit a DeepONet for depth-profile operators

Fit a DeepONet for depth-profile operators

## Usage

``` r
no_deeponet_fit(
  depths,
  targets,
  covariates,
  branch_hidden = 16L,
  trunk_hidden = 16L,
  output_dim = 8L,
  epochs = 300L,
  lr = 0.02,
  seed = NULL,
  backend = c("auto", "r", "torch"),
  device = c("cpu", "mps", "cuda")
)
```

## Arguments

- depths:

  Numeric vector of depths (length `n_depths`).

- targets:

  Matrix of targets, shape `(n_obs, n_depths)`.

- covariates:

  Matrix of per-site summary covariates, shape `(n_obs, p)` – NOT a
  depth-dependent trajectory; each site is represented by a vector of
  static covariates. This is the canonical DeepONet setup where the
  branch input is a fixed- length vector.

- branch_hidden, trunk_hidden:

  Integer hidden sizes for the branch and trunk MLPs.

- output_dim:

  Integer; dimension of the inner-product space (`p` in the notes
  above).

- epochs, lr:

  Training hyperparameters.

- seed:

  RNG seed.

- backend:

  One of `"auto"` (default; torch when libtorch is present, else
  pure-R), `"torch"` (full autograd), or `"r"`. The pure-R path freezes
  the branch/trunk hidden layers and trains a random-feature readout —
  it does learn, but is not the full DeepONet.

- device:

  `"cpu"`, `"mps"`, or `"cuda"` when `backend = "torch"`.

## References

Lu, L., Jin, P., Pang, G., Zhang, Z. and Karniadakis, G. E. (2021).
Learning nonlinear operators via DeepONet based on the universal
approximation theorem of operators. *Nature Machine Intelligence* **3**,
218-229.
[doi:10.1038/s42256-021-00302-5](https://doi.org/10.1038/s42256-021-00302-5)

Chen, T. and Chen, H. (1995). Universal approximation to nonlinear
operators by neural networks with arbitrary activation functions and its
application to dynamical systems. *IEEE Transactions on Neural Networks*
**6**, 911-917.
[doi:10.1109/72.392253](https://doi.org/10.1109/72.392253)

## Examples

``` r
set.seed(11)
depths <- seq(5, 150, length.out = 8L)

# The same known operator used in the no_fno_fit() example: the
# Pilar 2 pedogenetic ODE solution, driven by site covariates.
site <- cbind(clay   = runif(50L, 0.10, 0.60),
              map    = runif(50L, 0.80, 1.60),
              relief = runif(50L, 0.00, 1.00))
profile_of <- function(s, z) {
  y0  <- 20 + 25 * s[["clay"]];       yinf <- 2 + 6 * s[["map"]]
  lam <- 0.05 + 0.04 * s[["relief"]]; mu <- 0.02 + 0.01 * s[["clay"]]
  yinf + (y0 - yinf) * exp(-(lam / mu) * (1 - exp(-mu * z)))
}
soc <- t(apply(site, 1L, profile_of, z = depths)) +
       matrix(rnorm(400L, 0, 0.25), 50L, 8L)
tr <- 1:30; te <- 31:50

# The branch net takes a per-site covariate MATRIX -- not the depth
# cube no_fno_fit() wants -- and the trunk net takes the depth.
don <- no_deeponet_fit(depths, soc[tr, ], site[tr, ],
                       branch_hidden = 16L, trunk_hidden = 16L,
                       output_dim = 8L, epochs = 300L, lr = 0.02,
                       seed = 1L)
don
#> <edaphos_no_deeponet>  (Pilar 8 -- Deep Operator Network)
#>   branch 3x16 -> trunk 1x16, output_dim = 8
#>   n_train = 30   n_depths = 8
#>   initial MSE = 1.213  final MSE = 0.07538  (epochs = 300)

# Targets are standardised per depth, so the mean-profile predictor
# scores 1.  Unlike the FNO in the same setting, this one has
# genuinely learned most of the operator.
pred <- predict(don, site[te, ])
null_prof <- matrix(colMeans(soc[tr, ]), length(te), length(depths),
                    byrow = TRUE)
round(c(train_mse = don$history[length(don$history)],
        mean_profile = 1,
        test_rmse = sqrt(mean((pred - soc[te, ])^2)),
        nse_vs_mean_profile = 1 - sum((pred - soc[te, ])^2) /
                                  sum((soc[te, ] - null_prof)^2)), 4)
#>           train_mse        mean_profile           test_rmse nse_vs_mean_profile 
#>              0.0754              1.0000              0.5509              0.8918 

# The trunk accepts depths that were never in the training grid --
# the property a pointwise regressor cannot have.  Score those
# against the operator, with the interpolated training mean as null.
z_new <- c(12, 47, 88, 131)
truth <- t(apply(site[te, ], 1L, profile_of, z = z_new))
off   <- predict(don, site[te, ], newdepths = z_new)
null_new <- matrix(approx(depths, colMeans(soc[tr, ]), xout = z_new,
                          rule = 2)$y, length(te), length(z_new),
                   byrow = TRUE)
round(c(rmse = sqrt(mean((off - truth)^2)),
        nse  = 1 - sum((off - truth)^2) / sum((truth - null_new)^2)), 4)
#>   rmse    nse 
#> 0.8070 0.7985 

# Interpolating is not extrapolating.  Past the deepest training
# depth the per-depth un-standardisation constants are held FLAT
# (`rule = 2`) while the tanh trunk keeps drifting, so the AVERAGE
# profile still looks right at 300 cm while single sites are 1.4
# g/kg out -- an aggregate check would not catch it.
deep       <- predict(don, site[te, ], newdepths = c(200, 300))
truth_deep <- t(apply(site[te, ], 1L, profile_of, z = c(200, 300)))
round(c(mean_pred_300  = mean(deep[, 2]),
        mean_truth_300 = mean(truth_deep[, 2]),
        worst_site_err = max(abs(deep[, 2] - truth_deep[, 2]))), 3)
#>  mean_pred_300 mean_truth_300 worst_site_err 
#>          9.945          9.888          1.427 

# backend = "r" trains the second layer of each subnet; the first
# hidden layers stay at their random initialisation.
don1 <- no_deeponet_fit(depths, soc[tr, ], site[tr, ],
                        branch_hidden = 16L, trunk_hidden = 16L,
                        output_dim = 8L, epochs = 1L, lr = 0.02,
                        seed = 1L)
c(branch_hidden_frozen = identical(don1$W_b1, don$W_b1),
  trunk_hidden_frozen  = identical(don1$W_t1, don$W_t1),
  second_layer_trained = !identical(don1$W_b2, don$W_b2))
#> branch_hidden_frozen  trunk_hidden_frozen second_layer_trained 
#>                 TRUE                 TRUE                 TRUE 
```
