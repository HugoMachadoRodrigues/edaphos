# Quantum KRR over GAT node embeddings (Pilar 6 x Pilar 10)

Thin composition: take the GAT embedding matrix, PCA-reduce to `n_pcs`,
feed to
[`quantum_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_fit.md).
Returns a combined fit object that
[`predict()`](https://rdrr.io/r/stats/predict.html) unwraps by
projecting new embeddings through the stored rotation.

## Usage

``` r
qf_krr_on_gat_embeddings(gnn_fit, y, n_pcs = 6L, reps = 2L, lambda = 0.5)
```

## Arguments

- gnn_fit:

  An `edaphos_gnn_gat` fit.

- y:

  Numeric response (one per training node).

- n_pcs:

  Integer; number of PCs (= qubits). Default `6L`.

- reps:

  ZZFeatureMap repetitions. Default `2L`.

- lambda:

  Ridge regulariser. Default `0.5`.

## Value

An `edaphos_qf_krr_gat` fit.
