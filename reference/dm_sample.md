# Sample new soil-map patches from a trained DDPM

Ancestral sampling (Ho et al. 2020 Algorithm 2): start from Gaussian
noise at t=T, iteratively apply the denoising network to walk back to
t=0. Optional conditioning vector c is passed in at every step.

## Usage

``` r
dm_sample(fit, n_samples = 4L, conditioning = NULL, seed = NULL)
```

## Arguments

- fit:

  An `edaphos_dm_fit` from
  [`dm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_fit.md).

- n_samples:

  Integer; number of independent map draws.

- conditioning:

  Optional `(n_samples, cond_dim)` matrix. Default: zero vector for
  every sample (unconditional).

- seed:

  Optional RNG seed.

## Value

3-D array `(n_samples, H, W)` of generated patches.

## Examples

``` r
# \donttest{
data(br_cerrado)

as_grid <- function(v) {
  ux <- sort(unique(br_cerrado$x)); uy <- sort(unique(br_cerrado$y))
  m <- matrix(NA_real_, 45L, 45L)
  m[cbind(match(br_cerrado$x, ux), match(br_cerrado$y, uy))] <- v
  m
}
lag1 <- function(z) (cor(as.vector(z[, -ncol(z)]), as.vector(z[, -1])) +
                     cor(as.vector(z[-nrow(z), ]), as.vector(z[-1, ]))) / 2

field  <- as_grid(br_cerrado$twi)
field  <- (field - mean(field)) / sd(field)
starts <- seq(1L, 38L, by = 5L)
cells  <- expand.grid(r = starts, c = starts)
stack  <- array(0, dim = c(nrow(cells), 8L, 8L))
for (i in seq_len(nrow(cells)))
  stack[i, , ] <- field[cells$r[i]:(cells$r[i] + 7L),
                        cells$c[i]:(cells$c[i] + 7L)]

fit <- dm_fit(stack, T = 50L, epochs = 150L, hidden = 32L,
              lr = 0.02, seed = 1L)
gen <- dm_sample(fit, n_samples = 8L, seed = 7L)
dim(gen)
#> [1] 8 8 8

# "They look plausible" is not a result.  A generative model of a
# spatial field makes a checkable promise: the SPATIAL STATISTICS of
# its draws should match the data's.  Two numbers catch the usual
# failure modes, and they have to be read together.
stat <- function(a) c(sd = mean(apply(a, 1L, sd)),
                      lag1 = mean(apply(a, 1L, lag1)))
round(rbind(real = stat(stack), generated = stat(gen)), 3)
#>              sd   lag1
#> real      0.590  0.322
#> generated 3.169 -0.055

# The draws are five times over-dispersed AND spatially incoherent
# (lag-1 near zero against 0.32 in the data).  With `backend = "r"`
# the denoiser is a readout over frozen random features and has
# learned a marginal scale, not a landscape: these are not soil
# maps.  Use `backend = "torch"` for anything you would publish --
# and run this same two-number check on it rather than trusting it.

# `conditioning` is silently IGNORED when the fit was
# unconditional: cond_dim is 0, so there is no input for it to
# enter through, and the draws are bit-identical to the ones above.
same <- dm_sample(fit, n_samples = 8L,
                  conditioning = matrix(99, 8L, 1L), seed = 7L)
identical(same, gen)
#> [1] TRUE

# Conditioning has to be supplied at fit time, and its effect judged
# against the signal available.  Patch-mean elevation is nearly
# perfectly anti-correlated with patch-mean twi in this grid:
elev <- as_grid(br_cerrado$elev)
cond <- matrix(0, nrow(cells), 1L)
for (i in seq_len(nrow(cells)))
  cond[i, 1L] <- mean(elev[cells$r[i]:(cells$r[i] + 7L),
                           cells$c[i]:(cells$c[i] + 7L)])
cond[, 1L] <- as.vector(scale(cond[, 1L]))
round(cor(cond[, 1L], apply(stack, 1L, mean)), 3)
#> [1] -0.997

# ... and yet swinging the conditioner across 3 sd moves the sample
# mean by an eighth of the draw-to-draw spread, in the wrong
# direction.  Read it as a demonstration of the interface, not of a
# calibrated conditional simulator.
fit_c <- dm_fit(stack, conditioning = cond, T = 50L, epochs = 150L,
                hidden = 32L, lr = 0.02, seed = 1L)
lo <- dm_sample(fit_c, n_samples = 8L,
                conditioning = matrix(-1.5, 8L, 1L), seed = 3L)
hi <- dm_sample(fit_c, n_samples = 8L,
                conditioning = matrix(1.5, 8L, 1L), seed = 3L)
round(c(mean_low = mean(lo), mean_high = mean(hi),
        response = mean(hi) - mean(lo),
        draw_sd  = sd(apply(lo, 1L, mean))), 3)
#>  mean_low mean_high  response   draw_sd 
#>    -0.212    -0.180     0.032     0.260 
# }
```
