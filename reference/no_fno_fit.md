# Fit a 1-D Fourier Neural Operator for depth-profile operators

Learns the solution map `u(z) -> y(z)` from a collection of (covariate
trajectory, target profile) pairs. The trained operator predicts the
depth profile at new sites without re-fitting.

## Usage

``` r
no_fno_fit(
  depths,
  targets,
  covariates,
  n_modes = 4L,
  width = 8L,
  n_blocks = 2L,
  epochs = 200L,
  lr = 0.01,
  seed = NULL,
  backend = c("auto", "r", "torch"),
  device = c("cpu", "mps", "cuda")
)
```

## Arguments

- depths:

  Numeric vector of depths (common grid, length `n_depths`). Depth must
  be equally spaced for the DFT to be exact; if not equally spaced, the
  implementation falls back to a FFT on the reindexed series.

- targets:

  Matrix of observed profile values, shape `(n_obs, n_depths)`. Each row
  is one site.

- covariates:

  Matrix of depth-dependent covariate values, shape
  `(n_obs, n_depths, n_channels)` – the covariate trajectory that drives
  the operator. A 2-D matrix is accepted and treated as
  `n_channels = 1`.

- n_modes:

  Integer; number of Fourier modes retained in each spectral
  convolution. Default `4L`.

- width:

  Integer; number of latent channels. Default `8L`.

- n_blocks:

  Integer; number of FNO blocks. Default `2L`.

- epochs:

  Integer; SGD epochs.

- lr:

  Learning rate.

- seed:

  RNG seed.

- backend:

  One of `"auto"` (default), `"torch"` or `"r"`. `"auto"` uses the
  trained torch operator when a working libtorch is present and
  otherwise falls back to the pure-R path. The pure-R path is a
  **frozen-spectral random-feature reference** that does not learn the
  operator (near-zero skill); it exists for illustration and torch-less
  checks, and emits a one-time note when used. Use `"torch"` for the
  trained Fourier Neural Operator (full autograd via
  [`torch::optim_adam`](https://torch.mlverse.org/docs/reference/optim_adam.html)).

- device:

  `"cpu"` (default), `"mps"` (Apple Silicon) or `"cuda"` when
  `backend = "torch"`.

## Value

An `edaphos_no_fno` fit.

## References

Li, Z., Kovachki, N., Azizzadenesheli, K., Liu, B., Bhattacharya, K.,
Stuart, A. and Anandkumar, A. (2021). Fourier Neural Operator for
Parametric Partial Differential Equations. *International Conference on
Learning Representations*.

Kovachki, N., Li, Z., Liu, B., Azizzadenesheli, K., Bhattacharya, K.,
Stuart, A. and Anandkumar, A. (2023). Neural Operator: Learning Maps
Between Function Spaces With Applications to PDEs. *Journal of Machine
Learning Research* **24**, 1-97.

## Examples

``` r
set.seed(11)
depths <- seq(5, 150, length.out = 8L)

# A profile bank whose operator is KNOWN: the Pilar 2 pedogenetic
# ODE solution, with its four parameters driven by site covariates.
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

# The FNO consumes a (sites, depths, channels) cube; static site
# covariates are broadcast along the depth axis.
cube <- function(x) {
  a <- array(0, dim = c(nrow(x), length(depths), ncol(x)))
  for (j in seq_len(ncol(x))) a[, , j] <- x[, j]
  a
}
tr <- 1:30; te <- 31:50
fno <- no_fno_fit(depths, soc[tr, ], cube(site[tr, ]),
                  n_modes = 4L, width = 8L, n_blocks = 1L,
                  epochs = 20L, lr = 0.05, seed = 1L)
#> [no_fno_fit] backend = 'r' is a frozen-spectral random-feature reference and does NOT learn the operator; use backend = 'torch' (the default when libtorch is present) for the trained Fourier Neural Operator.
fno
#> <edaphos_no_fno>  (Pilar 8 -- Fourier Neural Operator)
#>   n_depths = 8   n_modes = 4   width = 8   blocks = 1
#>   n_train  = 30   C_in = 3
#>   initial MSE = 0.9664  final MSE = 0.9598

# Read that MSE against the only baseline that matters.  Targets are
# standardised PER DEPTH, so predicting the mean profile scores
# exactly 1 -- and 20 epochs have moved 4 percent off it.
round(c(initial = fno$history[1L],
        final   = fno$history[length(fno$history)],
        mean_profile = 1), 4)
#>      initial        final mean_profile 
#>       0.9664       0.9598       1.0000 

# Same story on held-out sites, and it vanishes if you score against
# the GRAND mean: that null does not know the shape of an average
# profile, so +0.85 is mostly "carbon decreases with depth".
pred <- predict(fno, cube(site[te, ]))
null_prof <- matrix(colMeans(soc[tr, ]), length(te), length(depths),
                    byrow = TRUE)
round(c(rmse_fno  = sqrt(mean((pred - soc[te, ])^2)),
        rmse_null = sqrt(mean((null_prof - soc[te, ])^2)),
        nse_vs_mean_profile = 1 - sum((pred - soc[te, ])^2) /
                                  sum((soc[te, ] - null_prof)^2),
        nse_vs_grand_mean   = 1 - sum((pred - soc[te, ])^2) /
                                  sum((soc[te, ] - mean(soc[tr, ]))^2)), 4)
#>            rmse_fno           rmse_null nse_vs_mean_profile   nse_vs_grand_mean 
#>              1.6693              1.6746              0.0063              0.8517 

# Why so weak: with backend = "r" the lift and the spectral
# multipliers stay at their random initialisation, and of the
# decoder only the weights move -- not even its bias.  That is an
# ELM regime, and a one-epoch fit proves it.
fno1 <- no_fno_fit(depths, soc[tr, ], cube(site[tr, ]),
                   n_modes = 4L, width = 8L, n_blocks = 1L,
                   epochs = 1L, lr = 0.05, seed = 1L)
c(lift_frozen     = identical(fno1$W_in, fno$W_in),
  spectral_frozen = identical(fno1$R_list, fno$R_list),
  bias_frozen     = identical(fno1$b_out, fno$b_out),
  decoder_trained = !identical(fno1$W_out, fno$W_out))
#>     lift_frozen spectral_frozen     bias_frozen decoder_trained 
#>            TRUE            TRUE            TRUE            TRUE 
c(trained_weights = length(fno$W_out))
#> trained_weights 
#>               8 

# predict() takes no `newdepths`: an FNO fit is tied to its training
# grid.  A cube with a different depth extent is silently RECYCLED
# into that grid (with a warning) rather than rejected, so check the
# shape of what you pass -- the result looks perfectly normal.
short <- array(0, dim = c(length(te), 6L, 3L))
for (j in 1:3) short[, , j] <- site[te, j]
dim(suppressWarnings(predict(fno, short)))
#> [1] 20  8
```
