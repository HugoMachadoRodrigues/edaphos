# Reduce foundation-model embeddings to PCs and scale to quantum range

Takes a matrix of per-observation foundation embeddings and returns the
top-`n_pcs` principal components rescaled into `[-pi, pi]`, the natural
input range of the ZZFeatureMap. Zero-variance columns are dropped
before PCA. The rotation and scaling are stored on the return object so
new observations can be projected identically.

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
