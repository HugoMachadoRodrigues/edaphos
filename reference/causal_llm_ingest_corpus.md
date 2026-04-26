# Ingest a corpus of abstracts into a Knowledge Graph (resumable)

Batched variant of
[`causal_llm_ingest_abstract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_abstract.md).
Runs the LLM extractor sequentially over a data frame of abstracts,
optionally persisting per-abstract claim tables to a `cache_dir` so that
multi-hour / multi-day ingestion runs can be interrupted and resumed
without re-spending LLM compute.

## Usage

``` r
causal_llm_ingest_corpus(
  kg,
  abstracts,
  abstract_col = "abstract",
  source_col = "source",
  min_confidence = 0.5,
  cache_dir = NULL,
  max_retries = 2L,
  progress = NULL,
  ...
)
```

## Arguments

- kg:

  An `edaphos_causal_kg`.

- abstracts:

  Data frame with one row per abstract.

- abstract_col, source_col:

  Column names in `abstracts` holding the text and the provenance key
  respectively.

- min_confidence:

  Minimum confidence for an extracted claim to be inserted into the KG.

- cache_dir:

  Optional directory for per-row cached JSON responses. Enables
  resumable runs.

- max_retries:

  Integer — how many times to retry a failed LLM call before giving up
  on that row.

- progress:

  Optional `function(i, n, source)` callback. When `NULL`, a
  `txtProgressBar` is shown.

- ...:

  Forwarded to
  [`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md)
  (`backend`, `model`, `host`, `temperature`, `timeout_sec`, `api_key`).

## Value

Updated `edaphos_causal_kg`. A `"failed"` attribute lists the rows (if
any) that exhausted all retries.

## Details

Every row's `(source, abstract)` pair is hashed into a stable filename;
when `cache_dir` is supplied and a cached JSON file already exists for a
row, the LLM call is skipped and the cached claims are replayed into the
KG. Failed rows (malformed JSON, timeouts) are retried up to
`max_retries` times with exponential backoff. Progress reporting uses
base R's `txtProgressBar` unless a custom `progress` callback is passed.

At 10 000+ abstracts the cache is what makes the workflow operationally
possible: re-running the function after any crash picks up where the
cache left off, and warm re-runs are near- instantaneous.
