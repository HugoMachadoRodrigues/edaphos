# Provenance for a generated data bundle

Builds the block every `data-raw/` script attaches to the object it
saves, so a shipped bundle names the script that produced it and carries
a hash of that script's content.

## Usage

``` r
edaphos_provenance(script = NULL, ...)
```

## Arguments

- script:

  Path to the producing script, relative to the package root (e.g.
  `"data-raw/piml_depth_benchmark.R"`). When `NULL`, it is derived from
  the running script's own path, which is what a `data-raw` script wants
  and cannot easily determine itself.

- ...:

  Extra named fields to record alongside — anything the script knows and
  a reader would want, such as the number of profiles used.

## Value

A named list with `script`, `script_sha256`, `hash_algo`,
`package_version`, `r_version`, `built_at` and any extras.

## What the hash is for

Not integrity — reproducibility. A recorded build date cannot tell a
reader whether the script has changed since; a content hash can.
`edaphos` shipped a published conclusion for four months after the
defect that produced it was fixed, because the code changed and the
bundle did not. Comparing the stored hash against the current script is
what makes that state visible, and
`tests/testthat/test-bundle-provenance.R` does exactly that for every
bundle in `inst/extdata`.

## Examples

``` r
p <- edaphos_provenance(script = "data-raw/example.R", n_profiles = 42L)
names(p)
#> [1] "script"          "script_sha256"   "hash_algo"       "package_version"
#> [5] "r_version"       "built_at"        "n_profiles"     
p$package_version
#> [1] "0.9.0"
```
