# Rename Knowledge-Graph nodes from an alignment mapping

Applies the `(original -> canonical)` mapping computed by
[`causal_kg_alignment()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_alignment.md)
to an `edaphos_causal_kg`, collapsing synonymous nodes and re-merging
their edges (max confidence / concatenated evidence, as per
[`causal_kg_add_edge()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_add_edge.md)).

## Usage

``` r
causal_kg_rename(kg, mapping)
```

## Arguments

- kg:

  An `edaphos_causal_kg`.

- mapping:

  A data frame with columns `original` and `canonical`. Rows with `NA`
  canonical are left untouched.

## Value

A new `edaphos_causal_kg` whose node names are the canonical terms
(unmapped nodes kept as-is).

## Examples

``` r
if (requireNamespace("igraph", quietly = TRUE)) {
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "precipitaton", "soc",
                           source = "Paper A", confidence = 0.7)
  kg <- causal_kg_add_edge(kg, "soc_stocks", "soc",
                           source = "Paper B", confidence = 0.5)

  map <- causal_kg_alignment(kg)
  kg2 <- causal_kg_rename(kg, map)

  # The typo is repaired: `precipitaton` becomes `precipitation`.
  print(causal_kg_edges(kg2)[, c("cause", "effect", "source")])

  # Now count the edges. `soc_stocks` aligns onto `soc`, so the edge
  # `soc_stocks -> soc` collapses into a self-loop and is dropped
  # without a warning: renaming can silently shrink a KG. Always
  # compare edge counts before and after.
  print(c(before = nrow(causal_kg_edges(kg)),
          after  = nrow(causal_kg_edges(kg2))))

  # Rows with an NA `canonical` are left untouched, so vetoing one
  # bad match by hand is enough to keep its edge alive.
  map$canonical[map$original == "soc_stocks"] <- NA
  nrow(causal_kg_edges(causal_kg_rename(kg, map)))
}
#>           cause effect  source
#> 1 precipitation    soc Paper A
#> before  after 
#>      2      1 
#> [1] 2
```
