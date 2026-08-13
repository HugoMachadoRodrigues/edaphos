# Create an empty pedogenetic Knowledge Graph

Initialises an empty, directed `edaphos_causal_kg` object. Edges are
added with
[`causal_kg_add_edge()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_add_edge.md)
— each edge carries four metadata attributes: `source` (bibliographic or
textual provenance), `evidence` (a short quotation supporting the
claim), `confidence` (value in `[0, 1]`, typically returned by an LLM
extractor), and `timestamp` (ISO 8601, auto-recorded).

## Usage

``` r
causal_kg_new()
```

## Value

An `edaphos_causal_kg` object (S3) containing an empty directed
`igraph`.

## Examples

``` r
# \donttest{
# `causal_kg_*()` needs igraph, a Suggests. `R CMD check --as-cran`
# DOES execute \donttest blocks, so this guard is load-bearing:
# without it the example errors on any machine lacking igraph.
if (requireNamespace("igraph", quietly = TRUE)) {
    kg <- causal_kg_new()
    kg <- causal_kg_add_edge(
      kg, "precipitation", "soc",
      source     = "Jenny 1941",
      evidence   = "Higher precipitation favours organic-matter accumulation.",
      confidence = 0.9
    )
    causal_kg_edges(kg)
}
#>           cause effect     source
#> 1 precipitation    soc Jenny 1941
#>                                                    evidence confidence
#> 1 Higher precipitation favours organic-matter accumulation.        0.9
#>              timestamp
#> 1 2026-08-13T23:17:03Z
# }
```
