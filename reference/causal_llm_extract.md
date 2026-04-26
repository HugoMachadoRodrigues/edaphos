# Extract causal claims from text via an LLM backend

Calls a Large Language Model and returns a tidy table of causal claims —
one row per extracted `(cause, effect)` pair — with the quoted evidence
and the confidence reported by the model.

## Usage

``` r
causal_llm_extract(
  text,
  backend = c("ollama", "openai", "anthropic"),
  model = NULL,
  host = "http://localhost:11434",
  temperature = 0,
  timeout_sec = 120,
  api_key = NULL
)
```

## Arguments

- text:

  Character scalar — the passage to annotate.

- backend:

  One of `"ollama"`, `"openai"`, `"anthropic"`.

- model:

  Optional model name; defaults vary by backend.

- host:

  Ollama server URL (ignored by the hosted backends).

- temperature:

  Sampling temperature. Defaults to `0` for reproducibility.

- timeout_sec:

  Request timeout in seconds.

- api_key:

  Optional API key overriding the environment variable.

## Value

A data frame with columns `cause`, `effect`, `evidence`, `confidence`.
Empty (zero rows) when the model returns no claims or the response
cannot be parsed.

## Details

Three backends are supported via a uniform prompt:

- `"ollama"` — local, zero-cost Ollama server (default
  `host = "http://localhost:11434"`, default model `"gemma4:latest"`).
  For higher extraction quality switch to `model = "gemma4:26b"`.

- `"openai"` — OpenAI Chat Completions API with JSON mode; needs the
  `OPENAI_API_KEY` environment variable (default model `"gpt-4o-mini"`).

- `"anthropic"` — Claude Messages API; needs `ANTHROPIC_API_KEY`
  (default model `"claude-sonnet-4-5"`).

The return value is backend-independent, so downstream
[`causal_llm_ingest_abstract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_abstract.md)
and
[`causal_kg_add_edge()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_add_edge.md)
work the same regardless of which model produced the claims.

## Examples

``` r
if (FALSE) { # \dontrun{
  abstract <- "In Cerrado soils, higher mean annual precipitation is
    associated with significantly increased topsoil organic carbon."
  causal_llm_extract(abstract, backend = "ollama",
                     model = "gemma4:latest")
} # }
```
