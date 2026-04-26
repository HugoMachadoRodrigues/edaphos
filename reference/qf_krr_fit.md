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
