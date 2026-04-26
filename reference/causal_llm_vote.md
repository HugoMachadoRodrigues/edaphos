# Multi-extractor consensus over LLM-extracted causal claims

Runs **N LLM backends** on the same abstract and returns a single
consensus data frame that resolves the inevitable disagreements by one
of three voting rules. See the file header for the design rationale.

## Usage

``` r
causal_llm_vote(
  abstract,
  backends,
  voting = c("majority", "weighted", "intersection"),
  min_support = NULL,
  threshold = NULL,
  weights = NULL,
  timeout_sec = 120
)
```

## Arguments

- abstract:

  Character scalar with the passage to annotate.

- backends:

  List of backend configurations; see above.

- voting:

  `"majority"` (default), `"weighted"`, or `"intersection"`.

- min_support:

  Integer — required number of backends for `"majority"` voting.
  Defaults to `ceiling(length(backends) / 2)`.

- threshold:

  Numeric — weighted-confidence threshold for `"weighted"` voting.
  Defaults to `0.5 * sum(weights)`.

- weights:

  Optional numeric vector, one element per backend (same order as
  `backends`). Defaults to uniform weights.

- timeout_sec:

  Default per-request timeout; may be overridden per-backend via the
  `timeout_sec` field of each config entry.

## Value

A data frame with one row per consensus edge and columns `cause`,
`effect`, `n_backends`, `mean_confidence`, `weighted_confidence`,
`backends` (`" | "`-separated list of supporting backend ids),
`evidence` (concatenated quotations).

## Voting rules

- `"majority"` (default):

  Keep edges asserted by at least `min_support` backends. When
  `min_support = NULL`, defaults to `ceiling(length(backends) / 2)` so
  2-out-of-3 or 3-out-of-5 agreement survives.

- `"weighted"`:

  Keep edges whose weighted confidence \\\sum_i w_i c_i\\ exceeds
  `threshold`. Weights are supplied per backend via `weights`.

- `"intersection"`:

  Keep only edges asserted by **every** backend. Most conservative;
  maximises precision at the expense of recall.

## Expected `backends` shape

A list of lists. Each inner list configures one backend and must contain
at least a `backend` field (one of `"ollama"`, `"openai"`,
`"anthropic"`) and may optionally carry `model`, `host` (for Ollama),
`temperature`, `timeout_sec`, `api_key`, `id`. Example:

    backends = list(
      list(backend = "ollama",    model = "gemma4:latest",
           host   = "http://localhost:11434"),
      list(backend = "openai",    model = "gpt-4o-mini"),
      list(backend = "anthropic", model = "claude-sonnet-4-6")
    )

Failed backends (timeouts, missing API keys) emit a warning and
contribute zero claims; the vote continues with the remaining backends.

## See also

[`causal_llm_ingest_abstract_voted()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_abstract_voted.md)
for the KG-insertion wrapper;
[`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md)
for the single-backend call.

## Examples

``` r
if (FALSE) { # \dontrun{
  backends <- list(
    list(backend = "ollama",    model = "gemma4:latest"),
    list(backend = "openai",    model = "gpt-4o-mini"),
    list(backend = "anthropic", model = "claude-sonnet-4-6")
  )
  cons <- causal_llm_vote(
    abstract = "In Cerrado Oxisols, precipitation drives SOC...",
    backends = backends,
    voting   = "majority"
  )
  cons
} # }
```
