# Export a Knowledge Graph to a `dagitty` DAG

Projects the Knowledge Graph onto a `dagitty` DAG by keeping only the
edges whose confidence is at least `min_confidence`. The resulting DAG
is ready to be consumed by
[`causal_adjustment_set()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_adjustment_set.md)
and
[`causal_estimate_effect()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_estimate_effect.md).

## Usage

``` r
causal_kg_to_dagitty(kg, min_confidence = 0.7)
```

## Arguments

- kg:

  An `edaphos_causal_kg`.

- min_confidence:

  Numeric in `[0, 1]`. Edges with `confidence < min_confidence` are
  dropped.

## Value

A `dagitty` object.
