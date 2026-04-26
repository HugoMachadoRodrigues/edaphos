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
