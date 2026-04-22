# `tools/pretrain/` — reproducible Pillar 4 encoder training

This directory holds every artefact needed to rebuild a published
pretrained Pillar 4 encoder for `edaphos` from scratch. The design
goal is strict reproducibility: fixed AoI, fixed variable list,
fixed seeds, fixed resolution, fixed hardware target. Two scripts
turn that specification into (i) a training dataset and (ii) a
trained encoder.

## Files

```
tools/pretrain/
├── README.md                     # this file
├── ZENODO_DEPOSIT_README.md      # metadata + description for Zenodo
├── prepare.log                   # stdout/stderr of the prep run
├── geodata_cache/                # geodata::soil_world() etc. downloads
│   ├── soil_world/ ...           # raw SoilGrids GeoTIFFs
│   ├── climate/ ...              # WorldClim monthly GeoTIFFs
│   └── elevation/ ...            # SRTM 30-arc-second
├── cerrado_stack.tif             # aligned analysis grid (0.01 deg)
├── cerrado_dataset.rds           # edaphos_tile_dataset (50k patches)
├── cerrado_dataset_meta.rds      # AoI + variable + normalisation meta
└── edaphos-cerrado-moco-v1/
    ├── encoder_q.pt              # final state dict
    ├── encoder_q.pt.sha256       # SHA-256 for weights registry
    ├── metadata.json             # full training configuration
    ├── loss_history.rds          # per-step InfoNCE loss
    └── checkpoints/              # per-1000-step intermediate state
```

## Reproduction

From the package root:

```bash
# 1) Download tiles + build the 50k-patch dataset (~15-60 min, one-off).
Rscript data-raw/pretrain_cerrado_prepare.R

# 2) Train MoCo v2 on MPS / CUDA / CPU (~1-2 h on M1 Max MPS).
Rscript data-raw/pretrain_cerrado_train.R
```

Two environment knobs influence the training run:

- `torch::backends_mps_is_available()` decides whether the script
  picks Apple Silicon MPS or falls through to CPU.
- The seed is hard-coded (`seed = 2026L`) so re-running on the same
  hardware produces a byte-identical encoder. Changing the hardware
  (CPU vs MPS) can produce negligible numerical drift.

## Publishing to Zenodo

Once `edaphos-cerrado-moco-v1/encoder_q.pt` exists:

1. Create a new Zenodo deposit (<https://zenodo.org/deposit/new>).
2. Upload `encoder_q.pt`, `metadata.json` and `loss_history.rds`.
3. Copy the title, description and creator fields from
   `ZENODO_DEPOSIT_README.md`.
4. Licence: **CC-BY-4.0**.
5. Publish; record the DOI and the direct-download URL of
   `encoder_q.pt`.
6. Update the `url`, `sha256` and `doi` columns in
   `.foundation_weights_registry()` inside
   `R/foundation_weights.R`.
7. Release the next minor version of `edaphos` with the updated
   registry.

From that moment on, any user can
`foundation_weights_load("edaphos-cerrado-moco-v1")` and the
download / SHA-256 check / cache are handled transparently.

## Licence

- Encoder artefacts (`encoder_q.pt`, `metadata.json`,
  `loss_history.rds`): **CC-BY-4.0**. Free to reuse, redistribute
  and modify, with attribution.
- Scripts (`data-raw/pretrain_cerrado_*.R`): same licence as the
  `edaphos` R package (MIT + file LICENSE).
- Raw raster tiles under `geodata_cache/` come from their upstream
  providers (SoilGrids / WorldClim / SRTM), with upstream licences
  unchanged.
