# Match extracted LLM claims against a gold-standard set

Takes a data frame of extracted claims (from any backend) and a data
frame of gold-standard claims, and returns a per-claim match table with
TP / FP / FN labels.

## Usage

``` r
llm_benchmark_match(predicted, gold, fuzzy = TRUE, fuzzy_threshold = 2L)
```

## Arguments

- predicted:

  Data frame with columns `abstract_id`, `cause`, `effect` (and optional
  `confidence`). Every edge found by the backend for a given abstract.

- gold:

  Data frame with columns `abstract_id`, `cause`, `effect` (and optional
  `polarity`). One row per annotated claim.

- fuzzy:

  Logical; if `TRUE` (default), also count a predicted edge as TP when
  one of its endpoints matches by Levenshtein distance within
  `fuzzy_threshold`. If `FALSE`, require exact match on canonicalised
  labels.

- fuzzy_threshold:

  Integer; maximum edit distance for a fuzzy endpoint match. Default
  `2`.

## Value

A data frame with columns `abstract_id`, `cause`, `effect`, `status`
(one of `"tp"`, `"fp"`, `"fn"`), and `source` (either `"predicted"` or
`"gold"`).

## Details

Matching is done on the (cause, effect) pair after canonicalisation. A
predicted claim is a **true positive** if the canonicalised pair appears
in the gold set for the same abstract; a **false positive** if the pair
is not in gold; gold entries not in predictions are **false negatives**.
