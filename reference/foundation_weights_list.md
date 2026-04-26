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
`.pt` path directly to
[`foundation_weights_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_load.md).

## Examples

``` r
foundation_weights_list()
#>                      name
#> 1 edaphos-cerrado-moco-v1
#>                                                                                                                                                                                                                                                                                            description
#> 1 MoCo v2 encoder pretrained on 50k 16x16 Cerrado tiles (SoilGrids 250m soc/clay/sand/phh2o/bdod + WorldClim 2.1 monthly prec/tavg + SRTM elev/slope), aligned to a 0.01-deg grid. 31 channels in, 64-dim feature embedding out. 20000 InfoNCE steps on an Apple M1 Max MPS; final InfoNCE loss ~1.64.
#>   n_channels feature_dim proj_dim patch_size
#> 1         31          64       32         16
#>                                             aoi
#> 1 Cerrado core (lon -53 to -43, lat -23 to -10)
#>                                                      url
#> 1 https://zenodo.org/records/19701276/files/encoder_q.pt
#>                                                             sha256
#> 1 44ace7f78c658b6028f1cf5ccfa624023295e5576f681d0135db64726c6738e8
#>                       doi   license         published_at edaphos_version
#> 1 10.5281/zenodo.19701276 CC-BY-4.0 2026-04-22T21:59:12Z           1.2.0
```
