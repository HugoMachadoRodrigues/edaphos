# Catalogue of pretrained Pillar 4 encoders

Returns a data frame describing every pretrained encoder published by
the `edaphos` project: its name, the Zenodo DOI, the raster AoI it was
trained on, the number of input channels it expects, the feature
dimension of its embeddings, and the SHA-256 digest of the hosted
artefact.

## Usage

``` r
foundation_weights_list()
```

## Value

A data frame; one row per registered encoder.

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
#> 2 edaphos-cerrado-moco-v2         31          64       32           pending

# Only rows with a non-NA `url` can actually be fetched; the rest
# are placeholders for a future release and error on download.
print(reg$name[!is.na(reg$url)])
#> [1] "edaphos-cerrado-moco-v1"

# `norm_stats_status` is not cosmetic. v1's per-channel training
# mean / sd were never written down and are unrecoverable, so an
# exact reproduction of its training-time inputs is not possible:
# standardise over your own area of interest, and say that you did.
```
