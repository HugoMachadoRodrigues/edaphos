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

## Examples

``` r
if (FALSE) { # \dontrun{
  corpus <- data.frame(
    source = c("Jenny 1941", "Minasny et al. 2017", "Poggio 2021"),
    abstract = c(
      "Climate governs the accumulation of soil organic matter.",
      "Wetter sites accumulate more carbon at equal parent material.",
      "A purely descriptive survey of Cerrado profile morphology."
    ),
    stringsAsFactors = FALSE
  )

  # `cache_dir` is what makes a 10 000-abstract run survivable, so it
  # must OUTLIVE the R session. file.path(tempdir(), "cache") looks
  # right and is useless here: it is wiped on exit, and the next run
  # silently re-spends the whole corpus.
  cache <- "cerrado_llm_cache"
  kg <- causal_llm_ingest_corpus(
    causal_kg_new(), corpus,
    cache_dir = cache,
    backend   = "ollama",   # "openai" / "anthropic" read their key
    host      = "http://localhost:11434"   # from the environment
  )

  # Each row is keyed by md5("source|abstract"). Re-running after a
  # crash replays the stored claims rather than calling the LLM, so
  # cached rows cost nothing and an interrupted run is resumable;
  # editing one abstract re-queries that row alone.
  kg <- causal_llm_ingest_corpus(causal_kg_new(), corpus,
                                 cache_dir = cache)

  # Claims are cached UNFILTERED, so `min_confidence` is applied when
  # they are replayed. Re-thresholding a finished corpus therefore
  # costs nothing; only edges change, never the cache.
  kg_loose <- causal_llm_ingest_corpus(causal_kg_new(), corpus,
                                       cache_dir = cache,
                                       min_confidence = 0.3)

  # Read "failed" carefully. A row is listed there when it yielded NO
  # claims after `max_retries`, so a descriptive abstract that
  # correctly produces nothing is reported exactly like a row whose
  # LLM call kept erroring. It is not a list of network failures.
  attr(kg, "failed")

  # Supplying `progress` replaces the default txtProgressBar, which
  # is only shown for corpora of five rows or more.
  kg <- causal_llm_ingest_corpus(
    causal_kg_new(), corpus, cache_dir = cache,
    progress = function(i, n, source)
      message(sprintf("[%d/%d] %s", i, n, source))
  )
} # }
```
