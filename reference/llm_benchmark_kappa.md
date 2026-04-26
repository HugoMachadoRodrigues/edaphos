# Pairwise Cohen's kappa between backends on edge presence

Computes agreement (Cohen's kappa) for every pair of backends on the
union of edges seen across them (and optionally gold) per abstract. For
each backend pair (A, B), treats every (abstract, edge) as a binary
rating: "did backend X extract this edge?".

## Usage

``` r
llm_benchmark_kappa(claims_by_backend, gold = NULL)
```

## Arguments

- claims_by_backend:

  Named list of data frames, each with `abstract_id`, `cause`, `effect`.

- gold:

  Optional gold-standard frame to include as a rater.

## Value

Numeric matrix of kappa values (symmetric, diagonal = 1).
