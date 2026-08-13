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

## Examples

``` r
# Same stand-in MoCo encoder output as in qf_embed_reduce(), on
# 60 Cerrado pixels so the three Gram matrices stay 60 x 60.
set.seed(42)
covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
sub  <- br_cerrado[sample(nrow(br_cerrado), 60L), ]
Z    <- scale(as.matrix(sub[, covs]))
W    <- matrix(rnorm(5L * 64L), 5L, 64L)
emb  <- tanh(Z %*% W) + matrix(rnorm(60L * 64L, 0, 0.1), 60L, 64L)

cmp <- qf_kernel_compare(qf_embed_reduce(emb, n_pcs = 6L)$X_q)
names(cmp)          # K_quantum, K_rbf, K_linear, rbf_sigma, ...
#> [1] "K_quantum"   "K_rbf"       "K_linear"    "rbf_sigma"   "diagnostics"
cmp$diagnostics
#>                pair   frob effrank_quantum effrank_rbf effrank_linear
#> 1    quantum_vs_rbf 37.158           59.22        4.62           5.79
#> 2 quantum_vs_linear 62.070           59.22        4.62           5.79
#> 3     rbf_vs_linear 62.449           59.22        4.62           5.79

# Read that table carefully.  Only `pair` and `frob` vary by row;
# the three effrank_* columns are per-KERNEL and are repeated
# identically on all three rows.
nrow(unique(cmp$diagnostics[, c("effrank_quantum", "effrank_rbf")]))
#> [1] 1

# And effrank_quantum ~ 59 out of n = 60 is not evidence that the
# quantum kernel is richer than the RBF's ~ 4.6.  It is evidence
# that it is nearly the IDENTITY: at 6 qubits the ZZFeatureMap
# states are close to mutually orthogonal, so K -> I, whose
# entropy-based effective rank is exactly n.
frob <- function(A, B) sqrt(sum((A - B)^2))
c(to_identity = frob(cmp$K_quantum, diag(60)),   # 1.33
  to_rbf      = frob(cmp$K_quantum, cmp$K_rbf))  # 37.16
#> to_identity      to_rbf 
#>    1.325009   37.157898 

# The collapse is driven by the qubit count, not by `reps`.  Off-
# diagonal kernel mass roughly halves per PC added, while the RBF
# on the identical features holds at 0.61-0.63 throughout.
off <- function(K) mean(K[upper.tri(K)])
t(vapply(2:6, function(p) {
  k <- qf_kernel_compare(qf_embed_reduce(emb, n_pcs = p)$X_q)
  c(n_pcs = p, quantum = off(k$K_quantum), rbf = off(k$K_rbf))
}, numeric(3)))                  # quantum .314 .137 .065 .032 .016
#>      n_pcs    quantum       rbf
#> [1,]     2 0.31388334 0.6091690
#> [2,]     3 0.13679924 0.6297054
#> [3,]     4 0.06548216 0.6296694
#> [4,]     5 0.03222972 0.6262061
#> [5,]     6 0.01583906 0.6259345

# Deepening the circuit does not undo it -- `reps` leaves the
# off-diagonal mass where 6 qubits put it:
X6 <- qf_embed_reduce(emb, n_pcs = 6L)$X_q
vapply(c(1L, 2L, 4L), function(r)
  off(qf_kernel_compare(X6, reps = r)$K_quantum), numeric(1))
#> [1] 0.01622202 0.01583906 0.01610353

# A kernel that close to the identity gives kernel ridge nothing
# to interpolate with: see the qf_krr_fit() example, where the
# 6-PC fit reproduces its training set and then predicts the
# training mean everywhere else.
```
