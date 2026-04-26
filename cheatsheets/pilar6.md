# Pilar 6 — Quantum ML (ZZFeatureMap KRR)

Pure-R state-vector simulator of the ZZFeatureMap (Havlicek et al.
2019) + a closed-form quantum kernel ridge regression.

## Core API

```r
# Pre-scale features to [-pi, pi]
X <- quantum_scale(my_matrix)

# Quantum kernel Gram matrix
K <- quantum_kernel(X, reps = 2L)
isSymmetric(K); all(eigen(K)$values >= -1e-8)  # PSD

# Quantum KRR (closed-form ridge in the quantum kernel)
fit <- quantum_krr_fit(X_train, y_train, reps = 2L, lambda = 0.5)
y_hat <- predict(fit, X_test)

# Foundation-quantum fusion: PCA-reduce embeddings, then KRR
qf <- qf_krr_fit(
  embeddings = my_emb_matrix,
  y          = my_y,
  n_pcs      = 8L, reps = 2L, lambda = 0.5
)
predict(qf, newdata = new_emb)

# Compare quantum vs RBF vs linear kernels at the same X
qf_kernel_compare(X_q = X, reps = 2L)
```

## v3.0.0 bridge: `qf_krr_on_gat_embeddings()` (Pilar 6 × Pilar 10)

PCA-reduce GAT node embeddings, then quantum KRR over the
PCA-projected embeddings.  See `cheatsheets/pilar10.md`.

## Rcpp port

`quantum_kernel_rcpp()` ships as a 12x speedup over the pure-R
state-vector simulator on n_qubits >= 6 (v2.1.3).

## Key references

* Havlicek et al. (2019) ZZFeatureMap.
* Schuld et al. (2021) — quantum kernel methods.

## See also

* `vignette("pilar6-quantum")` — full tutorial.
* `vignette("pilar4-pilar6-quantum")` — foundation-quantum bridge.
