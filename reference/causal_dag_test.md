# Test a DAG against the conditional independencies it implies

Restricts a graph to the nodes for which `data` has columns, enumerates
the conditional independencies the restricted graph implies, and tests
each one. Reports how many the data reject, which ones, and — optionally
— the same test after large-scale spatial structure has been removed.

## Usage

``` r
causal_dag_test(dag, data, alpha = 0.05, coords = NULL, k = 100L)
```

## Arguments

- dag:

  A `dagitty` graph, e.g. from
  [`causal_cerrado_real_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_cerrado_real_dag.md).

- data:

  A data frame whose columns are named after the graph's nodes. Nodes
  without a column are dropped from the tested sub-graph and reported in
  `nodes_without_data`.

- alpha:

  Significance level for calling an implied independence rejected.
  Applied twice: per test (unadjusted counts) and as the family-wise
  level of a Holm adjustment over all implied independencies, which is
  what the printed verdict on the graph is based on.

- coords:

  Optional length-2 character vector naming the coordinate columns in
  `data`. When supplied (and `mgcv` is installed), a second test is run
  on variables residualised on a thin-plate spline of position, which
  removes the large-scale spatial structure that inflates the effective
  sample size of a pooled test.

- k:

  Basis dimension of that spline. The residual degrees of freedom are
  reduced by `k` before testing, so the spatial test is not credited
  with observations the smoother consumed.

## Value

An `edaphos_dag_test` object: a list with `pooled` (the
[`dagitty::localTests`](https://rdrr.io/pkg/dagitty/man/localTests.html)
table), `spatial` (the same after residualising, or `NULL`), `n_tests`,
`n_rejected` and `n_rejected_spatial` (unadjusted p-value below
`alpha`), `n_rejected_holm` and `n_rejected_spatial_holm` (Holm-adjusted
p-value below `alpha`, via
[`stats::p.adjust()`](https://rdrr.io/r/stats/p.adjust.html)),
`max_abs_r` (largest absolute partial correlation over all tests,
rejected or not), `nodes_tested`, `nodes_without_data`, and `n`.

With `n_tests` implied independencies that all hold, about
`alpha * n_tests` unadjusted rejections are expected by chance alone, so
the unadjusted count is not by itself evidence against the graph. The
print method reports it against that expectation and rests its verdict
on the Holm count.

## References

Zhang Y, Wadoux AMJ-C (2026). Can digital soil mapping be causal?
*Geoderma*.

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE)) {
  # Simulated profiles, already using the graph's own column names.
  d <- edaphos_example_profiles()

  tst <- causal_dag_test(causal_cerrado_real_dag(), d)
  tst

  # The spatial variant fits one thin-plate spline per variable, so it is
  # seconds rather than milliseconds.
  # \donttest{
  tsp <- causal_dag_test(causal_cerrado_real_dag(), d,
                         coords = c("lon", "lat"))
  # The graph fails on both tests -- but the counts differ, which is why
  # reporting only the pooled one would overstate the result.
  c(pooled = tsp$n_rejected, spatial = tsp$n_rejected_spatial,
    of = tsp$n_tests)
  # }
}
#>  pooled spatial      of 
#>       6       2      66 
```
