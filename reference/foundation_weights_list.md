# Catalogue of pretrained Pillar 4 encoders

Returns a data frame describing every pretrained encoder published by
the `edaphos` project: its name, the Zenodo DOI, the raster AoI it was
trained on, the number of input channels it expects, the feature
dimension of its embeddings, and the SHA-256 digest of the hosted
artefact.

## Usage

``` r
foundation_weights_list(include_planned = FALSE)
```

## Arguments

- include_planned:

  Logical. `FALSE` (default) lists only encoders that have been
  published and can be downloaded. `TRUE` also lists planned ones, whose
  `url`, `sha256`, `doi` and `published_at` are `NA` and whose accessors
  refuse with an explicit message.

## Value

A data frame; one row per registered encoder, with a `status` column
(`"published"` or `"planned"`).

## Details

New encoders are added by the `edaphos` maintainers on each minor
release and propagated through the package. Users with bespoke
pretrained encoders can bypass the registry entirely by passing a local
`.pt` path to
[`foundation_weights_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_load.md)
— but a bare state dict carries no shape metadata, so that route
additionally requires `n_channels`, `feature_dim` and `proj_dim`. For
registered encoders those three come from the columns below.

## Examples

``` r
reg <- foundation_weights_list()
print(reg[, c("name", "n_channels", "feature_dim", "proj_dim",
              "norm_stats_status")])
#>                      name n_channels feature_dim proj_dim norm_stats_status
#> 1 edaphos-cerrado-moco-v1         31          64       32     unrecoverable

# Planned encoders are listed only on request; they cannot be fetched.
all_reg <- foundation_weights_list(include_planned = TRUE)
print(all_reg[, c("name", "status")])
#>                      name    status
#> 1 edaphos-cerrado-moco-v1 published
#> 2 edaphos-cerrado-moco-v2   planned

# `norm_stats_status` is not cosmetic. v1's per-channel training
# mean / sd were never written down and are unrecoverable, so an
# exact reproduction of its training-time inputs is not possible:
# standardise over your own area of interest, and say that you did.
```
