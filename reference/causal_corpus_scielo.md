# Query the SciELO literature corpus

Calls the **SciELO ArticleMeta REST API** (no account needed) and
returns a tidy data frame of abstracts ready for LLM extraction via
[`causal_llm_ingest_corpus()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_corpus.md).
Results are deduplicated by DOI / title and filtered to articles that
expose an abstract.

## Usage

``` r
causal_corpus_scielo(
  query,
  max_results = 50L,
  from_year = NULL,
  to_year = NULL,
  host = "articlemeta.scielo.org",
  timeout_sec = 120
)
```

## Arguments

- query:

  Character search string passed to the ArticleMeta full-text search
  (`q=`).

- max_results:

  Integer cap on the number of articles fetched.

- from_year, to_year:

  Optional integer year filters (inclusive).

- host:

  Endpoint host (default `"articlemeta.scielo.org"`; override for mirror
  testing).

- timeout_sec:

  Request timeout (seconds).

## Value

A data frame with columns `source`, `title`, `abstract`, `year`, `doi`,
`url`.

## Examples

``` r
if (FALSE) { # \dontrun{
  cerrado <- causal_corpus_scielo("Cerrado soil organic carbon",
                                   max_results = 20)
  head(cerrado[, c("source", "title", "year")])
} # }
```
