# Train a tiny DDPM on a collection of soil-map patches

Train a tiny DDPM on a collection of soil-map patches

## Usage

``` r
dm_fit(
  stack,
  conditioning = NULL,
  T = 50L,
  epochs = 100L,
  hidden = 32L,
  lr = 0.01,
  seed = NULL,
  backend = c("auto", "r", "torch"),
  device = c("cpu", "mps", "cuda")
)
```

## Arguments

- stack:

  A 3-D array of shape `(n_patches, H, W)` of soil- property patches
  (e.g. SOC at each pixel, already standardised to zero mean / unit
  variance).

- conditioning:

  Optional matrix of shape `(n_patches, cond_dim)` giving a per-patch
  covariate summary fed to the denoising network as conditioning.
  Default `NULL`.

- T:

  Integer; number of diffusion timesteps.

- epochs:

  Integer; training epochs.

- hidden:

  Integer; hidden width of the denoising MLP.

- lr:

  Numeric; learning rate.

- seed:

  Optional RNG seed.

- backend:

  One of `"auto"` (default), `"torch"` or `"r"`. `"auto"` uses the torch
  U-Net denoiser when a working libtorch is present and otherwise falls
  back to the pure-R path. The pure-R denoiser is an **uncalibrated
  reference**: its samples are over-dispersed and spatially incoherent
  (see the Pillar 9 vignette), so publication figures must use
  `"torch"`. The R path emits a one-time note when used.

- device:

  `"cpu"` (default), `"mps"`, or `"cuda"` when `backend = "torch"`.

## Value

An `edaphos_dm_fit` fit.

## References

Ho, J., Jain, A. and Abbeel, P. (2020). Denoising Diffusion
Probabilistic Models. *Advances in Neural Information Processing
Systems* **33**, 6840-6851.

Nichol, A. Q. and Dhariwal, P. (2021). Improved Denoising Diffusion
Probabilistic Models. *Proceedings of the 38th International Conference
on Machine Learning* **139**, 8162-8171.

Huang, G.-B., Zhu, Q.-Y. and Siew, C.-K. (2006). Extreme learning
machine: Theory and applications. *Neurocomputing* **70**, 489-501.
[doi:10.1016/j.neucom.2005.12.126](https://doi.org/10.1016/j.neucom.2005.12.126)
(the random-hidden-layer regime the `backend = "r"` trainer operates
in).

## Examples

``` r
# \donttest{
data(br_cerrado)

# br_cerrado is a 45 x 45 grid, so it reshapes into an image.  Model
# `twi`: a generative model can only learn structure the field
# actually has, and `soc` in this grid carries far less short-range
# structure than `twi` does.
as_grid <- function(v) {
  ux <- sort(unique(br_cerrado$x)); uy <- sort(unique(br_cerrado$y))
  m <- matrix(NA_real_, 45L, 45L)
  m[cbind(match(br_cerrado$x, ux), match(br_cerrado$y, uy))] <- v
  m
}
lag1 <- function(z) (cor(as.vector(z[, -ncol(z)]), as.vector(z[, -1])) +
                     cor(as.vector(z[-nrow(z), ]), as.vector(z[-1, ]))) / 2
round(c(soc = lag1(as_grid(br_cerrado$soc)),
        twi = lag1(as_grid(br_cerrado$twi))), 3)
#>   soc   twi 
#> 0.230 0.785 

field  <- as_grid(br_cerrado$twi)
field  <- (field - mean(field)) / sd(field)
starts <- seq(1L, 38L, by = 5L)
cells  <- expand.grid(r = starts, c = starts)
stack  <- array(0, dim = c(nrow(cells), 8L, 8L))
for (i in seq_len(nrow(cells)))
  stack[i, , ] <- field[cells$r[i]:(cells$r[i] + 7L),
                        cells$c[i]:(cells$c[i] + 7L)]

# `backend = "r"` is PINNED, and that is not a performance choice.
# Everything this example says is about the reference backend: it is
# what CRAN runs (libtorch is not installed there) and what the
# commentary below describes. Left unpinned, the backend defaults to
# torch wherever libtorch happens to exist, and the printed output
# then contradicts the prose around it -- the draws in `dm_sample`'s
# example go from 5.4x over-dispersed to 1.1x, and their lag-1
# correlation from -0.06 to +0.61. An example whose narrative depends
# on the machine rendering it is not an example.
fit <- dm_fit(stack, T = 50L, epochs = 150L, hidden = 32L,
              lr = 0.02, seed = 1L, backend = "r")
fit
#> <edaphos_dm_fit>  (Pilar 9 -- Denoising Diffusion Probabilistic Model)
#>   patch shape : 8 x 8
#>   n_train     : 64   cond_dim = 0
#>   T (steps)   : 50   hidden = 32
#>   initial loss = 2.746  final loss = 0.9268

# The score-matching target is standard normal, so a denoiser that
# predicts nothing at all -- eps_theta == 0 -- scores exactly 1.
# That is what the training loss must be read against, and the gap
# here is small.
round(c(initial = fit$history[1L],
        final   = fit$history[length(fit$history)],
        eps_hat_zero = 1), 4)
#>      initial        final eps_hat_zero 
#>       2.7463       0.9268       1.0000 

# Nor does the gap close with training: `backend = "r"` fits a readout
# over frozen random features (an ELM), and that readout converges
# inside the first hundred epochs.  Read this as BLOCK MEANS, not as
# two single epochs: the loss is stochastic in the sampled timestep,
# and its epoch-to-epoch spread here (sd about 0.03) is comparable to
# the whole remaining improvement, so comparing epoch 150 against
# epoch 400 measures the noise.  This example used to do exactly that
# and reported the difference as "0.05"; measured, the two epochs it
# compared differ by -0.015 -- the later one is worse.
blk <- function(i) mean(fit$history[i])
round(c(epochs_51_100  = blk(51:100),
        epochs_101_150 = blk(101:150),
        noise_sd       = sd(fit$history[51:150])), 4)
#>  epochs_51_100 epochs_101_150       noise_sd 
#>         0.9884         0.9506         0.0341 

# A second fit is not needed to see this, and this example no longer
# runs one: training for longer does not change the epochs already
# taken, so a 400-epoch trace contains the 150-epoch trace as its
# prefix.  The second call cost 166 s of the example's 325 s.

# And the patches overlap by construction (stride 5, window 8), so
# these 64 are nowhere near 64 independent training examples.
c(n_patches = dim(stack)[1L], H = dim(stack)[2L], W = dim(stack)[3L])
#> n_patches         H         W 
#>        64         8         8 
# }
```
