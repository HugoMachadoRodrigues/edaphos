# Tidy edge list of a pedogenetic Knowledge Graph

Returns a `data.frame` with one row per edge and columns `cause`,
`effect`, `source`, `evidence`, `confidence`, `timestamp`.

## Usage

``` r
causal_kg_edges(kg)
```

## Arguments

- kg:

  An `edaphos_causal_kg`.

## Value

A data frame; empty (zero rows) for an empty graph.

## Examples

``` r
if (requireNamespace("igraph", quietly = TRUE)) {
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(
    kg, "mean annual precipitation", "ndvi",
    source     = "Jenny 1941",
    evidence   = "Water availability limits primary production.",
    confidence = 0.90
  )
  kg <- causal_kg_add_edge(
    kg, "ndvi", "soc",
    source     = "Minasny et al. 2017",
    evidence   = "Litter inputs scale with productivity.",
    confidence = 0.85
  )
  kg <- causal_kg_add_edge(
    kg, "termite mound density", "soc",
    source     = "field notebook",
    evidence   = "Speculative bioturbation pathway.",
    confidence = 0.35
  )

  edges <- causal_kg_edges(kg)
  edges[, c("cause", "effect", "confidence")]

  # The frame is an audit trail, not just a topology dump: every
  # claim carries the source and the quotation it was extracted
  # from, so the weakly supported ones can go back for curation.
  edges[edges$confidence < 0.5, c("cause", "effect", "source")]

  # An empty graph returns a ZERO-ROW frame with the same six
  # columns, never NULL, so column-wise code is safe before any
  # claim has been extracted.
  dim(causal_kg_edges(causal_kg_new()))  # 0 6
}
#> [1] 0 6
```
