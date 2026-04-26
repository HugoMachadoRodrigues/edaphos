# Suggest a backdoor-adjustment set from a DAG

Wraps
[`dagitty::adjustmentSets()`](https://rdrr.io/pkg/dagitty/man/adjustmentSets.html)
and returns the adjustment set as a plain character vector — or `NULL`
if the effect is not identifiable.

## Usage

``` r
causal_adjustment_set(
  dag,
  exposure,
  outcome,
  type = c("minimal", "canonical", "all"),
  effect = c("direct", "total")
)
```

## Arguments

- dag:

  A `dagitty` DAG object.

- exposure:

  Character, name of the exposure variable.

- outcome:

  Character, name of the outcome variable.

- type:

  One of `"minimal"`, `"canonical"`, `"all"`; forwarded to
  [`dagitty::adjustmentSets()`](https://rdrr.io/pkg/dagitty/man/adjustmentSets.html).

- effect:

  One of `"direct"` or `"total"`; forwarded to
  [`dagitty::adjustmentSets()`](https://rdrr.io/pkg/dagitty/man/adjustmentSets.html).

## Value

A character vector of variable names to condition on, or `NULL` if no
valid set exists.
