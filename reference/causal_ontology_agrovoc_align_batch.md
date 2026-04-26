# Concurrent AGROVOC alignment for a large vocabulary

Resolves a vector of free-text `terms` against the FAO AGROVOC SPARQL
endpoint using **parallel HTTP dispatch**, an on-disk cache, and retry
logic with exponential backoff. Designed for Knowledge Graphs built from
thousands of papers, where the per-term overhead of
[`causal_ontology_agrovoc_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align.md)
(~5–10 s / term against agrovoc.fao.org) dominates the runtime.

## Usage

``` r
causal_ontology_agrovoc_align_batch(
  terms,
  cache_path = NULL,
  max_active = 5L,
  max_per_term = 5L,
  max_retries = 2L,
  endpoint = "https://agrovoc.fao.org/sparql",
  timeout_sec = 60L,
  verbose = FALSE
)
```

## Arguments

- terms:

  Character vector of free-text terms.

- cache_path:

  Optional `.rds` file path. When supplied, the function reads cached
  matches on entry and writes updated matches on exit.

- max_active:

  Integer — maximum number of concurrent HTTP connections. Default `5`;
  raise for faster throughput, lower if the endpoint is rate-limiting
  you. `httr2` transparently pools up to `max_active` connections.

- max_per_term:

  Integer — AGROVOC query `LIMIT` per term; the closest label by
  Levenshtein distance is retained.

- max_retries:

  Integer — number of retry rounds for terms that come back with a
  non-200 response. Retries apply exponential backoff (`2 ^ attempt`
  seconds between rounds).

- endpoint:

  AGROVOC SPARQL endpoint URL. Override for a mirror or a local SPARQL
  proxy.

- timeout_sec:

  Per-request timeout (seconds).

- verbose:

  Logical — print a one-line progress summary after each parallel round.

## Value

A data frame with columns `term`, `uri`, `label`, `distance` (NA when no
hit). Unresolved terms keep NA slots; the caller can decide whether to
retry them or accept a partial alignment.

## SPARQL-level vs transport-level batching

A single composite SPARQL query that binds N terms via `VALUES` and
filters labels with `CONTAINS(?label, ?term)` is the theoretically
optimal batching strategy, but AGROVOC's production endpoint
consistently rejects such queries with a 504 gateway timeout because the
substring predicate cannot short-circuit against the bound term set.
`causal_ontology_agrovoc_align_batch()` therefore batches at the
transport layer instead: it issues one single-term query per uncached
input and dispatches them through
[`httr2::req_perform_parallel()`](https://httr2.r-lib.org/reference/req_perform_parallel.html)
with `max_active` concurrent connections. The on-wire semantics are
identical to
[`causal_ontology_agrovoc_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align.md);
only the wall-clock time changes.

## Caching and resumability

The cache is a named list keyed by normalised term, persisted as a
single `.rds` file. On entry every cached term is short-circuited
without a network call. Failed terms are **not** cached, so a resumed
run retries them; successful terms become permanent. Pointing a fresh
`cache_path` at an existing `.rds` keeps the cache; passing `NULL`
disables persistence (in-memory only).

## See also

[`causal_ontology_agrovoc_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align.md)
for the sequential variant;
[`causal_kg_alignment()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_alignment.md)
for KG-level dispatch.

## Examples

``` r
if (FALSE) { # \dontrun{
  # 100-term vocabulary extracted from a KG built over 10k abstracts.
  vocab <- unique(c(causal_kg_edges(kg)$cause,
                     causal_kg_edges(kg)$effect))
  ag <- causal_ontology_agrovoc_align_batch(
    vocab,
    cache_path = "tools/.agrovoc_cache.rds",
    max_active = 8L,
    max_retries = 2L,
    verbose = TRUE
  )
  # Resolution rate:
  mean(!is.na(ag$uri))
} # }
```
