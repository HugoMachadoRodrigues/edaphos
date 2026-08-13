# Load a Knowledge Graph from disk

Reads a `.rds` file previously written by
[`causal_kg_save()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_save.md)
and reconstructs the `edaphos_causal_kg`. The reconstruction is careful:
it re-calls
[`causal_kg_add_edge()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_add_edge.md)
for every saved edge so that the duplicate-edge merge + cycle check +
normalisation rules stay consistent with a freshly-built graph.

## Usage

``` r
causal_kg_load(path)
```

## Arguments

- path:

  Path to the `.rds` file.

## Value

An `edaphos_causal_kg`.

## Examples

``` r
if (requireNamespace("igraph", quietly = TRUE)) {
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "mean annual precipitation", "ndvi",
                           source     = "Jenny 1941",
                           evidence   = "Water limits primary production.",
                           confidence = 0.90)
  kg <- causal_kg_add_edge(kg, "ndvi", "soc",
                           source     = "Minasny et al. 2017",
                           evidence   = "Litter inputs scale with NPP.",
                           confidence = 0.85)

  f <- tempfile(fileext = ".rds")
  causal_kg_save(kg, f)

  # The round trip is exact down to the per-edge timestamps, so a
  # reloaded KG is the same audit trail, not an approximation.
  print(identical(causal_kg_edges(kg),
                  causal_kg_edges(causal_kg_load(f))))

  # Loading REPLAYS causal_kg_add_edge() for every saved edge, and
  # the replay is wrapped in suppressWarnings(). A KG that warned
  # about a cycle while you built it therefore reloads in silence:
  # re-check is_dag() after loading rather than waiting to be told.
  cyclic <- suppressWarnings(
    causal_kg_add_edge(kg, "soc", "mean annual precipitation",
                       confidence = 0.40)
  )
  g <- tempfile(fileext = ".rds")
  causal_kg_save(cyclic, g)
  print(igraph::is_dag(causal_kg_load(g)$graph))  # FALSE, silently

  # The reader is guarded by format_version, so aiming it at some
  # other .rds fails loudly instead of half-building a graph.
  other <- tempfile(fileext = ".rds")
  saveRDS(list(cause = "clay", effect = "soc"), other)
  try(causal_kg_load(other))
}
#> [1] TRUE
#> [1] FALSE
#> Error : File '/tmp/Rtmph4Y1fI/file1ec31a34e637.rds' does not look like a saved edaphos KG (format_version mismatch).
```
