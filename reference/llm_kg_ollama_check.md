# Check whether a local Ollama server is reachable

Issues a 1-second HEAD request to the Ollama `/api/tags` endpoint and
reports whether the server responds. Used by
[`llm_kg_pipeline_run()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_kg_pipeline_run.md)
as a pre-flight gate.

## Usage

``` r
llm_kg_ollama_check(
  host = "http://localhost:11434",
  model = NULL,
  timeout_sec = 1
)
```

## Arguments

- host:

  Character; the base URL of the Ollama server. Default
  `"http://localhost:11434"`.

- model:

  Optional character; if supplied, additionally verifies that the named
  model is present on the server.

- timeout_sec:

  Numeric; HTTP timeout. Default `1`.

## Value

Named logical list with `reachable` (bool) and (when `model` is
non-NULL) `model_present` (bool).
