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

## Examples

``` r
set.seed(1)
sub <- br_cerrado[sample(nrow(br_cerrado), 150L), ]
names(sub)[names(sub) == "x"] <- "lon"
names(sub)[names(sub) == "y"] <- "lat"
g <- gnn_build_graph(sub, k = 6L,
                     feature_cols = c("elev", "slope", "twi",
                                      "map_mm", "ndvi"))

# Pillar 10 transductively: the graph spans all 150 pixels, the
# regression head sees only the first 100 SOC labels.
tr <- 1:100; te <- 101:150
y_obs <- sub$soc; y_obs[te] <- NA
gat <- gnn_fit(g, y_obs, hidden = 8L, n_heads = 2L, n_layers = 1L,
               epochs = 40L, seed = 1L)
c(gat        = edaphos_rmse(sub$soc[te], predict(gat)[te]),
  train_mean = edaphos_rmse(sub$soc[te], rep(mean(sub$soc[tr]), 50)))
#>        gat train_mean 
#>   4.740551   6.271455 
# 4.77 vs 6.27 g/kg -- the GAT is ahead of the null it must beat

# Now the hand-off, and the first thing it demands: one y per NODE.
# There is no train_mask here, so the quantum KRR is fitted on all
# 150 labels, including the 50 the GAT was never shown.
qk <- qf_krr_on_gat_embeddings(gat, sub$soc, n_pcs = 5L, reps = 1L,
                               lambda = 0.5)
qk
#> <edaphos_qf_krr_gat>  (Pilar 6 x Pilar 10)
#>   GAT emb_dim   : 8
#>   qubits (PCs)  : 5
#>   reps          : 1   lambda = 0.5
#>   n_train       : 150
c(nodes = nrow(gat$emb), gat_trained_on = gat$n_train,
  krr_trained_on = qk$n_train)                    # 150, 100, 150
#>          nodes gat_trained_on krr_trained_on 
#>            150            100            150 

# Which makes every number the returned object can produce an
# in-sample one.  This looks held out and is not:
edaphos_rmse(sub$soc[te], predict(qk, newdata = gat$emb[te, ]))  # 2.93
#> [1] 2.761911
edaphos_rmse(sub$soc, predict(qk))   # 2.73, predict() with no
#> [1] 2.666344
                                     # newdata scores the training
                                     # embeddings

# The honest version: same embedding, KRR refitted on the 100 rows
# the GAT actually trained on, read against the training mean.
qk_tr <- qf_krr_fit(gat$emb[tr, ], sub$soc[tr], n_pcs = 5L,
                    reps = 1L, lambda = 0.5)
p <- predict(qk_tr, gat$emb[te, ])
c(qf_krr     = edaphos_rmse(sub$soc[te], p),
  train_mean = edaphos_rmse(sub$soc[te], rep(mean(sub$soc[tr]), 50)),
  r2         = edaphos_r2(sub$soc[te], p))
#>     qf_krr train_mean         r2 
#>  6.5263153  6.2714550 -0.1192319 
# 6.32, 6.27, -0.049: worse than predicting the mean everywhere.
# The GAT embedding the bridge feeds the ZZFeatureMap is 8-dim and
# nearly rank-2 -- the first two PCs hold 94 % of its variance --
# so five qubits are encoding almost no independent directions.
round(qk$reduction$variance_explained, 3)
#>   PC1   PC2   PC3   PC4   PC5 
#> 0.622 0.324 0.040 0.013 0.002 
```
