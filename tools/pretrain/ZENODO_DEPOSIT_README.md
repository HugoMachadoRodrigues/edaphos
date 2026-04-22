# `edaphos-cerrado-moco-v1` — Zenodo deposit

This directory contains the build tree for the first public
pretrained Pillar 4 encoder of the [`edaphos`](https://github.com/HugoMachadoRodrigues/edaphos)
R package. The `.pt` file plus sidecar metadata in this folder is
intended to be uploaded to a fresh Zenodo deposit by the repository
owner; the `edaphos` package's weights-registry is then updated to
point at the resulting DOI.

## Artefact layout

```
edaphos-cerrado-moco-v1/
├── encoder_q.pt           # torch state dict, gzip-compressed
├── encoder_q.pt.sha256    # SHA-256 digest for verification
├── metadata.json          # channels, feature_dim, AoI, training config
├── loss_history.rds       # per-step InfoNCE loss vector
└── checkpoints/           # optional per-1000-step intermediates
```

## Scientific metadata (for the Zenodo form)

### Title

```
edaphos-cerrado-moco-v1 — a MoCo v2 foundation-model encoder for the
Brazilian Cerrado soil covariate stack
```

### Description

> A self-supervised MoCo v2 (He et al. 2020; Chen et al. 2020) encoder
> pretrained on 50 000 16×16 raster patches sampled from a core
> Cerrado AoI (longitude −53 to −43, latitude −23 to −10), covering
> the Brazilian states of Goiás, Tocantins, Mato Grosso, Bahia and
> Minas Gerais. The input stack is aligned to a 0.01-degree (~1 km)
> grid and combines three public keyless sources:
>
> - **SoilGrids 250m, 0–5 cm mean**: SOC, clay, sand, pH(H₂O),
>   bulk density (5 layers);
> - **WorldClim 2.1 (Brazil country pack)**: 12 monthly
>   precipitation + 12 monthly mean temperature (24 layers);
> - **SRTM 30 arc-second**: elevation + slope (2 layers).
>
> The encoder is a 5-block convolutional backbone producing a
> 64-dimensional feature vector followed by a 2-layer MLP projection
> head (`feature_dim = 64`, `proj_dim = 32`). Training uses a queue
> of 4096 negatives, InfoNCE temperature 0.07, momentum 0.999, Adam
> learning rate 3e-4, batch size 64, for 20 000 optimisation steps
> on an Apple Silicon M1 Max via `torch::backend_mps`. The raster-
> specific augmentation policy matches the one shipped in the
> `foundation_moco_pretrain_tiles()` default, with a band-level
> channel-drop layer that simulates missing / corrupt covariate
> bands.
>
> The artefact is a PyTorch state dict compatible with the `edaphos`
> R package (version 1.2.0 and later). The package's
> `foundation_weights_load("edaphos-cerrado-moco-v1")` downloads the
> file from this deposit, verifies its SHA-256 digest, caches it
> under `tools::R_user_dir("edaphos")` and rebuilds the in-memory
> encoder in a single call. Downstream tasks — soil-order
> classification, SOC regression — are trained on top of the encoder
> with `foundation_fit_classifier()` / `foundation_fit_regressor()`.

### Creators

- Rodrigues, Hugo (author, ORCID 0000-0002-8070-8126)

### Keywords

`digital soil mapping`, `foundation models`, `self-supervised
learning`, `MoCo`, `Cerrado`, `pedometry`, `SoilGrids`, `WorldClim`,
`SRTM`, `transfer learning`

### License

Creative Commons Attribution 4.0 International (CC-BY-4.0).
Both the encoder artefact and its metadata are licensed to allow
reuse, redistribution and commercial use, provided that attribution
to this deposit and to the `edaphos` package is preserved.

### Related identifiers

- **is derived from** Hengl, T. et al. (2017). SoilGrids250m: Global
  gridded soil information based on machine learning. *PLoS ONE*
  12(2), e0169748. DOI: 10.1371/journal.pone.0169748
- **is derived from** Fick, S. E. and Hijmans, R. J. (2017).
  WorldClim 2: new 1-km spatial resolution climate surfaces for
  global land areas. *International Journal of Climatology* 37(12),
  4302–4315. DOI: 10.1002/joc.5086
- **is derived from** U.S. Geological Survey (2000). *Shuttle Radar
  Topography Mission Global 30-arcsecond Digital Elevation Model*.
- **is supplement to** Rodrigues, H. (2026). `edaphos`: Disruptive
  algorithms for digital soil mapping. R package, version 1.2.0.
  DOI: (concept DOI of the `edaphos` package on Zenodo)

## Reproducibility

The full build is reproducible on any machine that runs R ≥ 4.3,
`torch` ≥ 0.16 and `geodata` ≥ 0.6. Two scripts in the `edaphos`
repository rebuild the deposit:

1. `data-raw/pretrain_cerrado_prepare.R` — downloads the SoilGrids,
   WorldClim and SRTM tiles; crops them to the AoI; aligns them to a
   0.01-deg grid; samples 50 000 patches; writes
   `tools/pretrain/cerrado_dataset.rds`.

2. `data-raw/pretrain_cerrado_train.R` — loads the dataset, builds
   the MoCo v2 encoders, runs 20 000 steps on MPS (or CPU /
   CUDA), writes `tools/pretrain/edaphos-cerrado-moco-v1/` with the
   artefact layout above.

Seeds are fixed (`seed = 2026L`) so two runs on the same hardware
produce byte-identical encoders; the SHA-256 of `encoder_q.pt` is
recorded in the weights registry shipped with the package.

## Relation to the `edaphos` weights registry

Once the Zenodo deposit is published, the registry row in
`R/foundation_weights.R` is updated with:

- `url`        — the direct-download URL of `encoder_q.pt` on Zenodo
- `sha256`     — the SHA-256 digest printed by the training script
- `doi`        — the deposit DOI assigned by Zenodo
- `n_channels` — the final channel count after stacking
- `published_at` — ISO-8601 timestamp of the deposit's publication

A minor version of `edaphos` is released with the updated registry
so that users doing `install.packages("edaphos")` and then
`foundation_weights_load("edaphos-cerrado-moco-v1")` get a working
download by default.
