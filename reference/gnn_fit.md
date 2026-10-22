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

  Integer; training epochs. Every layer is trained, not only the readout
  head.

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

  `"r"` (default; analytic reverse-mode gradients over all layers) or
  `"torch"` (autograd, same architecture; requires the `torch` Suggests
  dependency). Unlike Pillars 8 and 9, whose pure-R paths are
  frozen-feature references that do not learn the named architecture,
  the Pillar 10 R backend trains the GAT itself.

- device:

  `"cpu"` (default), `"mps"`, or `"cuda"` when `backend = "torch"`.

## Value

An `edaphos_gnn_gat` fit.

## References

Veličković, P., Cucurull, G., Casanova, A., Romero, A., Liò, P. and
Bengio, Y. (2018). Graph Attention Networks. *International Conference
on Learning Representations*.

Kipf, T. N. and Welling, M. (2017). Semi-Supervised Classification with
Graph Convolutional Networks. *International Conference on Learning
Representations*.

## Examples

``` r
data(br_cerrado)
set.seed(10)

# gnn_build_graph() wants the coordinates under `lon` / `lat`.
sub <- br_cerrado[sample(nrow(br_cerrado), 150L), ]
names(sub)[names(sub) == "x"] <- "lon"
names(sub)[names(sub) == "y"] <- "lat"
g <- gnn_build_graph(sub, k = 6L,
                     feature_cols = c("elev", "slope", "twi", "map_mm"))

# Hold every third profile out by setting its target to NA: the
# default train_mask is !is.na(targets), so those nodes still pass
# messages to their neighbours but never enter the loss.
test  <- rep(c(FALSE, FALSE, TRUE), length.out = nrow(sub))
y     <- sub$soc
y_obs <- y; y_obs[test] <- NA

fit <- gnn_fit(g, y_obs, hidden = 8L, n_heads = 2L, n_layers = 2L,
               epochs = 60L, seed = 1L)
c(n_train = fit$n_train, n_val = fit$n_val,
  epochs_run = length(fit$history), best_epoch = fit$best_epoch)
#>    n_train      n_val epochs_run best_epoch 
#>        100         20         21          1 

# Score the held-out nodes against an achievable null -- the
# TRAINING mean -- and against OLS on the same four covariates.
null_mean <- mean(y[!test])
nse <- function(pred)
  1 - sum((pred - y[test])^2) / sum((y[test] - null_mean)^2)
ols <- lm(soc ~ elev + slope + twi + map_mm, data = sub[!test, ])
round(c(gat = nse(predict(fit)[test]),
        ols = nse(predict(ols, sub[test, ]))), 4)
#>    gat    ols 
#> 0.6259 0.5974 

# Before crediting the graph, read `best_epoch`.  It is 1 here: no
# epoch of attention training beat the initialisation on the
# internal validation split, so what came back is the random-init
# encoder plus the closed-form ridge head -- and the four raw
# covariates the readout skip hands that head do nearly all of it.
fit_ns <- gnn_fit(g, y_obs, hidden = 8L, n_heads = 2L, n_layers = 2L,
                  epochs = 60L, seed = 1L, readout_skip = FALSE)
round(c(with_skip = nse(predict(fit)[test]),
        without   = nse(predict(fit_ns)[test])), 4)
#> with_skip   without 
#>    0.6259    0.3806 

# Inventing a target for the held-out nodes instead of masking them
# -- the training mean is the usual choice -- fits the head to
# reproduce that invented value and drags the test set towards it.
y_imp <- y; y_imp[test] <- null_mean
fit_imp <- gnn_fit(g, y_imp, hidden = 8L, n_heads = 2L, n_layers = 2L,
                   epochs = 60L, seed = 1L)
round(c(masked = nse(predict(fit)[test]),
        invented = nse(predict(fit_imp)[test])), 4)
#>   masked invented 
#>   0.6259   0.4186 

# `history` is the TRAINING loss and the printed "final MSE" is its
# last entry.  Neither describes the parameters you got back, which
# come from `best_epoch` on the validation split.
round(c(train_at_best = fit$history[fit$best_epoch],
        train_min     = min(fit$history),
        train_at_end  = fit$history[length(fit$history)]), 4)
#> train_at_best     train_min  train_at_end 
#>        0.5043        0.4820        0.8000 
```
