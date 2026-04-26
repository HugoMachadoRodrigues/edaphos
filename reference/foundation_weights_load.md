# Load a pretrained encoder into an `edaphos_foundation_moco` wrapper

Restores a pretrained MoCo v2 encoder from a `.pt` state-dict file (or
by name from the published registry) into an in-memory
`edaphos_foundation_moco` object that is **shape-compatible** with the
output of
[`foundation_moco_pretrain_tiles()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain_tiles.md).
The restored object is ready to feed into
[`foundation_moco_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed.md),
[`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md)
or
[`foundation_fit_regressor()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_regressor.md)
without any additional plumbing.

## Usage

``` r
foundation_weights_load(
  source,
  n_channels = NULL,
  feature_dim = NULL,
  proj_dim = NULL,
  cache_dir = NULL,
  overwrite = FALSE,
  verbose = FALSE
)
```

## Arguments

- source:

  Either a character name registered in
  [`foundation_weights_list()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_list.md)
  — in which case the encoder is downloaded (cached) via
  [`foundation_weights_download()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_download.md)
  — or a path to a local `.pt` file. For the local path case, pass the
  matching metadata as `n_channels` / `feature_dim` / etc.

- n_channels, feature_dim, proj_dim:

  Optional integers; when `source` is a local path these must describe
  the shape the `.pt` file was saved from. When `source` is a registry
  name they are pulled from the registry.

- cache_dir, overwrite, verbose:

  Forwarded to
  [`foundation_weights_download()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_download.md)
  when `source` is a registry name.

## Value

An `edaphos_foundation_moco` object with a populated `$encoder_q` (the
query encoder; the momentum encoder is not restored because it is only
needed during training).

## Examples

``` r
if (FALSE) { # \dontrun{
  moco <- foundation_weights_load("edaphos-cerrado-moco-v1")
  emb  <- foundation_moco_embed(moco, patches)
} # }
```
