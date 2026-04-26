# Quantum kernel Gram matrix via ZZFeatureMap overlap

Computes the Havlicek-et-al. quantum kernel \$\$K(\mathbf{x}\_i,
\mathbf{x}\_j) \\=\\ \bigl\|\langle \phi(\mathbf{x}\_j) \mid
\phi(\mathbf{x}\_i)\rangle\bigr\|^2\$\$ over one or two datasets whose
rows are feature vectors in `[0, pi]` (see
[`quantum_scale()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_scale.md)).
The result is a positive semi-definite matrix with ones on the diagonal.

## Usage

``` r
quantum_kernel(X, Y = NULL, reps = 2L, backend = c("rcpp", "r"))
```

## Arguments

- X:

  Numeric matrix or data frame (rows = samples, columns = features).
  Features are mapped 1-1 to qubits; the number of qubits equals
  `ncol(X)`. The current pure-R simulator scales to about 8 qubits
  comfortably.

- Y:

  Optional numeric matrix / data frame with the same number of columns
  as `X`. When `NULL` (default), the symmetric Gram matrix `K(X, X)` is
  returned.

- reps:

  Integer encoding depth — forwarded to
  [`quantum_feature_map()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_feature_map.md).

- backend:

  One of `"rcpp"` (default, 10-50x faster; requires the package to be
  properly installed so the compiled code is available) or `"r"` (pure-R
  reference implementation, kept for audit and fallback).

## Value

Numeric matrix with `nrow(X)` rows and `nrow(Y %||% X)` columns; all
values lie in `[0, 1]`.

## References

Havlicek, V. et al. (2019). Supervised learning with quantum-enhanced
feature spaces. *Nature* **567**, 209-212.

## Examples

``` r
set.seed(1)
X <- matrix(runif(20, 0, pi), nrow = 5)
K <- quantum_kernel(X, reps = 2L)
stopifnot(isSymmetric(K))
stopifnot(all(abs(diag(K) - 1) < 1e-8))
```
