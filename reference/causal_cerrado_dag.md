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

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE)) {
  dag <- causal_cerrado_dag()

  # Unlike causal_clorpt_dag(), every node is a column of the
  # bundled grid, so DAG and data frame can be used together as-is.
  print(all(names(dag) %in% names(br_cerrado)))

  # A DAG is a falsifiable claim, not decoration. This one is nearly
  # saturated: it implies only two conditional independencies, so
  # passing them is weak evidence for the structure, not proof.
  print(dagitty::impliedConditionalIndependencies(dag))

  # Both do hold in br_cerrado -- the partial correlations come out
  # under 0.03 in absolute value, and neither confidence interval
  # excludes zero.
  print(dagitty::localTests(dag, br_cerrado))
}
#> [1] TRUE
#> elev _||_ ndvi | mp_m, slop, twi
#> mp_m _||_ slop | elev
#>                                    estimate   p.value        2.5%      97.5%
#> elev _||_ ndvi | mp_m, slop, twi 0.02075439 0.3509765 -0.02285807 0.06428808
#> mp_m _||_ slop | elev            0.01331066 0.5495577 -0.03027714 0.05684796
```
