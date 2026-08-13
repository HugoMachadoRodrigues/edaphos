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
  the Levenshtein distances of its two endpoints *sum* to no more than
  `fuzzy_threshold`. If `FALSE`, require exact match on canonicalised
  labels. Fuzzy matching needs the suggested package stringdist; without
  it `fuzzy = TRUE` silently degrades to exact matching.

- fuzzy_threshold:

  Integer; maximum Levenshtein distance summed over the cause and the
  effect. Default `2`.

## Value

A data frame with columns `abstract_id`, `cause`, `effect`, `status`
(one of `"tp"`, `"fp"`, `"fn"`), and `source` (either `"predicted"` or
`"gold"`).

## Details

Matching is done on the (cause, effect) pair after canonicalisation. A
predicted claim is a **true positive** if the canonicalised pair appears
in the gold set for the same abstract; a **false positive** if the pair
is not in gold; gold entries not in predictions are **false negatives**.

## Examples

``` r
# The package ships a 30-abstract Cerrado gold standard.  Flatten
# its nested `claims` arrays into the one-row-per-edge frame the
# matcher expects.
gold_path <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
                         package = "edaphos")
if (nzchar(gold_path)) {
  recs <- lapply(readLines(gold_path), jsonlite::fromJSON)
  gold <- do.call(rbind, lapply(recs, function(r) data.frame(
    abstract_id = r$abstract_id, cause = r$claims$cause,
    effect      = r$claims$effect, stringsAsFactors = FALSE)))
  print(c(abstracts = length(recs), claims = nrow(gold)))

  # CER_01 is a rainfall / temperature / SOC abstract with five gold
  # claims.  Below is an extraction a pedologist would call four out
  # of four correct -- only the surface strings differ from the
  # annotator's.  Three score TP, one scores FP.
  cer1 <- gold[gold$abstract_id == "CER_01", ]
  pred <- data.frame(
    abstract_id = "CER_01",
    cause  = c("Rainfall", "MAP",        "mean annual temperature",
               "tree cover"),
    effect = c("TOC",      "tree cover", "Corg", "organic carbon"),
    stringsAsFactors = FALSE)
  print(llm_benchmark_match(pred, cer1))

  # P = 0.75, R = 0.60, and BOTH losses are the matching rule rather
  # than the model:
  #  * "Rainfall" canonicalises to `precipitation`, the annotator
  #    wrote `mean_annual_precipitation`, and the normaliser keeps
  #    those deliberately apart -- so the same claim is scored as a
  #    false positive AND leaves the gold edge as a false negative.
  #  * gold lists `mean_annual_temperature -> soc` TWICE for CER_01,
  #    and matching is one-to-one, so one predicted edge clears only
  #    one of the pair.
  print(round(unlist(llm_benchmark_metrics(
    llm_benchmark_match(pred, cer1))[
      c("tp", "fp", "fn", "precision", "recall")]), 3))

  # That duplicate caps the whole benchmark.  Feed gold back as its
  # own prediction, deduplicated the way any extractor would emit it,
  # and recall stops at 71/72 -- no model can score 1.
  ded <- gold[!duplicated(paste(gold$abstract_id, gold$cause,
                                gold$effect)), ]
  print(round(unlist(llm_benchmark_metrics(
    llm_benchmark_match(ded, gold))[c("tp", "fn", "recall")]), 4))

  # Trap: `fuzzy = TRUE` is the default, but it changes nothing here.
  # The threshold is the SUM over both endpoints, and no
  # predicted/gold pair in this vocabulary sits within 2 edits
  # without already matching exactly.  Report the threshold you used
  # next to F1 -- see llm_benchmark_simulate() for what raising it
  # does.
  print(identical(llm_benchmark_match(ded, gold, fuzzy = TRUE),
                  llm_benchmark_match(ded, gold, fuzzy = FALSE)))
}
#> abstracts    claims 
#>        30        72 
#>            abstract_id                     cause     effect status    source
#> CER_01_p.1      CER_01             precipitation        soc     fp predicted
#> CER_01_p.2      CER_01 mean_annual_precipitation vegetation     tp predicted
#> CER_01_p.3      CER_01   mean_annual_temperature        soc     tp predicted
#> CER_01_p.4      CER_01                vegetation        soc     tp predicted
#> CER_01_g.1      CER_01 mean_annual_precipitation        soc     fn      gold
#> CER_01_g.2      CER_01   mean_annual_temperature        soc     fn      gold
#>        tp        fp        fn precision    recall 
#>      3.00      1.00      2.00      0.75      0.60 
#>      tp      fn  recall 
#> 71.0000  1.0000  0.9861 
#> [1] TRUE
```
