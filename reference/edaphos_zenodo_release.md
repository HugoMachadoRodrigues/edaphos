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

## Examples

``` r
# `output_dir` is DELETED before it is written -- never point it at a
# directory that holds anything else.  Everything here stays inside
# tempdir(); suppressMessages() only hides the two [zenodo] progress
# lines the function prints.
out <- file.path(tempdir(), "edaphos-zenodo-demo")
dir.create(out, showWarnings = FALSE)
writeLines("not a release artefact", file.path(out, "keep_me.txt"))

# include_tarball = FALSE skips devtools::build(), which compiles the
# package found in getwd() rather than anything in `output_dir`; zip =
# FALSE skips utils::zip(), which needs a zip binary on the PATH.
suppressMessages(
  edaphos_zenodo_release(out, include_tarball = FALSE, zip = FALSE))
file.exists(file.path(out, "keep_me.txt"))     # FALSE -- unlink() ran
#> [1] FALSE

# Every shipped inst/extdata artefact is copied under bundles/.
shipped <- list.files(system.file("extdata", package = "edaphos"),
                      pattern = "[.](rds|jsonl)$")
c(shipped = length(shipped),
  copied  = length(list.files(file.path(out, "bundles"))))
#> shipped  copied 
#>      34      34 

# manifest.csv carries a size and a SHA-256 per file -- but it is
# written from a snapshot taken before itself and before
# ZENODO-README.md exist, so the table advertised as "checksums for
# every file" is missing exactly those two.
man <- read.csv(file.path(out, "manifest.csv"))
c(rows = nrow(man), files = length(list.files(out, recursive = TRUE)))
#>  rows files 
#>    37    39 
setdiff(list.files(out, recursive = TRUE), man$path)
#> [1] "ZENODO-README.md" "manifest.csv"    

# The checksums are real, though: recompute one and compare.
if (requireNamespace("digest", quietly = TRUE)) {
  i <- match("bundles/pilar10_gat_tuning.rds", man$path)
  print(identical(man$sha256[i],
                  digest::digest(file = file.path(out, man$path[i]),
                                 algo = "sha256")))
} else {
  print(all(is.na(man$sha256)))   # without digest the column is NA
}
#> [1] TRUE

# metadata.json is the DataCite block to paste into the Zenodo form.
# Its `version` is packageVersion("edaphos") -- the INSTALLED package --
# while a tarball built with include_tarball = TRUE comes from the
# DESCRIPTION in getwd().  Install the checkout before you release from
# it, or the deposit metadata can name a different version than the
# tarball beside it.
meta <- jsonlite::read_json(file.path(out, "metadata.json"))
unlist(meta$metadata[c("upload_type", "access_right", "license")])
#>  upload_type access_right      license 
#>   "software"       "open"        "mit" 
identical(meta$metadata$version, as.character(packageVersion("edaphos")))
#> [1] TRUE

# CITATION.cff, NEWS.md and README.md are snapshotted only if they can
# be found -- first in getwd(), then in the installed package -- so a
# bundle built outside a source checkout can be missing them.  Check
# before uploading.
intersect(c("CITATION.cff", "NEWS.md", "README.md"), list.files(out))
#> [1] "NEWS.md"   "README.md"

if (FALSE) { # \dontrun{
# The full deposit: tarball + zip archive.  devtools::build() runs on
# the package in the CURRENT working directory, so call this from a
# source checkout.  Upload is manual at https://zenodo.org/deposit/new
# -- the package never stores a Zenodo token.
edaphos_zenodo_release(file.path(tempdir(), "edaphos-zenodo"),
                       include_tarball = TRUE, zip = TRUE)
} # }
```
