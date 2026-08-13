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

## Examples

``` r
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {
  data(br_cerrado)

  # Twelve 8 x 8 tiles, three standardised covariate channels.
  grids <- lapply(c("elev", "twi", "ndvi"), function(v) {
    m <- matrix(br_cerrado[[v]], nrow = 45, ncol = 45)
    (m - mean(m)) / sd(m)
  })
  patches <- array(0, dim = c(12L, 3L, 8L, 8L))
  k <- 0L
  for (r0 in c(0L, 8L, 16L)) for (c0 in c(0L, 8L, 16L, 24L)) {
    k <- k + 1L
    for (j in seq_along(grids)) {
      patches[k, j, , ] <- grids[[j]][r0 + 1:8, c0 + 1:8]
    }
  }

  # Warm torch up first, else `seed` misses the lazily-loaded
  # backend (see `foundation_simclr_pretrain()`).
  invisible(torch::torch_manual_seed(11L))
  set.seed(1)
  fit <- foundation_simclr_pretrain(patches, epochs = 30L,
                                    batch_size = 6L, seed = 11L)

  # The default is the backbone feature, `feature_dim` wide. The
  # projection head, `proj_dim` wide, exists only to shape the
  # contrastive loss; Chen et al. (2020) throw it away and reuse
  # the feature, which is why `projection = FALSE` is the default.
  feat <- foundation_simclr_embed(fit, patches)
  proj <- foundation_simclr_embed(fit, patches, projection = TRUE)
  print(c(feature = ncol(feat), projection = ncol(proj)))

  # They differ in geometry, not merely in width. Projection rows
  # are unit-norm by construction. Backbone features are pooled
  # ReLU activations: never negative, and with row norms spread
  # over nearly an order of magnitude -- scale them before handing
  # them to a distance-based or penalised downstream model.
  print(round(c(feat_min  = min(feat),
                feat_norm = range(sqrt(rowSums(feat^2))),
                proj_norm = range(sqrt(rowSums(proj^2)))), 4))

  # Embedding applies no augmentation, so it is deterministic.
  print(identical(feat, foundation_simclr_embed(fit, patches)))

  # Adaptive average pooling makes the encoder size-agnostic: a
  # 16 x 16 patch still yields `feature_dim` columns. The channel
  # count and order, though, must match pre-training exactly.
  print(dim(foundation_simclr_embed(
    fit, array(0, dim = c(2L, 3L, 16L, 16L)))))

  # How much has it actually learned? Compare two retrieval probes
  # against a barely-trained encoder.
  set.seed(1)
  raw <- foundation_simclr_pretrain(patches, epochs = 1L,
                                    batch_size = 6L, seed = 11L)
  unit <- function(m) m / sqrt(rowSums(m^2))
  top1 <- function(f, query) {
    s <- tcrossprod(unit(foundation_simclr_embed(f, query)),
                    unit(foundation_simclr_embed(f, patches)))
    mean(apply(s, 1, which.max) == seq_len(nrow(s)))
  }
  set.seed(2)
  noisy <- patches + array(rnorm(length(patches), sd = 0.25),
                           dim(patches))

  # `noise` retrieves each patch from a noisy copy; `flip` from a
  # vertically flipped one, the invariance the augmentation asks
  # the encoder to acquire.
  print(rbind(
    untrained = c(noise = top1(raw, noisy),
                  flip  = top1(raw, patches[, , 8:1, ])),
    trained   = c(noise = top1(fit, noisy),
                  flip  = top1(fit, patches[, , 8:1, ])),
    chance    = c(1 / 12, 1 / 12)))

  # The noise probe is saturated before training starts, so it
  # cannot tell the two encoders apart; only the flip probe moves.
  # Treat even that as an interface check: an encoder pre-trained
  # on twelve tiles for thirty epochs has memorised twelve tiles,
  # not learned a transferable covariate representation.
}
```
