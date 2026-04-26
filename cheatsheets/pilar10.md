# Pilar 10 — Graph Attention Networks

Profiles as nodes, k-NN co-location adjacency as edges, attention-
weighted message passing for node-level regression.

## Core API

```r
# Build a k-NN co-location graph from a profile frame
g <- gnn_build_graph(
  profiles     = df_with_lon_lat,
  k            = 8L,
  feature_cols = c("elev", "slope", "twi", "map_mm")
)
g$features      # (n, d_in) z-scored node features
g$edge_index    # (n_edges, 2): src, dst
g$edge_weight   # inverse-distance softmax-normalised per source

# Train a 2-layer GAT with multi-head attention (v3.6.0 sparse path)
fit <- gnn_fit(
  graph     = g,
  targets   = df$soc,
  hidden    = 16L, n_heads = 4L, n_layers = 2L,
  epochs    = 200L, lr = 0.01,
  backend   = "r",        # or "torch" (full autograd)
  seed = 1L
)

# Read out node embeddings + predictions
emb <- gnn_embed(fit)            # (n, hidden * n_heads)
pr  <- predict(fit)              # length-n vector on the native scale
```

## v3.0.0 bridges

* `gnn_causal_discovery()` (P10 × P1) — augment causal-discovery
  feature frame with GAT embeddings as nuisance conditioners.
* `qf_krr_on_gat_embeddings()` (P10 × P6) — quantum KRR over PCA-
  reduced GAT embeddings.

## v3.6.0 sparse implementation

`.gnn_gat_layer()` uses `Matrix::sparseMatrix` for edge aggregation;
~6x faster than the v2.6.0 per-node loop at n = 500.

## Key references

* Velickovic et al. (2018) — Graph Attention Networks.
* Kipf & Welling (2017) — Graph Convolutional Networks.

## See also

* `cheatsheets/pilar1.md` — `gnn_causal_discovery()` bridge.
* `cheatsheets/pilar6.md` — `qf_krr_on_gat_embeddings()` bridge.
