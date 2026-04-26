# Rank Knowledge-Graph edges by evidence strength

Collapses a `edaphos_causal_kg` to one row per unique (cause, effect)
edge and ranks the result by a user-selected metric:

## Usage

``` r
causal_kg_rank_edges(
  kg,
  by = c("n_sources", "mean_confidence", "agrovoc_support"),
  alignment = NULL,
  top_n = NULL
)
```

## Arguments

- kg:

  An `edaphos_causal_kg`.

- by:

  Character vector of ranking metrics, any subset of
  `c("n_sources", "mean_confidence", "agrovoc_support")`, in priority
  order.

- alignment:

  Optional data frame as returned by
  [`causal_kg_alignment()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_alignment.md)
  (must have columns `original`, `canonical`, plus `uri` when derived
  from `vocab = "agrovoc"`). Used to compute `agrovoc_support`.

- top_n:

  Optional integer — return at most this many rows. `NULL` returns the
  full ranking.

## Value

A data frame with columns `cause`, `effect`, `n_sources`,
`mean_confidence`, `max_confidence`, `sources` (collapsed " \|
"-separated), `evidence` (collapsed), and — when available —
`agrovoc_support`, `agrovoc_cause`, `agrovoc_effect`.

## Details

- `"n_sources"`:

  Number of distinct sources supporting the edge (counted by splitting
  the `|`-separated `source` field on the underlying `igraph`
  edge-attribute). The single most informative signal for an
  LLM-extracted KG built over thousands of papers: an edge asserted by
  50 papers is far more trustworthy than one asserted by 1.

- `"mean_confidence"`:

  Mean LLM confidence across extractions that produced the same (cause,
  effect) pair.

- `"agrovoc_support"`:

  Fraction of the pair's endpoints (cause, effect) that resolve to a FAO
  AGROVOC concept under an `alignment` mapping (0, 0.5 or 1). Requires
  either `alignment` to be supplied or `kg` already aligned; when
  neither is available the column is `NA`.

The return is a tidy data frame sorted in descending order by *all*
ranking columns requested in `by` (i.e. the first `by` element is the
primary sort key, the second breaks ties, etc.). This is usually more
informative than a single-metric ranking — an edge that has both many
sources AND high confidence is more trustworthy than either alone.

## See also

[`causal_kg_alignment()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_alignment.md),
[`summary.edaphos_causal_kg()`](https://hugomachadorodrigues.github.io/edaphos/reference/summary.edaphos_causal_kg.md).

## Examples

``` r
# \donttest{
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "precipitation", "soc",
                            source = "Jenny 1941", confidence = 0.9)
  kg <- causal_kg_add_edge(kg, "precipitation", "soc",
                            source = "Minasny 2017", confidence = 0.85)
  causal_kg_rank_edges(kg, by = c("n_sources", "mean_confidence"))
#>           cause effect n_sources mean_confidence max_confidence
#> 1 precipitation    soc         2             0.9            0.9
#>                     sources evidence
#> 1 Jenny 1941 | Minasny 2017         
# }
```
