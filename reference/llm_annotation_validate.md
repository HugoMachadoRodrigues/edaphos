# Validate a gold-standard JSONL file

Checks every record for required fields, every claim for required
fields, that `cause` / `effect` belong to the canonical vocabulary
(unless `strict_vocab = FALSE`), that `polarity` is `"+"` or `"-"`, and
that `confidence` is in `[0, 1]`.

## Usage

``` r
llm_annotation_validate(path, strict_vocab = TRUE)
```

## Arguments

- path:

  Path to the JSONL file.

- strict_vocab:

  Logical; if `TRUE` (default), flag any `cause` or `effect` outside
  [`llm_annotation_vocabulary()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_annotation_vocabulary.md).

## Value

Named list with `ok` (logical), `errors` (character vector) and
`summary` (data frame with per-record counts).

## Examples

``` r
gs <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
                  package = "edaphos")
v <- llm_annotation_validate(gs)
v$ok
#> [1] TRUE

# The v1 seed: 30 abstracts, 72 claims, 1 to 5 claims each, clean
# under the strict vocabulary.
c(records = nrow(v$summary), claims = sum(v$summary$n_claims))
#> records  claims 
#>      30      72 
range(v$summary$n_claims)
#> [1] 1 5

# A file with one of each failure mode.  The second record has no
# `claims` key at all.
bad <- file.path(tempdir(), "bad.jsonl")
writeLines(c(
  paste0('{"abstract_id":"BAD_01","abstract_text":"Tree cover raised SOC.",',
         '"claims":[{"cause":"tree_cover","effect":"soc",',
         '"polarity":"positive","confidence":0.8},',
         '{"cause":"clay","effect":"soc","polarity":"+",',
         '"confidence":1.4}]}'),
  '{"abstract_id":"BAD_02","abstract_text":"No claims field at all."}'
), bad)
llm_annotation_validate(bad)$errors
#> [1] "BAD_01: 1 claim(s) with invalid polarity"        
#> [2] "BAD_01: 1 claim(s) with confidence outside [0,1]"
#> [3] "BAD_01: 1 claim(s) with non-canonical vocabulary"
#> [4] "BAD_02: missing required field(s) claims"        

# `strict_vocab = FALSE` retires the vocabulary error only -- the
# polarity and confidence checks always run.  Use it while a new
# term like "tree_cover" is still being argued about, not to make a
# file pass.
llm_annotation_validate(bad, strict_vocab = FALSE)$errors
#> [1] "BAD_01: 1 claim(s) with invalid polarity"        
#> [2] "BAD_01: 1 claim(s) with confidence outside [0,1]"
#> [3] "BAD_02: missing required field(s) claims"        

# Read `summary` next to `errors`, never alone: a record that fails
# the required-field check is skipped before it is counted, so
# BAD_02 has no row and nrow(summary) is not the file's length.
c(rows_in_summary = nrow(llm_annotation_validate(bad)$summary),
  lines_in_file   = length(readLines(bad, warn = FALSE)))
#> rows_in_summary   lines_in_file 
#>               1               2 

# And `ok` is a schema verdict, not a coverage one.  An export that
# dropped every claim validates perfectly, so gate a deposit on the
# claim count as well.
empty <- file.path(tempdir(), "empty.jsonl")
writeLines('{"abstract_id":"E_01","abstract_text":"x","claims":[]}', empty)
e <- llm_annotation_validate(empty)
e$ok
#> [1] TRUE
sum(e$summary$n_claims)
#> [1] 0
```
