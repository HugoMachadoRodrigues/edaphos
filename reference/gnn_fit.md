# Fit a Graph Attention Network on a WoSIS-style co-location graph

Fit a Graph Attention Network on a WoSIS-style co-location graph

## Usage

``` r
gnn_fit(
  graph,
  targets,
  train_mask = NULL,
  hidden = 16L,
  n_heads = 4L,
  n_layers = 2L,
  epochs = 200L,
  lr = 0.01,
  seed = NULL,
  weight_decay = 1e-04,
  residual = TRUE,
  average_heads = TRUE,
  readout_skip = TRUE,
  val_frac = 0.2,
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

- train_mask:

  Optional logical vector of length `graph$n` selecting the nodes whose
  target is observed. The graph is used in full for message passing, but
  the regression head is fitted – and the targets are standardised – on
  these nodes only. Defaults to `!is.na(targets)`, so held-out nodes can
  simply be passed as `NA` rather than given an invented value.

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

- weight_decay:

  Numeric; L2 penalty applied to the attention projections `W`. Default
  `1e-4`.

- residual:

  Logical; add a skip connection around each layer whose input and
  output widths match. Default `TRUE`.

- average_heads:

  Logical; average the attention heads on the output layer (the
  convention of Velickovic et al. 2018) instead of concatenating them.
  Default `TRUE`.

- readout_skip:

  Logical; concatenate the raw node features to the final embedding
  before the regression head, so the head sees a profile's own
  covariates un-smoothed as well as its neighbourhood summary. Default
  `TRUE`. With this off the graph layers must reconstruct the input
  through the aggregation, and a plain linear model on the same
  covariates can outperform the network.

- val_frac:

  Numeric in (0, 1); fraction of the training nodes held out internally
  to select the stopping epoch. Default `0.2`.

- backend:

  `"r"` (default, ELM-style) or `"torch"` (full autograd with multi-head
  attention; requires the `torch` Suggests dependency). v2.7.0 upgrade.

- device:

  `"cpu"` (default), `"mps"`, or `"cuda"` when `backend = "torch"`.

## Value

An `edaphos_gnn_gat` fit.
