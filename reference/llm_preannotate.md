# Pre-annotate a corpus with an LLM to produce draft claims

Runs
[`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md)
(real Ollama / OpenAI / Anthropic) or the deterministic
[`llm_benchmark_simulate()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_benchmark_simulate.md)
fallback over every abstract in the corpus, and writes a **draft JSONL**
in the same schema as `cerrado_gold_standard_v1.jsonl` but with `claims`
marked `status = "draft"` so the Shiny reviewer can distinguish
machine-generated entries from human-added ones.

## Usage

``` r
llm_preannotate(
  corpus,
  backend = c("ollama", "openai", "anthropic", "simulator"),
  model = NULL,
  output_path = "cerrado_draft_gold.jsonl",
  cache_dir = NULL,
  max_abstracts = NULL,
  verbose = TRUE,
  ...
)
```

## Arguments

- corpus:

  Either a path to a JSONL file with one record per line (records must
  have `abstract_id` and `abstract_text`), or a list of records already
  in memory.

- backend:

  One of `"ollama"`, `"openai"`, `"anthropic"`, `"simulator"`. When
  `"simulator"` the function uses
  [`llm_benchmark_simulate()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_benchmark_simulate.md)
  against a pseudo-gold-standard derived from the abstract's first
  sentence – useful for demos and CI builds without API access. Defaults
  to `"ollama"` with `gemma4:latest`.

- model:

  Optional model id. Defaults to `"gemma4:latest"` for Ollama.

- output_path:

  Path to write the draft JSONL.

- cache_dir:

  Optional directory for per-record JSON caches. When set, re-running
  the function over the same corpus short-circuits to cached
  extractions, so interrupted jobs resume exactly where they left off.
  Defaults to `NULL` (no cache).

- max_abstracts:

  Optional integer cap on how many abstracts to process (useful for
  staged runs).

- verbose:

  Logical; print per-abstract progress.

- ...:

  Forwarded to
  [`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md).

## Value

Invisibly, the list of records written.
