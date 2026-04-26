# Ingest an abstract into a KG via multi-extractor voting

Single-call equivalent of running
[`causal_llm_vote()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_vote.md)
and then
[`causal_kg_add_edge()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_add_edge.md)
on every surviving edge. The resulting KG has a `source` tag of the form
`"<abstract_source> | vote(<voting>, n=<N_backends>)"` so the provenance
of every edge records both the underlying abstract and the backends that
agreed on the claim.

## Usage

``` r
causal_llm_ingest_abstract_voted(
  kg,
  abstract,
  source,
  backends,
  voting = "majority",
  min_support = NULL,
  threshold = NULL,
  weights = NULL,
  min_confidence = 0.5,
  timeout_sec = 120
)
```

## Arguments

- kg, abstract, source:

  See
  [`causal_llm_ingest_abstract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_abstract.md).

- backends, voting, min_support, threshold, weights, timeout_sec:

  Forwarded to
  [`causal_llm_vote()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_vote.md).

- min_confidence:

  Claims whose `mean_confidence` is below this threshold are dropped
  before insertion.

## Value

The updated `edaphos_causal_kg`. A `claims` attribute carries the tidy
consensus data frame that was actually inserted, and a `per_backend`
attribute carries the raw per-backend claims for audit / debugging.

## Examples

``` r
if (FALSE) { # \dontrun{
  backends <- list(
    list(backend = "ollama",    model = "gemma4:latest"),
    list(backend = "openai",    model = "gpt-4o-mini")
  )
  kg <- causal_kg_new()
  kg <- causal_llm_ingest_abstract_voted(
    kg,
    abstract = "Higher MAP drives SOC accumulation in Cerrado...",
    source   = "Ferreira 2021",
    backends = backends,
    voting   = "majority"
  )
} # }
```
