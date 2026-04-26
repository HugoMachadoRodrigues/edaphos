# Build a k-NN co-location graph from a profile frame

Each profile is a node; each node connects to its `k` spatially nearest
neighbours via an inverse-distance-weighted edge. Returns an
`edaphos_gnn_graph` S3 object carrying the node-feature matrix, the
sparse adjacency (edge_index + edge_weight), and the spatial coordinates
used.

## Usage

``` r
gnn_build_graph(profiles, k = 8L, feature_cols = NULL)
```

## Arguments

- profiles:

  Data frame with numeric columns `lon`, `lat` and additional
  node-feature columns selected by `feature_cols`.

- k:

  Integer; number of nearest neighbours per node. Default `8L`.

- feature_cols:

  Character vector of column names to use as node features. Default:
  every numeric column except `lon`, `lat`.

## Value

An `edaphos_gnn_graph` list with `features`, `edge_index`,
`edge_weight`, `coords`, `feature_names`.
