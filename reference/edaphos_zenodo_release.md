# Build a Zenodo-ready release bundle for the edaphos package

Build a Zenodo-ready release bundle for the edaphos package

## Usage

``` r
edaphos_zenodo_release(
  output_dir,
  include_tarball = TRUE,
  title = NULL,
  description = NULL,
  authors = NULL,
  keywords = c("digital soil mapping", "causal inference", "foundation models",
    "quantum machine learning", "Cerrado", "pedometrics"),
  zip = TRUE
)
```

## Arguments

- output_dir:

  Directory to create (overwritten if it exists).

- include_tarball:

  Logical. If `TRUE` (default), also run
  [`devtools::build()`](https://devtools.r-lib.org/reference/build.html)
  and drop the resulting `.tar.gz` into the bundle. Requires the
  `devtools` package.

- title:

  Deposit title; defaults to a sensible package-level string with the
  current version.

- description:

  Free-text description (HTML allowed). Defaults to the package
  DESCRIPTION's Description field.

- authors:

  Data frame with `family_name`, `given_name`, optional `orcid`,
  optional `affiliation`. Defaults to a single- author entry for the
  package maintainer.

- keywords:

  Character vector of Zenodo keywords.

- zip:

  Logical; also produce a zip archive. Default `TRUE`.

## Value

Invisibly, the path of the created directory.
