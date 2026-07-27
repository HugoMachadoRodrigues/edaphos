# Seed ensemble of GAT fits

Fits `n_ensemble` independent GATs that differ only in their random seed
– which drives the attention initialisation and the internal validation
split – and averages their predictions.

## Usage

``` r
gnn_fit_ensemble(
  graph,
  targets,
  train_mask = NULL,
  n_ensemble = 10L,
  seed = NULL,
  ...
)
```

## Arguments

- graph:

  An `edaphos_gnn_graph` from
  [`gnn_build_graph()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_build_graph.md).

- targets:

  Numeric vector, one value per node.

- train_mask:

  Optional logical vector of length `graph$n` selecting the nodes whose
  target is observed. The graph is used in full for message passing, but
  the regression head is fitted – and the targets are standardised – on
  these nodes only. Defaults to `!is.na(targets)`, so held-out nodes can
  simply be passed as `NA` rather than given an invented value.

- n_ensemble:

  Integer; number of members. Default `10L`.

- seed:

  RNG seed.

- ...:

  Further arguments passed to
  [`gnn_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_fit.md)
  for every member – `hidden`, `n_heads`, `n_layers`, `epochs`, `lr`,
  `weight_decay`, `residual`, `average_heads`, `readout_skip`,
  `val_frac`, `backend`, `device`. Members differ only in their seed.

## Value

An `edaphos_gnn_ensemble` carrying the member fits, the averaged node
predictions, and the between-member standard deviation (a cheap
epistemic spread).

## Details

A single GAT is one model; a quantile regression forest is an ensemble
of hundreds of trees. Comparing the two directly measures the ensembling
as much as the method, so a fair head-to-head gives the network an
ensemble too. Averaging also damps the run-to-run variance that a single
gradient-trained fit carries on datasets of this size.
