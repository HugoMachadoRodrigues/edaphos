# Benchmark wrapper: Pilar 10 – GAT seed-ensemble on k-NN graph

Builds a joint k-NN co-location graph on `rbind(train, test)` using
(lon, lat) for adjacency and `cov_cols` as node features, then fits
`n_ensemble` independent GAT regressors with different seeds, and
harvests predictions at the test nodes. Predictive posterior is the seed
ensemble.

## Usage

``` r
benchmark_fit_p10_gat(
  train,
  test,
  cov_cols,
  k = 8L,
  hidden = 12L,
  n_heads = 2L,
  n_layers = 2L,
  epochs = 100L,
  lr = 0.03,
  n_ensemble = 10L,
  seed = 1L,
  calibrate = TRUE
)
```

## Arguments

- train, test:

  Data frames with `soc`, `lon`, `lat`, and `cov_cols`.

- cov_cols:

  Character vector of covariate columns used as node features.

- k:

  Integer; k-NN degree of the co-location graph.

- hidden, n_heads, n_layers:

  Architecture. See
  [`gnn_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_fit.md).

- epochs, lr:

  Training hyperparameters.

- n_ensemble:

  Integer; number of seed-distinct fits.

- seed:

  Base RNG seed (each member uses `seed + b`).

- calibrate:

  Logical (default `TRUE`). When `TRUE`, residual noise from a
  representative full-data GAT fit is injected on every posterior sample
  (see Pilar-1 wrapper for the rationale).

## Value

An `edaphos_posterior` with `method = "ensemble"`, `query_type = "map"`.
