# Estimate per-1 000-claim extraction cost

Uses published list prices as of 2026-04: Gemma 4 local \$0, GPT-4o-mini
input \$0.15 / 1M tokens + output \$0.60 / 1M tokens, Claude Sonnet-4.5
input \$3 / 1M + output \$15 / 1M. Assumes mean abstract is 220 tokens
in + 110 tokens out + 480 tokens of system prompt.

## Usage

``` r
llm_benchmark_cost(
  backend,
  model = NULL,
  n_abstracts = 100L,
  claims_per_abstract = 5,
  tokens_in = 700L,
  tokens_out = 110L
)
```

## Arguments

- backend:

  String, one of `"ollama"`, `"openai"`, `"anthropic"`.

- model:

  Optional exact model id for documentation.

- n_abstracts:

  Integer; number of abstracts the extractor ran on.

- claims_per_abstract:

  Numeric; mean claims per abstract (for per-1k-claim normalisation).

- tokens_in:

  Integer; mean input tokens per call.

- tokens_out:

  Integer; mean output tokens per call.

## Value

Named list with cost per 1 000 claims in USD.
