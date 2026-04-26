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
