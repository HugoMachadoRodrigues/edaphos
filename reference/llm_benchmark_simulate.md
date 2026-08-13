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

  Probability of keeping a gold claim. This is the sampling probability,
  not the recall you will measure: mutation happens after sampling, so
  the realised recall is lower.

- precision_target:

  Used only to derive the false-positive rate, assuming no mutation.
  With `mutate_rate > 0` the realised precision falls below this target,
  because every mutated endpoint converts a true positive into a false
  positive.

- mutate_rate:

  Probability of mutating an endpoint label.

- seed:

  Optional RNG seed. Pass one: without it the output, including its row
  count, differs between calls.

## Value

Data frame with columns `abstract_id`, `cause`, `effect` and
`confidence`. Any other column of `gold` (`polarity`, for instance) is
dropped.

## Details

The simulator is **deterministic given a seed** and parameterised by the
three probabilities. Default profiles approximate published benchmarks
for the three backends (Gemma 4, GPT-4o-mini, Claude Sonnet-4.5) on
soil-science causal-claim extraction.

## Examples

``` r
res_path <- system.file("extdata", "llm_benchmark_results.rds",
                        package = "edaphos")
if (nzchar(res_path)) {
  B <- readRDS(res_path)

  # Always pass `seed`.  Without one even the row count moves.
  print(identical(llm_benchmark_simulate(B$gold_df, seed = 42L),
                  llm_benchmark_simulate(B$gold_df, seed = 42L)))

  # The shipped benchmark bundle IS this function, not an API call:
  # replaying the Gemma 4 profile from data-raw/llm_benchmark_run.R
  # reproduces its row of `metrics_table` to the digit.
  sim <- llm_benchmark_simulate(B$gold_df, recall = 0.80,
                                precision_target = 0.85,
                                mutate_rate = 0.06, seed = 101L)
  m <- llm_benchmark_metrics(llm_benchmark_match(sim, B$gold_df))
  print(rbind(
    replayed = round(unlist(m[c("precision", "recall", "f1")]), 4),
    shipped  = round(unlist(
      B$metrics_table[1, c("precision", "recall", "f1")]), 4)))

  # `recall` and `precision_target` are knobs on the sampler, not
  # properties of the output: 0.80 and 0.85 in give 0.667 and 0.750
  # out.  `mutate_rate` is why -- it corrupts endpoint labels AFTER
  # sampling, so each mutation costs one TP and adds one FP, pushing
  # both metrics down at once.
  for (mr in c(0, 0.05, 0.20)) {
    s <- llm_benchmark_simulate(B$gold_df, recall = 0.82,
                                precision_target = 0.90,
                                mutate_rate = mr, seed = 7L)
    mm <- llm_benchmark_metrics(llm_benchmark_match(s, B$gold_df))
    cat(sprintf("mutate_rate %.2f -> precision %.4f (target 0.90)\n",
                mr, mm$precision))
  }

  # The mutation writes "<label>_alt", four edits away, so the
  # default fuzzy_threshold of 2 recovers none of it and a threshold
  # of 4 recovers all of it: F1 0.706 -> 0.824.  That single line of
  # the scoring rule moves F1 further (+0.118) than the whole spread
  # between the three simulated backends (0.116).  Fix the rule
  # before you compare models.
  if (requireNamespace("stringdist", quietly = TRUE)) {
    print(round(vapply(c(2L, 4L), function(th)
      llm_benchmark_metrics(llm_benchmark_match(
        sim, B$gold_df, fuzzy_threshold = th))$f1, numeric(1)), 4))
  }

  # `polarity` does not survive, although it is right there in the
  # gold frame -- so a downstream KG built from simulated claims
  # cannot be scored on the sign of the effect, only on its
  # existence.
  print(names(sim))
}
#> [1] TRUE
#>          precision recall     f1
#> replayed      0.75 0.6667 0.7059
#> shipped       0.75 0.6667 0.7059
#> mutate_rate 0.00 -> precision 0.8696 (target 0.90)
#> mutate_rate 0.05 -> precision 0.8261 (target 0.90)
#> mutate_rate 0.20 -> precision 0.6377 (target 0.90)
#> [1] 0.7059 0.8235
#> [1] "abstract_id" "cause"       "effect"      "confidence" 
```
