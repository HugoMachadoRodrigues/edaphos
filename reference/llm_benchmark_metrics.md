# Compute precision / recall / F1 from a match table

Compute precision / recall / F1 from a match table

## Usage

``` r
llm_benchmark_metrics(match_df)
```

## Arguments

- match_df:

  Output of
  [`llm_benchmark_match()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_benchmark_match.md).

## Value

Named list with `precision`, `recall`, `f1`, `tp`, `fp`, `fn`, and
per-abstract metrics as a data frame in `per_abstract`.
