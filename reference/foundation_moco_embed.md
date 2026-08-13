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

## Examples

``` r
# The installed-package check is not enough on its own: libtorch /
# lantern is a separate binary download, and torch_is_installed() is
# what tells you it is actually there.
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {

# The same 8 x 8 Cerrado patch corpus used by
# foundation_moco_pretrain().
g <- 45L
cube <- vapply(c("elev", "slope", "twi", "map_mm", "ndvi"),
               function(v) {
                 m <- matrix(br_cerrado[[v]], g, g)
                 (m - mean(m)) / stats::sd(m)
               }, matrix(0, g, g))
set.seed(42)
top  <- sample(g - 7L, 24L, replace = TRUE)
left <- sample(g - 7L, 24L, replace = TRUE)
patches <- array(0, dim = c(24L, 5L, 8L, 8L))
for (i in 1:24) {
  patches[i, , , ] <- aperm(cube[top[i]:(top[i] + 7L),
                                 left[i]:(left[i] + 7L), ], c(3, 1, 2))
}
set.seed(1)
fit <- foundation_moco_pretrain(patches, feature_dim = 16L,
                                proj_dim = 8L, batch_size = 8L,
                                epochs = 8L, seed = 1L)

# Default: the reusable backbone representation, feature_dim wide.
emb <- foundation_moco_embed(fit, patches)
print(dim(emb))

# The two outputs live in different spaces and must never be mixed
# in one distance calculation. Backbone features leave a ReLU, so
# they are non-negative and of arbitrary length; the projection head
# L2-normalises, so its rows sit on the unit sphere and may be
# negative. Regress on the backbone, do cosine geometry on the
# projection.
z <- foundation_moco_embed(fit, patches, projection = TRUE)
print(c(backbone_cols = ncol(emb), proj_cols = ncol(z),
        backbone_min = min(emb), proj_min = min(z)))
print(range(round(sqrt(rowSums(z^2)), 6)))

# The encoder is switched to eval() inside, so BatchNorm uses its
# stored running statistics rather than the statistics of whatever
# you happened to pass. That is what makes an embedding a property
# of the patch instead of a property of the batch: encoding three
# patches alone reproduces the corresponding rows of the full run
# (to float32 precision), and a repeated call is bit-identical.
chunk <- foundation_moco_embed(fit, patches[1:3, , , , drop = FALSE])
print(c(chunked  = isTRUE(all.equal(chunk, emb[1:3, , drop = FALSE],
                                    tolerance = 1e-4)),
        repeated = identical(foundation_moco_embed(fit, patches),
                             emb)))

# Only the query encoder is read here. `fit$encoder_k` is the
# momentum copy that built the dictionary during training and is
# never consulted by this function.
}
```
