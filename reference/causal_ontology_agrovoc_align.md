# Live AGROVOC alignment for a vector of free-text terms

For each input `term`, queries the AGROVOC SPARQL endpoint for concepts
whose `skos:prefLabel` or `skos:altLabel` contains the term, ranks the
matches by Levenshtein distance to the canonical label, and returns the
best hit. Results are cached on disk via `cache_path` so that repeated
runs over the same vocabulary do not re-query FAO.

## Usage

``` r
causal_ontology_agrovoc_align(
  terms,
  cache_path = NULL,
  max_per_term = 5L,
  endpoint = "https://agrovoc.fao.org/sparql",
  timeout_sec = 60L,
  verbose = FALSE
)
```

## Arguments

- terms:

  Character vector of free-text terms (typically the nodes of a
  Knowledge Graph).

- cache_path:

  Optional `.rds` file path. When supplied, the function reads cached
  matches on entry and writes updated matches on exit.

- max_per_term:

  Integer — how many candidates to request per term (AGROVOC query
  LIMIT). The best one is kept.

- endpoint:

  Override the SPARQL endpoint URL.

- timeout_sec:

  Per-query timeout.

- verbose:

  Logical — print one line per queried term.

## Value

A data frame with columns `term` (input), `uri` (AGROVOC concept),
`label` (AGROVOC pref label), `distance` (Levenshtein of lowercased
label vs term).
