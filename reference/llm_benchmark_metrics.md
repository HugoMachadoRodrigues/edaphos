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

## Examples

``` r
res_path <- system.file("extdata", "llm_benchmark_results.rds",
                        package = "edaphos")
if (nzchar(res_path)) {
  B <- readRDS(res_path)

  # Read this before quoting any number below: the shipped bundle is
  # simulator output, not measured API calls.
  print(B$mode)

  m <- llm_benchmark_metrics(
    llm_benchmark_match(B$backend_claims[["Gemma 4"]], B$gold_df))
  print(round(unlist(
    m[c("tp", "fp", "fn", "precision", "recall", "f1")]), 4))

  # Every row of the match table lands in exactly one cell, so the
  # three counts reconstruct its length -- a cheap audit that no
  # abstract was dropped by the join.
  mt <- llm_benchmark_match(B$backend_claims[["Gemma 4"]], B$gold_df)
  print(c(counts = m$tp + m$fp + m$fn, rows = nrow(mt)))

  # Trap: `per_abstract` returns NA, not 0, whenever a denominator is
  # empty.  Precision is NA for the 2 abstracts where this backend
  # predicted nothing at all, and F1 is NA for all 5 where it got
  # nothing right (precision + recall == 0).
  pa <- m$per_abstract
  print(c(abstracts = nrow(pa), na_precision = sum(is.na(pa$precision)),
          na_f1 = sum(is.na(pa$f1))))

  # So the obvious macro average deletes exactly the abstracts the
  # backend failed on and reports 0.794; scoring those failures as 0
  # gives 0.662; the pooled (micro) F1 is 0.706.  Quote the micro
  # figure -- `mean(f1, na.rm = TRUE)` is the flattering one.
  print(round(c(macro_narm = mean(pa$f1, na.rm = TRUE),
                macro_zero = mean(ifelse(is.na(pa$f1), 0, pa$f1)),
                micro      = m$f1), 4))

  # And read the spread next to the headline: this backend is not
  # uniformly mediocre, it is bimodal -- 10 of 30 abstracts perfect,
  # 5 a complete miss.
  print(c(perfect = sum(pa$f1 == 1, na.rm = TRUE),
          total_miss = sum(is.na(pa$f1))))
}
#> [1] "simulated"
#>        tp        fp        fn precision    recall        f1 
#>   48.0000   16.0000   24.0000    0.7500    0.6667    0.7059 
#> counts   rows 
#>     88     88 
#>    abstracts na_precision        na_f1 
#>           30            2            5 
#> macro_narm macro_zero      micro 
#>     0.7941     0.6617     0.7059 
#>    perfect total_miss 
#>         10          5 
```
