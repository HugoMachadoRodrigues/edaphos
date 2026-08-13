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

  Data frame with one row per creator and all four of `family_name`,
  `given_name`, `orcid`, `affiliation` as columns. The `orcid` and
  `affiliation` *values* may be `NA` (the field is then omitted from
  that creator) but the *columns* must be present, or creator assembly
  fails. Defaults to a single hard-coded entry for the package
  maintainer.

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

## Examples

``` r
gs <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
                  package = "edaphos")
bundle <- file.path(tempdir(), "cerrado_kg_deposit")

# `zip = FALSE` because utils::zip() shells out to an external
# `zip` executable that is not present everywhere.  Pass `version`
# explicitly too: it defaults to Sys.Date(), so metadata.json and
# README.md otherwise differ on every run and the bundle is not
# reproducible.
llm_annotation_to_zenodo(gs, bundle,
                         title = "Cerrado gold-standard KG (v1)",
                         version = "1.0.0", zip = FALSE)
#> === Exported gold standard: /tmp/RtmpNvtEGq/cerrado_kg_deposit/gold_standard.jsonl (30 abstracts, 72 claims) ===
#> === Zenodo bundle ready: /tmp/RtmpNvtEGq/cerrado_kg_deposit ===
sort(list.files(bundle))
#> [1] "README.md"           "gold_standard.jsonl" "kg.ttl"             
#> [4] "metadata.json"      

# The 72 accepted claims become 72 reified rdf:Statement blocks,
# plus 30 eda:Abstract provenance nodes carrying title and year.
ttl <- readLines(file.path(bundle, "kg.ttl"), warn = FALSE)
c(statements = sum(grepl("a rdf:Statement", ttl, fixed = TRUE)),
  abstracts  = sum(grepl("a eda:Abstract", ttl, fixed = TRUE)))
#> statements  abstracts 
#>         72         30 

# The licence is lower-cased into metadata.json on purpose: that is
# the identifier the Zenodo REST API expects, not the SPDX spelling
# you passed in.
md <- jsonlite::fromJSON(file.path(bundle, "metadata.json"))
c(license = md$metadata$license, version = md$metadata$version)
#>     license     version 
#> "cc-by-4.0"     "1.0.0" 

# Trap: this runs llm_annotation_export() internally, so a reviewed
# file whose claims are all still "draft" produces a bundle that
# SUCCEEDS, prints its usual banner, and contains zero statements.
# Check the count before you mint a DOI, not the exit status.
draft <- system.file("extdata", "cerrado_gold_standard_v1_draft.jsonl",
                     package = "edaphos")
hollow <- file.path(tempdir(), "hollow_deposit")
llm_annotation_to_zenodo(draft, hollow, version = "1.0.0", zip = FALSE)
#> === Exported gold standard: /tmp/RtmpNvtEGq/hollow_deposit/gold_standard.jsonl (30 abstracts, 0 claims) ===
#> === Zenodo bundle ready: /tmp/RtmpNvtEGq/hollow_deposit ===
sum(grepl("a rdf:Statement",
          readLines(file.path(hollow, "kg.ttl"), warn = FALSE), fixed = TRUE))
#> [1] 0

# `authors` must carry all four columns.  NA values are fine and
# omit that field from the creator, but a missing COLUMN aborts
# part-way through, leaving a half-written directory behind.
who <- data.frame(family_name = c("Silva", "Costa"),
                  given_name  = c("Ana", "Bruno"),
                  orcid       = c("0000-0001-2345-6789", NA),
                  affiliation = c("Embrapa Cerrados", NA),
                  stringsAsFactors = FALSE)
authored <- file.path(tempdir(), "authored_deposit")
llm_annotation_to_zenodo(gs, authored, authors = who,
                         version = "1.0.0", zip = FALSE)
#> === Exported gold standard: /tmp/RtmpNvtEGq/authored_deposit/gold_standard.jsonl (30 abstracts, 72 claims) ===
#> === Zenodo bundle ready: /tmp/RtmpNvtEGq/authored_deposit ===
jsonlite::fromJSON(file.path(authored, "metadata.json"),
                   simplifyVector = FALSE)$metadata$creators
#> [[1]]
#> [[1]]$name
#> [1] "Silva, Ana"
#> 
#> [[1]]$orcid
#> [1] "0000-0001-2345-6789"
#> 
#> [[1]]$affiliation
#> [1] "Embrapa Cerrados"
#> 
#> 
#> [[2]]
#> [[2]]$name
#> [1] "Costa, Bruno"
#> 
#> 
```
