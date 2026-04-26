# Node-level embeddings from a fitted GAT

Node-level embeddings from a fitted GAT

## Usage

``` r
gnn_embed(object)
```

## Arguments

- object:

  An `edaphos_gnn_gat` fit.

## Value

An `(n, hidden * n_heads)` matrix – one row per node.
