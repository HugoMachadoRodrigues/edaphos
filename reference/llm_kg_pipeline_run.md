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

## Examples

``` r
# Everything outside \dontrun{} below runs offline: the corpus is
# arranged so that no record ever reaches an LLM.  The pipeline
# opens an `edaphos_causal_kg` on every path, so it needs igraph
# (a Suggests) even when it extracts nothing -- and R CMD check
# --as-cran does execute this block.
if (requireNamespace("igraph", quietly = TRUE)) {

  corpus <- tempfile(fileext = ".jsonl")
  out    <- tempfile(fileext = ".jsonl")
  writeLines(c(
    '{"source":"silva2021","abstract":"MAP raised topsoil SOC."}',
    '{"source":"reis2019","abstract":""}',
    '{"source":"castro2020","abstract":"Clay content'  # truncated
  ), corpus)

  # What a run killed half way through leaves behind: two claims in
  # the output file and one source logged in the `.done` sidecar.
  claim <- function(cause, conf)
    jsonlite::toJSON(list(cause = cause, effect = "soil organic carbon",
                          evidence = "quoted from the abstract",
                          confidence = conf, source = "silva2021"),
                     auto_unbox = TRUE)
  writeLines(c(claim("mean annual precipitation", 0.9),
               claim("clay content", 0.7)), out)
  writeLines("silva2021", paste0(out, ".done"))

  # `backend = "openai"` skips the Ollama pre-flight, and the
  # hosted backends have no pre-flight of their own: the API key is
  # read only once an abstract is actually sent.  Here none is.
  res <- llm_kg_pipeline_run(corpus, out, backend = "openai",
                             verbose = FALSE)
  print(c(res$n_processed, res$n_skipped, res$n_errors))   # 0 1 1

  # Read those three next to the corpus size: they account for 2 of
  # 3 lines.  The truncated JSON is dropped at parse time and is
  # invisible -- not an error, not a skip, never in `.errors`.
  print(length(readLines(corpus)))                         # 3

  # An EMPTY abstract, by contrast, is charged as an error and
  # logged.  Errors are logged and stepped over, never fatal.
  print(readLines(paste0(out, ".errors")))  # "[reis2019]\tempty abstract"

  # The trap: `res$kg` holds only the edges extracted in THIS call.
  # Resumed sources are skipped and their claims are never read
  # back from `output_path`, so the returned graph is empty while
  # the claims file has two rows.  Never treat `res$kg` as the
  # accumulated graph of a resumed job.
  print(nrow(causal_kg_edges(res$kg)))      # 0
  print(length(readLines(out)))             # 2

  # The claims file is the durable artefact; rebuild the graph from
  # it.  Node labels are normalised on insertion, so the two rows
  # become mean_annual_precipitation -> soil_organic_carbon and
  # clay_content -> soil_organic_carbon.
  prev <- jsonlite::stream_in(file(out), verbose = FALSE)
  kg <- causal_kg_new()
  for (i in seq_len(nrow(prev)))
    kg <- causal_kg_add_edge(kg, prev$cause[i], prev$effect[i],
                             source     = prev$source[i],
                             evidence   = prev$evidence[i],
                             confidence = prev$confidence[i])
  print(causal_kg_edges(kg)[, c("cause", "effect", "confidence")])

  unlink(c(corpus, out, paste0(out, c(".done", ".errors"))))
}
#> [1] 0 1 1
#> [1] 3
#> [1] "[reis2019]\tempty abstract"
#> [1] 0
#> [1] 2
#>                       cause              effect confidence
#> 1 mean_annual_precipitation soil_organic_carbon        0.9
#> 2              clay_content soil_organic_carbon        0.7

# A missing credential is treated as a TRANSIENT failure: it is put
# on the back-off ladder and then written off, instead of failing
# fast.  Guarded on the key so that a reader who has one is not
# billed for a live call by running this example.
if (requireNamespace("igraph", quietly = TRUE) &&
    !nzchar(Sys.getenv("OPENAI_API_KEY"))) {
  corpus <- tempfile(fileext = ".jsonl")
  out    <- tempfile(fileext = ".jsonl")
  writeLines('{"source":"silva2021","abstract":"MAP raised SOC."}', corpus)

  res <- llm_kg_pipeline_run(corpus, out, backend = "openai",
                             max_retries = 0L, verbose = FALSE)
  print(res$n_errors)                       # 1
  print(readLines(paste0(out, ".errors")))  # "Set OPENAI_API_KEY ..."
  print(file.exists(out))                   # FALSE -- an all-error
                                            # run never creates
                                            # output_path at all

  # `max_retries = 0L` is what makes that instant.  At the default
  # 3L the very same missing key costs the full back-off ladder,
  # 1 + 2 + 4 = 7 s, per abstract before it is written off -- so on
  # the 10 000-abstract corpus this function exists for, about 20 h
  # of sleeping and not one claim.  Check credentials yourself
  # before the run; the pipeline will not do it for you.
  unlink(c(corpus, paste0(out, ".errors")))
}
#> [1] 1
#> [1] "[silva2021]\tSet OPENAI_API_KEY or pass `api_key`."
#> [1] FALSE

if (FALSE) { # \dontrun{
# The networked path.  No key is ever passed as an argument: each
# backend reads its own environment variable, and `host` reaches
# exactly one of them.
#   "ollama"    -- no key; POSTs to <host>/api/chat
#   "openai"    -- OPENAI_API_KEY;    `host` ignored
#   "anthropic" -- ANTHROPIC_API_KEY; `host` ignored

# Pass `model` explicitly.  The pre-flight only checks the model
# when it is non-NULL, so leaving it NULL starts the run happily
# and then fails on every single abstract if the default
# "gemma4:latest" was never pulled.
res <- llm_kg_pipeline_run(
  corpus_path    = "cerrado_10k.jsonl",   # {source, abstract} per line
  output_path    = "cerrado_claims.jsonl",
  backend        = "ollama",
  model          = "gemma4:latest",
  min_confidence = 0.6,
  max_abstracts  = 250L
)
res$n_processed

# `min_confidence` is applied before anything is written, and the
# source is marked done even when the filter left nothing.  So
# raising the threshold on a resumed run is a no-op, and lowering
# it does not revisit what is already in `.done`: delete
# <output_path>.done to re-extract a corpus at a new threshold.
causal_kg_edges(res$kg)[, c("cause", "effect", "confidence")]
} # }
```
