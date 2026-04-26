# Compare quantum, RBF, and linear kernels on the same feature set

Computes three Gram matrices on the same PCA-reduced embeddings and
reports their pairwise Frobenius distance and eigenvalue divergence.
Useful for understanding whether the quantum kernel is materially
different from the classical RBF at the same feature space (if not, the
quantum lift is cosmetic).

## Usage

``` r
qf_kernel_compare(X_q, reps = 2L, rbf_sigma = NULL)
```

## Arguments

- X_q:

  PCA-reduced, pi-scaled feature matrix (the `X_q` element of
  [`qf_embed_reduce()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_embed_reduce.md)).

- reps:

  Integer; ZZFeatureMap repetitions. Default `2L`.

- rbf_sigma:

  Numeric; RBF kernel bandwidth. If `NULL`, uses the median heuristic
  `median( || x_i - x_j || )` over the training set.

## Value

Named list with `K_quantum`, `K_rbf`, `K_linear`, and a `diagnostics`
data frame summarising pairwise distances + effective rank.
