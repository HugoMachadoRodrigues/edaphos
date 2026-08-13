# Graph-based causal discovery (Pilar 10 x Pilar 1)

Runs
[`causal_structure_learn()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_structure_learn.md)
on a feature frame augmented with GAT node embeddings, which act as
nuisance conditioners absorbing spatial dependence the expert DAG does
not name.

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

An `edaphos_causal_kg` from the underlying structure-learn call.
`$graph` is the DAG over `feature_frame` *and* the `z_emb_*`
conditioners; `$edges_feature_only` is a two-column character matrix of
the arcs whose endpoints are both in `feature_frame` (added only when
`igraph` is installed).

## Details

The returned graph is the FULL augmented DAG: the `z_emb_*` conditioners
are vertices of `$graph` like any other. The restriction to the caller's
variables is attached alongside it as `$edges_feature_only`, and
everything downstream that walks `$graph` –
[`causal_kg_edges()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_edges.md),
backdoor adjustment – still sees the embedding nodes.

## Examples

``` r
# `causal_structure_learn()` needs bnlearn AND igraph, both
# Suggests, so the whole hand-off is guarded.
if (requireNamespace("bnlearn", quietly = TRUE) &&
    requireNamespace("igraph", quietly = TRUE)) {

  set.seed(1)
  sub <- br_cerrado[sample(nrow(br_cerrado), 150L), ]
  names(sub)[names(sub) == "x"] <- "lon"
  names(sub)[names(sub) == "y"] <- "lat"

  # Pillar 10 side: a k-NN co-location graph over the pixels, then
  # a GAT whose node embeddings have already absorbed each pixel's
  # spatial neighbourhood.
  g <- gnn_build_graph(sub, k = 6L,
                       feature_cols = c("elev", "slope", "twi",
                                        "map_mm", "ndvi"))
  gat <- gnn_fit(g, sub$soc, hidden = 8L, n_heads = 2L,
                 n_layers = 1L, epochs = 40L, seed = 1L)

  # Pillar 1 side: hill-climbing over the six covariates PLUS four
  # embedding dimensions carried along as conditioners.
  feats <- sub[, c("elev", "slope", "twi", "map_mm", "ndvi", "soc")]
  kg <- gnn_causal_discovery(gat, feats, method = "hc",
                             n_emb_cols = 4L, seed = 1L)

  # The restriction the name promises lives in one extra field.
  # `kg$graph` is still the augmented DAG -- 10 vertices, 25 arcs,
  # 17 of them touching a conditioner.  Anything that reads
  # `kg$graph` gets the nuisance nodes too.
  print(c(vertices     = igraph::vcount(kg$graph),
          arcs         = igraph::ecount(kg$graph),
          feature_only = nrow(kg$edges_feature_only)))
  e <- causal_kg_edges(kg)
  print(sum(grepl("^z_emb_", e$cause) | grepl("^z_emb_", e$effect)))

  # What the conditioning bought, read against the same search with
  # no embeddings at all: eight arcs over the six covariates
  # against seven, four of them shared.
  plain <- causal_structure_learn(feats, variables = names(feats),
                                  method = "hc")
  p <- causal_kg_edges(plain)
  a_arcs <- paste(kg$edges_feature_only[, 1L], "->",
                  kg$edges_feature_only[, 2L])
  p_arcs <- paste(p$cause, "->", p$effect)
  print(setdiff(a_arcs, p_arcs))
  # "elev -> map_mm" "map_mm -> ndvi" "slope -> soc" "twi -> soc"
  print(setdiff(p_arcs, a_arcs))
  # "soc -> map_mm" "slope -> map_mm" "twi -> map_mm"

  # Read those two lines together before believing either DAG.
  # Without the embeddings three arrows run INTO mean annual
  # rainfall, from carbon and from terrain; conditioning on four
  # GAT dimensions removes all three, puts elevation upstream of
  # rainfall instead, and sends slope and TWI straight to SOC.
  # Encouraging -- but a BIC score is identical across a Markov
  # equivalence class, so arc DIRECTION out of `hc` is a search
  # artefact and not evidence.  Pin the arrows you already know
  # with `whitelist` / `blacklist` before reading any of it
  # causally.
}
#>     vertices         arcs feature_only 
#>           10           22            5 
#> [1] 17
#> [1] "elev -> map_mm"
#> [1] "soc -> map_mm"   "slope -> map_mm" "twi -> map_mm"  
```
