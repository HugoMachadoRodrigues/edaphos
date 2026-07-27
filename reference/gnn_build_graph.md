# Build a k-NN co-location graph from a profile frame

Each profile is a node; each node connects to its `k` spatially nearest
neighbours via an inverse-distance-weighted edge. Returns an
`edaphos_gnn_graph` S3 object carrying the node-feature matrix, the
sparse adjacency (edge_index + edge_weight), and the spatial coordinates
used.

## Usage

``` r
gnn_build_graph(
  profiles,
  k = 8L,
  feature_cols = NULL,
  edges = c("spatial", "feature", "hybrid"),
  self_loops = TRUE
)
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

- edges:

  How neighbours are chosen. `"spatial"` (default) uses geographic k-NN;
  `"feature"` uses k-NN in standardised covariate space; `"hybrid"` is
  the union of both.

  Which one is best is not obvious, and the answer changed once the
  model was fixed. Under spatially blocked validation a purely spatial
  graph connects a held-out node almost exclusively to other held-out
  nodes (measured on the Cerrado benchmark folds: 99.9 % of a node's 8
  nearest geographic neighbours are also held out, against 73.7 % for
  feature-space edges). While the regression head was trained by
  gradient descent and a profile's own covariates reached the readout
  only through the smoothing aggregation, that starved the network and
  feature-space edges were clearly better. With the closed-form readout
  and the input skip (`readout_skip = TRUE`) a node already has direct
  access to its own covariates, and the spatial neighbourhood then
  contributes the one thing it genuinely carries – spatial structure.

  Nested cross-validation on the Cerrado benchmark
  (`data-raw/pilar10_gat_tuning.R`, bundle
  `inst/extdata/pilar10_gat_tuning.rds`) selected `"spatial"` in 3 of 5
  outer folds and `"hybrid"` in the other 2, never `"feature"` – and the
  selection never saw the evaluated folds. Hence `"spatial"` is the
  default. Treat the choice as a hyperparameter and tune it: none of the
  three dominates.

- self_loops:

  Logical; add an edge from every node to itself. Default `TRUE`. k-NN
  never returns a node as its own neighbour, so without a self-loop the
  aggregation builds each node's representation purely from OTHER
  profiles and a profile's own covariates never reach its own
  prediction. Graphs built before this argument existed had no
  self-loops.

## Value

An `edaphos_gnn_graph` list with `features`, `edge_index`,
`edge_weight`, `coords`, `feature_names`.
