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

## Examples

``` r
# List prices, not invoices: published per-token rates times assumed
# token counts (700 in / 110 out).  Nothing is measured.
str(llm_benchmark_cost("anthropic", model = "claude-sonnet-4-5",
                       n_abstracts = 30L, claims_per_abstract = 2.4))
#> List of 6
#>  $ backend               : chr "anthropic"
#>  $ model                 : chr "claude-sonnet-4-5"
#>  $ n_abstracts           : int 30
#>  $ n_claims              : num 72
#>  $ cost_total_usd        : num 0.113
#>  $ cost_per_1k_claims_usd: num 1.56

# Scaling a Cerrado systematic review to 10 000 abstracts.  The
# local model reads $0 because list price is all this function
# knows -- it is blind to the GPU, and to the 15.9 s/abstract that
# the shipped latency summary records for Gemma 4 against 3.0 s for
# GPT-4o-mini.
round(c(
  ollama    = llm_benchmark_cost("ollama",
                                 n_abstracts = 10000L)$cost_total_usd,
  openai    = llm_benchmark_cost("openai",
                                 n_abstracts = 10000L)$cost_total_usd,
  anthropic = llm_benchmark_cost("anthropic",
                                 n_abstracts = 10000L)$cost_total_usd), 2)
#>    ollama    openai anthropic 
#>      0.00      1.71     37.50 

# Trap 1: `n_abstracts` cancels out of `cost_per_1k_claims_usd`.
# That headline is a function of the token assumptions and
# `claims_per_abstract` alone and says nothing about your corpus.
c(n30 = llm_benchmark_cost("openai", n_abstracts = 30L,
         claims_per_abstract = 2.4)$cost_per_1k_claims_usd,
  n10k = llm_benchmark_cost("openai", n_abstracts = 10000L,
          claims_per_abstract = 2.4)$cost_per_1k_claims_usd)
#>     n30    n10k 
#> 0.07125 0.07125 

# Trap 2: an unrecognised backend returns NA prices rather than
# erroring, so a typo quietly turns a paid model into a free one.
llm_benchmark_cost("gemini", n_abstracts = 30L)$cost_total_usd
#> [1] NA

# Trap 3: the denominator is claims EXTRACTED, not claims CORRECT,
# so over-extraction buys a cheaper headline.  Re-normalise on the
# true positives from the shipped benchmark and both backends get
# dearer -- GPT by 1.43x, Claude by 1.22x -- and the advertised 22x
# price gap between them narrows to 19x.
res_path <- system.file("extdata", "llm_benchmark_results.rds",
                        package = "edaphos")
if (nzchar(res_path)) {
  mt <- readRDS(res_path)$metrics_table   # rows: Gemma, GPT, Claude
  per1k <- function(bk, claims) llm_benchmark_cost(
    bk, n_abstracts = 30L,
    claims_per_abstract = claims / 30)$cost_per_1k_claims_usd
  print(round(rbind(
    openai    = c(all = per1k("openai",    mt$n_claims[2]),
                  tp  = per1k("openai",    mt$tp[2])),
    anthropic = c(all = per1k("anthropic", mt$n_claims[3]),
                  tp  = per1k("anthropic", mt$tp[3]))), 4))
}
#>              all     tp
#> openai    0.0703 0.1006
#> anthropic 1.5625 1.9068
```
