# Augment a base DAG with edges from a Knowledge Graph

Takes a `dagitty` DAG expressing prior / expert structural knowledge
(e.g. the CLORPT or Cerrado DAGs shipped with `edaphos`) and unions it
with the subset of Knowledge-Graph edges whose confidence is at least
`min_confidence`. Duplicate edges are dropped silently, and any edge
whose insertion would introduce a directed cycle is rejected (warned but
not inserted), so the returned DAG is guaranteed to be acyclic and
usable for
[`causal_adjustment_set()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_adjustment_set.md).

## Usage

``` r
causal_augment_dag(base_dag, kg, min_confidence = 0.7, allow_new_nodes = TRUE)
```

## Arguments

- base_dag:

  A `dagitty` DAG (e.g.
  [`causal_cerrado_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_cerrado_dag.md)).

- kg:

  An `edaphos_causal_kg` (from
  [`causal_kg_new()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_new.md)
  / LLM ingestion).

- min_confidence:

  Numeric in `[0, 1]`; KG edges strictly below this threshold are
  ignored.

- allow_new_nodes:

  Logical. When `TRUE` (default) nodes appearing only in the KG are
  added to the augmented DAG. When `FALSE` KG edges touching unseen
  nodes are dropped — useful when the analyst wants to lock the
  structural vocabulary.

## Value

An object of class `dagitty`, augmented.

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE) &&
    requireNamespace("igraph", quietly = TRUE)) {

  base <- causal_cerrado_dag()   # 13 edges over the br_cerrado columns

  # Three claims of the shape an LLM extractor returns: one
  # plausible, one read backwards, one weakly supported.
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "elev", "ndvi",
                           source = "altitudinal zonation",
                           confidence = 0.92)
  kg <- causal_kg_add_edge(kg, "soc", "map_mm",
                           source = "mis-extracted direction",
                           confidence = 0.99)
  kg <- causal_kg_add_edge(kg, "fire_frequency", "soc",
                           source = "single-site study",
                           confidence = 0.45)

  # At the default threshold the 0.45 fire claim is never
  # considered. The 0.99 reversed claim is, and is then thrown out
  # by the acyclicity guard (with a warning) because base already
  # has map_mm -> soc. Only elev -> ndvi is actually added.
  aug <- causal_augment_dag(base, kg)
  print(unlist(attributes(aug)[c("n_base_edges", "n_added_edges",
                                 "n_rejected")]))

  # Note what that implies: confidence 0.99 bought nothing and
  # confidence 0.92 bought an edge. `min_confidence` ranks claims,
  # it never weighs them -- an edge is either in or out.

  # Lowering the threshold buys the fire claim, and with it a node
  # that no column of br_cerrado measures.
  loose <- causal_augment_dag(base, kg, min_confidence = 0.4)
  print(setdiff(names(loose), names(base)))

  # allow_new_nodes = FALSE locks the structural vocabulary, so
  # that edge is dropped again even though it cleared the
  # threshold.
  locked <- causal_augment_dag(base, kg, min_confidence = 0.4,
                               allow_new_nodes = FALSE)
  print(setdiff(names(locked), names(base)))
}
#> Warning: Rejected 1 edge(s) that would have introduced a directed cycle: soc -> map_mm
#>  n_base_edges n_added_edges    n_rejected 
#>            13             1             1 
#> Warning: Rejected 1 edge(s) that would have introduced a directed cycle: soc -> map_mm
#> [1] "fire_frequency"
#> Warning: Rejected 1 edge(s) that would have introduced a directed cycle: soc -> map_mm
#> character(0)
```
