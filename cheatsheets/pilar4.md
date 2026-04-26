# Pilar 4 — Foundation Models (SimCLR / MoCo)

Self-supervised contrastive pre-training on unlabelled raster
covariate patches, plus PCA-aware utilities for downstream linear
probes.

## Core API

```r
# Tile a covariate stack into patches for contrastive pre-training
tiles <- foundation_tile_raster(
  stack       = my_terra_rast,
  patch_size  = 16L,
  overlap     = 4L
)

# SimCLR pre-training (small demo; production uses tools/pretrain/)
fit <- foundation_simclr_fit(
  tiles, encoder = "small",
  epochs = 50L, batch_size = 64L,
  seed = 1L
)

# MoCo v1 pre-training
moco <- foundation_moco_fit(
  tiles, queue_size = 1024L,
  momentum = 0.999, epochs = 50L
)

# Embed at point coordinates
emb <- foundation_embed_at_coords(
  moco, coords = my_xy_df,
  stack = my_terra_rast,
  patch_size = 16L
)

# Load pre-trained Cerrado MoCo from Zenodo
moco_v1 <- foundation_weights_load("edaphos-cerrado-moco-v1")

# Linear probe / fine-tune on a small labelled set
probe <- foundation_finetune(
  moco, labelled = my_df, target = "soc",
  freeze_encoder = TRUE
)
```

## v2.0.0 bridge: `qf_krr_fit()` (Pilar 4 × Pilar 6)

PCA-reduce the foundation embedding to N qubits, encode via
ZZFeatureMap, run quantum kernel ridge regression.

## Key references

* Chen et al. (2020) SimCLR.
* He et al. (2020) MoCo.

## See also

* `vignette("pilar4-simclr-embeddings")` — full tutorial.
* `vignette("pilar4-pilar6-quantum")` — quantum-foundation bridge.
