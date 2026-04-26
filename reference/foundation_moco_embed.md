# Extract backbone embeddings from a fitted MoCo v2 encoder

Returns the `feature_dim` backbone output of the **query** encoder (the
projection head is by design discarded after pre-training, so the
returned embedding is the reusable representation suitable for
downstream DSM tasks). Set `projection = TRUE` to obtain the normalised
projection-head output instead, which is useful when visualising the
contrastive space.

## Usage

``` r
foundation_moco_embed(object, patches, projection = FALSE)
```

## Arguments

- object:

  A `edaphos_foundation_moco`.

- patches:

  Array `(N, C, H, W)`.

- projection:

  Logical; return L2-normalised projection outputs rather than backbone
  features.

## Value

Numeric matrix `(N, D)` where `D = feature_dim` (or `proj_dim` if
`projection = TRUE`).
