# Reduce foundation-model embeddings to PCs and scale to quantum range

Takes a matrix of per-observation foundation embeddings and returns the
top-`n_pcs` principal components rescaled into `[-pi, pi]`.
Zero-variance columns are dropped before PCA. The rotation and scaling
are stored on the return object so new observations can be projected
identically.

## Usage

``` r
qf_embed_reduce(embeddings, n_pcs = 8L)
```

## Arguments

- embeddings:

  Numeric matrix (obs x embedding-dim).

- n_pcs:

  Integer; number of PCs to retain. Default `8L` (the largest `n` for
  which
  [`quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_kernel.md)
  stays classically simulable on a laptop).

## Value

A list with components `X_q` (the PCs in `[-pi, pi]`, ready for
[`quantum_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_fit.md)),
`rotation`, `variance_explained`, `pca_center`, `pca_scale`, and
`range_min`/`range_max` used for the pi-rescale.

## Details

Note that `[-pi, pi]` is twice the `[0, pi]` interval that
[`quantum_scale()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_scale.md)
produces and that
[`quantum_feature_map()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_feature_map.md)
and
[`quantum_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_fit.md)
document as the ZZFeatureMap's input range. The wider interval doubles
the entangling phase \\2(\pi - x_i)(\pi - x_j)\\, pushing it several
times past the `4 * pi` period of the `Rz` gate; the examples measure
what that costs.

## Examples

``` r
# A stand-in for a MoCo v2 patch encoder: 64 columns built by a
# fixed random projection of five Cerrado covariates through a
# tanh, plus noise.  Wide but low-rank, like a real encoder's
# output -- and cheap enough to run here.
set.seed(42)
covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
sub  <- br_cerrado[sample(nrow(br_cerrado), 200L), ]
Z    <- scale(as.matrix(sub[, covs]))
W    <- matrix(rnorm(5L * 64L), 5L, 64L)
emb  <- tanh(Z %*% W) + matrix(rnorm(200L * 64L, 0, 0.1), 200L, 64L)

red <- qf_embed_reduce(emb, n_pcs = 6L)
dim(red$X_q)                       # 200 x 6: one column per qubit
#> [1] 200   6
round(red$variance_explained, 3)   # .358 .269 .183 .060 .041 .015
#>   PC1   PC2   PC3   PC4   PC5   PC6 
#> 0.358 0.269 0.183 0.060 0.041 0.015 

# Trap: every PC is stretched to the SAME [-pi, pi] range, so
# QPC_6 -- 1.5% of the variance, mostly noise -- reaches the
# feature map at the amplitude QPC_1 gets for its 36%.  The PCA
# ordering does not survive the rescale:
round(apply(red$X_q, 2, sd), 2)    # 1.79 1.67 1.47 1.13 1.27 1.38
#> QPC_1 QPC_2 QPC_3 QPC_4 QPC_5 QPC_6 
#>  1.79  1.67  1.47  1.13  1.27  1.38 

# n_pcs IS the qubit count, and the simulator carries one state
# vector of length 2^n_pcs per sample, so the work behind every
# Gram entry doubles with each extra PC.
length(quantum_feature_map(rep(0, 6)))    # 64
#> [1] 64
length(quantum_feature_map(rep(0, 12)))   # 4096
#> [1] 4096

# The interval is not cosmetic.  Mapping the same PCs onto
# [0, pi] -- what quantum_scale() would have produced -- halves
# the ZZ phase and leaves visibly more off-diagonal kernel mass,
# i.e. a Gram matrix less collapsed onto the identity.
Kw <- quantum_kernel(red$X_q[1:60, ], reps = 2L)
Kn <- quantum_kernel((red$X_q[1:60, ] + pi) / 2, reps = 2L)
c(range_2pi = mean(Kw[upper.tri(Kw)]),
  range_pi  = mean(Kn[upper.tri(Kn)]))    # 0.0153 vs 0.0189
#>  range_2pi   range_pi 
#> 0.01531711 0.01893714 
```
