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
