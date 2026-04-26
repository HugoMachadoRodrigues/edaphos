# Package a reviewed gold-standard into a Zenodo-ready deposit bundle

Generates a self-contained directory (and optionally a zip archive) that
can be uploaded to Zenodo to mint a permanent DOI for the gold-standard.
Bundle contents:

## Usage

``` r
llm_annotation_to_zenodo(
  reviewed_path,
  output_dir,
  title = "Cerrado gold-standard KG (edaphos)",
  authors = NULL,
  description = NULL,
  keywords = c("soil science", "pedometrics", "causal inference", "knowledge graph",
    "Cerrado"),
  license = "CC-BY-4.0",
  version = NULL,
  zip = TRUE
)
```

## Arguments

- reviewed_path:

  Path to the reviewed JSONL.

- output_dir:

  Directory to create. Will be made if it doesn't exist. Existing
  contents are overwritten.

- title:

  Deposit title (will appear on Zenodo).

- authors:

  Data frame with `family_name`, `given_name`, optional `orcid`,
  optional `affiliation` per row. Defaults to a single-author entry
  using [`utils::maintainer()`](https://rdrr.io/r/utils/maintainer.html)
  on the package.

- description:

  Free-text description (HTML allowed). Defaults to a short summary
  including abstract / claim counts.

- keywords:

  Character vector of keyword tags.

- license:

  Licence identifier (default `"CC-BY-4.0"`).

- version:

  Optional version string to embed in metadata.json.

- zip:

  Logical; when `TRUE` (default), also produce a `<output_dir>.zip`
  alongside the directory.

## Value

Invisibly, the path to the created directory.

## Details

- `gold_standard.jsonl` – cleaned gold-standard (drafts / rejected
  removed, identical to
  [`llm_annotation_export()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_annotation_export.md)
  output).

- `kg.ttl` – RDF 1.1 Turtle representation of the aggregated KG built by
  treating each accepted claim as a directed edge.

- `metadata.json` – DataCite-compatible metadata ready for the Zenodo
  REST API. Also usable as a source for a manual upload via the Zenodo
  web UI.

- `README.md` – Human-readable description with schema, annotator,
  extractor, date, counts, citation.

The function does NOT upload to Zenodo automatically (Zenodo requires a
personal access token which should never be hard-coded). After the
bundle is built the user uploads the zip / files manually at
<https://zenodo.org/deposit/new> and records the minted DOI back into
the package's CITATION.cff / .zenodo.json.
