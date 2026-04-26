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
