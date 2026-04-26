# Graph-based causal discovery (Pilar 10 x Pilar 1)

Runs
[`causal_structure_learn()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_structure_learn.md)
on a feature frame augmented with GAT node embeddings. Returns the
discovered DAG restricted to the user's canonical variables; embeddings
act as nuisance conditioners that absorb spatial dependence the expert
DAG does not name.

## Usage

``` r
gnn_causal_discovery(
  gnn_fit,
  feature_frame,
  method = c("hc", "tabu", "pc-stable"),
  whitelist = NULL,
  blacklist = NULL,
  n_emb_cols = NULL,
  bootstrap = FALSE,
  R_boot = 100L,
  seed = NULL
)
```

## Arguments

- gnn_fit:

  An `edaphos_gnn_gat` from
  [`gnn_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_fit.md).

- feature_frame:

  Data frame of the actual variables to form the DAG over. Must have the
  same number of rows as the graph on which `gnn_fit` was trained.

- method:

  Passed to
  [`causal_structure_learn()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_structure_learn.md);
  default `"hc"`.

- whitelist, blacklist:

  Optional edge constraints (see
  [`causal_structure_learn()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_structure_learn.md)).

- n_emb_cols:

  Integer; how many GAT embedding dimensions to use as conditioners.
  Default `min(8, emb_dim)` to keep the search space manageable.

- bootstrap:

  Logical; pass to
  [`causal_structure_learn()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_structure_learn.md).

- R_boot:

  Integer; bootstrap resamples.

- seed:

  Optional RNG seed.

## Value

An `edaphos_causal_kg` from the underlying structure-learn call,
restricted to edges between variables in `feature_frame`.
