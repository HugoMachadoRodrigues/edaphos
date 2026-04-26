# Download a pretrained Pillar 4 encoder from Zenodo

Fetches a named pretrained encoder from its registered URL (a public
Zenodo deposit), verifies its SHA-256 digest against the registry, and
caches the result under the user's standard cache directory so
subsequent calls are instantaneous.

## Usage

``` r
foundation_weights_download(
  name,
  cache_dir = NULL,
  overwrite = FALSE,
  timeout_sec = 300L,
  verbose = FALSE
)
```

## Arguments

- name:

  Character — a name from
  [`foundation_weights_list()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_list.md).

- cache_dir:

  Optional directory override.

- overwrite:

  Logical — if `TRUE`, re-download even when a cached copy exists.

- timeout_sec:

  Network timeout for the download request. The encoder artefacts are
  typically 1–5 MB, so 300 s is a comfortable ceiling.

- verbose:

  Logical — print progress messages.

## Value

A named list with:

- path:

  Local path to the cached `.pt` state dict.

- metadata:

  Local path to the `metadata.json` sidecar.

- entry:

  The registry row (a one-row data frame).

## Details

The cache directory defaults to
`tools::R_user_dir("edaphos", which = "cache") / weights / <name>`.
Override via `cache_dir` if you need to share the download across users
on a shared HPC filesystem, or to redirect the cache away from a
quota-limited home directory.

## See also

[`foundation_weights_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_load.md),
[`foundation_weights_list()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_list.md).

## Examples

``` r
if (FALSE) { # \dontrun{
  loc <- foundation_weights_download("edaphos-cerrado-moco-v1",
                                       verbose = TRUE)
  moco <- foundation_weights_load(loc$path)
} # }
```
