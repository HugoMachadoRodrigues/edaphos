# Export a reviewed JSONL into the canonical gold-standard format

Drops claims flagged as `rejected`, drops draft-only claims that have
not been reviewed, removes the internal `status` field, and re-validates
the result.

## Usage

``` r
llm_annotation_export(reviewed_path, output_path, include_rationale = TRUE)
```

## Arguments

- reviewed_path:

  Path to the reviewed JSONL (output of the Shiny reviewer).

- output_path:

  Path for the cleaned gold-standard JSONL.

- include_rationale:

  Logical; keep the `rationale` free-text field (default `TRUE`).

## Value

Invisibly, the list of records written.

## Examples

``` r
n_claims <- function(recs) sum(vapply(recs, function(r)
  if (is.data.frame(r$claims)) nrow(r$claims) else 0L, integer(1)))

draft <- system.file("extdata", "cerrado_gold_standard_v1_draft.jsonl",
                     package = "edaphos")

# The bundled draft holds 93 machine claims, every one still at
# status = "draft".  Export keeps NONE of them, and says so: 30
# abstracts, 0 claims.  "draft" means no human ever looked, and an
# unreviewed claim is not gold-standard evidence.
kept <- llm_annotation_export(draft, file.path(tempdir(), "hollow.jsonl"))
#> === Exported gold standard: /tmp/Rtmph4Y1fI/hollow.jsonl (30 abstracts, 0 claims) ===
n_claims(kept)
#> [1] 0

# Accept the first claim of each abstract and re-export.  Only the
# `status` string decides -- nothing else in the record matters.
reviewed <- file.path(tempdir(), "reviewed.jsonl")
writeLines(sub('"status":"draft"', '"status":"accepted"',
               readLines(draft, warn = FALSE), fixed = TRUE), reviewed)
n_claims(llm_annotation_export(reviewed, file.path(tempdir(), "g2.jsonl")))
#> === Exported gold standard: /tmp/Rtmph4Y1fI/g2.jsonl (30 abstracts, 30 claims) ===
#> [1] 30

# Back-compat trap in the other direction: the hand-annotated v1
# seed has no `status` column at all, and those claims are treated
# as already accepted, so all 72 survive.  A file with no statuses
# keeps everything; a file with only draft statuses keeps nothing.
gs <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
                  package = "edaphos")
once <- file.path(tempdir(), "once.jsonl")
c(once  = n_claims(llm_annotation_export(gs, once)),
  twice = n_claims(llm_annotation_export(
            once, file.path(tempdir(), "twice.jsonl"))))
#> === Exported gold standard: /tmp/Rtmph4Y1fI/once.jsonl (30 abstracts, 72 claims) ===
#> === Exported gold standard: /tmp/Rtmph4Y1fI/twice.jsonl (30 abstracts, 72 claims) ===
#>  once twice 
#>    72    72 

# Idempotent because `status` is stripped on the way out -- which
# also means you cannot re-review an exported file.  Keep the
# reviewed JSONL; the export is a derived artefact.

# `include_rationale = FALSE` drops the free-text justification,
# leaving the four fields llm_annotation_validate() requires.
names(llm_annotation_export(gs, file.path(tempdir(), "no_rat.jsonl"),
                            include_rationale = FALSE)[[1]]$claims)
#> === Exported gold standard: /tmp/Rtmph4Y1fI/no_rat.jsonl (30 abstracts, 72 claims) ===
#> [1] "cause"      "effect"     "polarity"   "confidence"
```
