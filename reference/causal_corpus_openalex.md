# Query the OpenAlex corpus

Thin wrapper around the **OpenAlex Works API** (no account needed; a
courtesy `mailto=` parameter raises the user's rate-limit tier).
OpenAlex stores abstracts as an inverted index; they are reconstructed
to plain text here so the result is LLM-extractor-ready.

## Usage

``` r
causal_corpus_openalex(
  query,
  max_results = 50L,
  from_year = NULL,
  to_year = NULL,
  mailto = NULL,
  timeout_sec = 120
)
```

## Arguments

- query:

  Character search string.

- max_results:

  Integer cap on the total number of works fetched. The function
  transparently pages through the API (cursor-based, 200 results per
  page) until either `max_results` or the result set is exhausted.

- from_year, to_year:

  Optional integer year filters (inclusive).

- mailto:

  Optional email string sent as `mailto=` to identify the client and
  unlock the "polite" rate-limit pool.

- timeout_sec:

  Request timeout (seconds).

## Value

A data frame with columns `source`, `title`, `abstract`, `year`, `doi`,
`url`.

## Examples

``` r
if (FALSE) { # \dontrun{
  oa <- causal_corpus_openalex("Cerrado soil organic carbon",
                                max_results = 2500L,
                                mailto = "you@example.org")
  head(oa[, c("source", "title", "year")])
} # }
```
