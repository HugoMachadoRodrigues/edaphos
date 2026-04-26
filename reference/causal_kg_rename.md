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
