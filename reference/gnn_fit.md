# Fit a Graph Attention Network on a WoSIS-style co-location graph

Fit a Graph Attention Network on a WoSIS-style co-location graph

## Usage

``` r
gnn_fit(
  graph,
  targets,
  hidden = 16L,
  n_heads = 4L,
  n_layers = 2L,
  epochs = 200L,
  lr = 0.01,
  seed = NULL,
  backend = c("r", "torch"),
  device = c("cpu", "mps", "cuda")
)
```

## Arguments

- graph:

  An `edaphos_gnn_graph` from
  [`gnn_build_graph()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_build_graph.md).

- targets:

  Numeric vector, one value per node.

- hidden:

  Integer; output dimension of each GAT layer. Default `16L`.

- n_heads:

  Integer; number of attention heads. Default `4L`.

- n_layers:

  Integer; number of stacked GAT layers. Default `2L`.

- epochs:

  Integer; training epochs for the final linear head.

- lr:

  Numeric; learning rate.

- seed:

  RNG seed.

- backend:

  `"r"` (default, ELM-style) or `"torch"` (full autograd with multi-head
  attention; requires the `torch` Suggests dependency). v2.7.0 upgrade.

- device:

  `"cpu"` (default), `"mps"`, or `"cuda"` when `backend = "torch"`.

## Value

An `edaphos_gnn_gat` fit.
