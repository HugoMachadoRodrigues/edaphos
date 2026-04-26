# DAG tailored to the bundled Cerrado dataset (`br_cerrado`)

Concrete directed acyclic graph matching the (synthetic) generating
process of `br_cerrado`, suitable for demonstrating backdoor adjustment
without relying on the high-level abstractions in
[`causal_clorpt_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_clorpt_dag.md).

## Usage

``` r
causal_cerrado_dag()
```

## Value

A `dagitty` graph object with nodes `elev`, `slope`, `twi`, `map_mm`,
`ndvi`, `soc`.
