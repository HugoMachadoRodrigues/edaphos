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

## Examples

``` r
if (requireNamespace("igraph", quietly = TRUE) &&
    requireNamespace("dagitty", quietly = TRUE)) {
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "mean annual precipitation", "ndvi",
                           confidence = 0.90)
  kg <- causal_kg_add_edge(kg, "mean annual precipitation", "soc",
                           confidence = 0.80)
  kg <- causal_kg_add_edge(kg, "ndvi", "soc", confidence = 0.85)
  kg <- causal_kg_add_edge(kg, "clay content", "soc",
                           confidence = 0.78)
  # A speculative claim the extractor was unsure about.
  kg <- causal_kg_add_edge(kg, "clay content", "ndvi",
                           confidence = 0.40)

  dag_hi <- causal_kg_to_dagitty(kg, min_confidence = 0.7)
  dag_lo <- causal_kg_to_dagitty(kg, min_confidence = 0.3)
  c(hi = nrow(dagitty::edges(dag_hi)),   # 4: clay -> ndvi dropped
    lo = nrow(dagitty::edges(dag_lo)))   # 5: it survives

  # min_confidence is a modelling decision, not a cosmetic filter.
  # Keeping the weak clay -> NDVI edge makes clay content a
  # confounder of the NDVI -> SOC effect, so it has to enter the
  # adjustment set; dropping it leaves precipitation alone. Same
  # evidence base, different estimator.
  causal_adjustment_set(dag_hi, "ndvi", "soc", effect = "total")
  causal_adjustment_set(dag_lo, "ndvi", "soc", effect = "total")

  # Set the bar above every edge and you get a valid but empty DAG
  # rather than an error, so check before handing it to an
  # estimator.
  length(names(causal_kg_to_dagitty(kg, min_confidence = 0.95)))  # 0
}
#> [1] 0
```
