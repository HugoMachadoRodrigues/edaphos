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
