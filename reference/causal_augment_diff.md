# Diff between a base DAG and an augmented DAG

Convenience helper that shows which edges are inherited from the
`base_dag`, which are new from the Knowledge Graph, and (if any) which
were rejected as cycle-forming. Handy for vignettes and auditing.

## Usage

``` r
causal_augment_diff(base_dag, augmented_dag)
```

## Arguments

- base_dag, augmented_dag:

  Two `dagitty` DAG objects — typically the second is the return value
  of
  [`causal_augment_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_augment_dag.md).

## Value

A data frame with columns `cause`, `effect`, `origin` (`"base"` or
`"kg"`).

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE) &&
    requireNamespace("igraph", quietly = TRUE)) {

  base <- causal_cerrado_dag()

  # Two mined claims. The first is sound -- clay protects organic
  # carbon. The second is a pedogenetic relation read backwards:
  # rainfall drives weathering drives clay, not clay drives
  # rainfall. The extractor was equally confident about both.
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "clay", "soc",    confidence = 0.95)
  kg <- causal_kg_add_edge(kg, "clay", "map_mm", confidence = 0.95)

  aug   <- causal_augment_dag(base, kg)
  diffs <- causal_augment_diff(base, aug)
  print(diffs[diffs$origin == "kg", ])

  # The wrong edge is not inert. Together the two claims make
  # `clay` a confounder of map_mm -> soc, so the minimal adjustment
  # set grows by a variable br_cerrado does not contain.
  print(causal_adjustment_set(base, "map_mm", "soc"))
  adj <- causal_adjustment_set(aug, "map_mm", "soc")
  print(setdiff(adj, names(br_cerrado)))

  # So read `origin == "kg"` as "asserted by the extractor", never
  # as "validated". The only filters causal_augment_dag() applies
  # are the confidence threshold and acyclicity.

  # The diff also sees only edges that survived, so a KG edge
  # rejected as cycle-forming appears nowhere in it; its count
  # lives on the augmented DAG. Nothing cycled here, hence 0.
  print(attr(aug, "n_rejected"))
}
#>   cause effect origin
#> 1  clay map_mm     kg
#> 2  clay    soc     kg
#> [1] "elev"  "ndvi"  "slope" "twi"  
#> [1] "clay"
#> [1] 0
```
