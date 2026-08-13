# Add a causal edge to a pedogenetic Knowledge Graph

Add a causal edge to a pedogenetic Knowledge Graph

## Usage

``` r
causal_kg_add_edge(
  kg,
  cause,
  effect,
  source = NA_character_,
  evidence = NA_character_,
  confidence = 1,
  timestamp = NULL
)
```

## Arguments

- kg:

  An `edaphos_causal_kg` returned by
  [`causal_kg_new()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_new.md).

- cause, effect:

  Character scalar — the causal exposure and the outcome node. Node
  names are normalised to lower-snake-case.

- source:

  Character scalar with a bibliographic key or human description of the
  evidence source (e.g. `"Jenny 1941"`, `"Minasny et al. 2017"`).

- evidence:

  Character scalar with a short quotation supporting the claim (max ~200
  characters recommended).

- confidence:

  Numeric in `[0, 1]` — the LLM's or annotator's confidence that the
  claim is supported by the evidence.

- timestamp:

  Character ISO 8601 timestamp. Defaults to
  [`Sys.time()`](https://rdrr.io/r/base/Sys.time.html).

## Value

The updated `edaphos_causal_kg`.

## Examples

``` r
if (requireNamespace("igraph", quietly = TRUE)) {
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(
    kg, "Mean annual precipitation", "SOC stock",
    source     = "Jenny 1941",
    evidence   = "Moisture regulates decomposition rate.",
    confidence = 0.80
  )

  # Node labels are normalised to lower-snake-case before insertion,
  # so free-text variants collapse onto one node. Convenient for LLM
  # output, but it silently merges concepts whose labels differ only
  # in case, spaces or hyphens.
  kg <- causal_kg_add_edge(
    kg, "mean-annual-precipitation", "soc stock",
    source     = "Minasny et al. 2017",
    evidence   = "Wetter sites accumulate more carbon.",
    confidence = 0.55
  )
  nrow(causal_kg_edges(kg))  # 1 -- the second call merged into the first

  # A merge keeps the MAXIMUM confidence and pastes provenance with
  # " | ". A weaker second citation can therefore never lower an
  # edge's confidence: re-asserting a claim only ever strengthens it.
  causal_kg_edges(kg)[, c("source", "confidence")]

  # A cycle is only warned about; the edge is still added and the
  # graph stops being a DAG, which breaks backdoor adjustment later.
  cyclic <- suppressWarnings(
    causal_kg_add_edge(kg, "soc stock", "mean annual precipitation",
                       confidence = 0.40)
  )
  igraph::is_dag(cyclic$graph)  # FALSE

  # A self-loop is a hard error instead -- and after normalisation
  # these two spellings are the same node.
  try(causal_kg_add_edge(kg, "SOC stock", "soc-stock"))
}
#> Error : Self-loops are not allowed (cause == effect).
```
