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

## Examples

``` r
data(br_cerrado)
set.seed(10)

sub <- br_cerrado[sample(nrow(br_cerrado), 150L), ]
names(sub)[names(sub) == "x"] <- "lon"
names(sub)[names(sub) == "y"] <- "lat"
g <- gnn_build_graph(sub, k = 6L,
                     feature_cols = c("elev", "slope", "twi", "map_mm"))

test  <- rep(c(FALSE, FALSE, TRUE), length.out = nrow(sub))
y     <- sub$soc
y_obs <- y; y_obs[test] <- NA

ens <- gnn_fit_ensemble(g, y_obs, n_ensemble = 4L, seed = 1L,
                        hidden = 8L, n_heads = 2L, n_layers = 2L,
                        epochs = 60L)
ens
#> <edaphos_gnn_ensemble>
#>   members = 4   nodes = 150   trained on = 100
#>   mean between-member sd = 0.6984

# Members differ only in their seed.  That alone moves the held-out
# score by more than most modelling choices do, which is the whole
# argument for reporting an ensemble instead of one lucky fit.
null_mean <- mean(y[!test])
nse <- function(pred)
  1 - sum((pred - y[test])^2) / sum((y[test] - null_mean)^2)
member <- vapply(ens$members, function(m) nse(predict(m)[test]),
                 numeric(1))
round(c(worst = min(member), mean = mean(member), best = max(member),
        ensemble = nse(predict(ens)[test])), 4)
#>    worst     mean     best ensemble 
#>   0.4799   0.5138   0.5507   0.5262 

# Note what averaging does and does not buy: it beats the AVERAGE
# member, not the best one -- and which seed was best is knowable
# only from the held-out labels you are not supposed to have.

# `member_sd` is the spread BETWEEN seeds, not a predictive
# interval.  It is under a fifth of the actual error here, so a
# +-1.96 sd band covers a quarter of the profiles, not 95 percent.
round(c(rmse       = sqrt(mean((predict(ens)[test] - y[test])^2)),
        mean_sd    = mean(ens$member_sd[test]),
        coverage95 = mean(abs(y[test] - predict(ens)[test]) <=
                          1.96 * ens$member_sd[test])), 3)
#>       rmse    mean_sd coverage95 
#>      4.339      0.746      0.240 
```
