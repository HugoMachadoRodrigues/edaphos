# Run the Pilar 1 LLM-KG pipeline on a (potentially large) corpus

Drives
[`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md)
over a JSONL corpus of abstracts (one JSON object with `source` +
`abstract` per line) with resumable JSONL checkpointing and throttle /
retry. The function is engineered for 10 000+ abstract runs that can
take several hours to a day on a local Ollama instance.

## Usage

``` r
llm_kg_pipeline_run(
  corpus_path,
  output_path,
  backend = c("ollama", "openai", "anthropic"),
  model = NULL,
  host = "http://localhost:11434",
  temperature = 0,
  timeout_sec = 120,
  max_retries = 3L,
  min_confidence = 0.5,
  verbose = TRUE,
  max_abstracts = NULL
)
```

## Arguments

- corpus_path:

  Character path to a JSONL file with one
  `{"source": ..., "abstract": ...}` object per line.

- output_path:

  Character path to the JSONL claims output. Created on first run;
  appended on resume.

- backend:

  One of `"ollama"`, `"openai"`, `"anthropic"`.

- model:

  LLM model identifier; defaults to backend-appropriate.

- host:

  Ollama HTTP host (ignored for hosted backends).

- temperature:

  Numeric; LLM sampling temperature. Default `0`.

- timeout_sec:

  Numeric; per-call HTTP timeout. Default `120`.

- max_retries:

  Integer; transient-error retry budget. Default `3L`.

- min_confidence:

  Numeric; claims below this confidence are discarded. Default `0.5`.

- verbose:

  Logical; emit progress messages. Default `TRUE`.

- max_abstracts:

  Optional integer; for testing, cap the run.

## Value

Invisibly, a list with `n_processed`, `n_skipped`, `n_errors`, and the
final `kg` object.

## Resumability

On every successful per-abstract extraction, claims are appended to
`output_path` and the source identifier is appended to
`output_path.done`. When `llm_kg_pipeline_run()` is restarted on the
same `output_path`, abstracts whose source is already in the `.done`
file are skipped automatically. This makes the pipeline safe under
arbitrary process kills, network drops, or Ollama restarts.

## Throttle / retry

Transient errors (HTTP 5xx, timeouts, JSON parse failures) are retried
up to `max_retries` times with exponential back-off (1s, 2s, 4s, ...).
Persistent errors are logged to `output_path.errors` and skipped without
halting the run.
