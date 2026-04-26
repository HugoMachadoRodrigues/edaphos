# Simulate backend extractions from a gold-standard set

Produces a realistic noisy extraction from a gold-standard data frame by
sampling recall, false-positive rate and label-mutation probability for
each backend. Useful for offline reproducibility and CI builds where
real LLM APIs are unreachable.

## Usage

``` r
llm_benchmark_simulate(
  gold,
  recall = 0.82,
  precision_target = 0.86,
  mutate_rate = 0.05,
  seed = NULL
)
```

## Arguments

- gold:

  Gold-standard data frame with `abstract_id`, `cause`, `effect`.

- recall:

  Probability of keeping a gold claim.

- precision_target:

  Implicit: FP rate calibrated so precision lands near this target.

- mutate_rate:

  Probability of mutating an endpoint label.

- seed:

  Optional RNG seed.

## Value

Data frame with the same columns as `gold` plus `confidence`.

## Details

The simulator is **deterministic given a seed** and parameterised by the
three probabilities. Default profiles approximate published benchmarks
for the three backends (Gemma 4, GPT-4o-mini, Claude Sonnet-4.5) on
soil-science causal-claim extraction.
