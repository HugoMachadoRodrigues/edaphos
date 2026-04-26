# Extract embeddings from a pretrained SimCLR encoder

Returns the **backbone** features (before the projection head) — these
are the reusable vectors to feed into downstream DSM models. If you
wanted the contrastive-projection vectors instead, pass
`projection = TRUE`.

## Usage

``` r
foundation_simclr_embed(object, patches, projection = FALSE)
```

## Arguments

- object:

  A `edaphos_foundation_simclr`.

- patches:

  Array `(N, C, H, W)`.

- projection:

  Logical; return L2-normalised projection-head outputs instead of
  backbone features.

## Value

Numeric matrix `N x D` with `D = feature_dim` (or `proj_dim`).
