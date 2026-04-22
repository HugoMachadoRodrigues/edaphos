# Step-by-step: publishing `edaphos-cerrado-moco-v1` on Zenodo

This file is a recipe. Follow it top-to-bottom when you are ready to
publish the encoder.

## 1. Create the Zenodo deposit

1. Go to <https://zenodo.org/deposit/new> (log in with your ORCID).
2. Drag the four files from `tools/pretrain/zenodo-upload/` into
   the uploader:
   - `encoder_q.pt`      (481 KB, the trained state dict)
   - `encoder_q.pt.sha256` (65 B, the SHA-256 digest for anyone
     verifying the download)
   - `metadata.json`     (full training config)
   - `loss_history.rds`  (per-step InfoNCE loss)
   - `README.md`         (the human-readable description — Zenodo
     renders it on the deposit landing page)
3. Fill the metadata form using the values printed below.
4. Click **Publish**. Copy the resulting DOI and the direct
   download URL of `encoder_q.pt`.

## 2. Metadata to paste into the Zenodo form

```
Title:
  edaphos-cerrado-moco-v1 — a MoCo v2 foundation-model encoder for
  the Brazilian Cerrado soil covariate stack

Resource type:
  Dataset

Version:
  1.0

License:
  Creative Commons Attribution 4.0 International (CC-BY-4.0)

Creators:
  - Rodrigues, Hugo — ORCID 0000-0002-8070-8126

Description:
  (copy the Description block from ZENODO_DEPOSIT_README.md)

Keywords:
  digital soil mapping, foundation models, self-supervised learning,
  MoCo, Cerrado, pedometry, SoilGrids, WorldClim, SRTM, transfer
  learning

Related identifiers:
  - Derived from (SoilGrids 250m)
    10.1371/journal.pone.0169748
  - Derived from (WorldClim 2.1)
    10.1002/joc.5086
  - Supplement to (edaphos R package, concept DOI)
    10.5281/zenodo.19683708
```

## 3. After publishing — patch the registry

Once the deposit is live, give me three things from the Zenodo
landing page:

- **DOI**          (e.g. `10.5281/zenodo.1234567`)
- **Direct URL** of `encoder_q.pt` (e.g.
  `https://zenodo.org/records/1234567/files/encoder_q.pt?download=1`)
- **Publication timestamp** (ISO 8601; shown at the top of the
  deposit page)

Give me those and I'll patch the single function
`.foundation_weights_registry()` in `R/foundation_weights.R` with
the three new values. Then:

```r
foundation_weights_load("edaphos-cerrado-moco-v1")
```

will start working end-to-end for every `edaphos` user.

The SHA-256 already baked into the registry is

```
44ace7f78c658b6028f1cf5ccfa624023295e5576f681d0135db64726c6738e8
```

so once the URL is set, `foundation_weights_download()` will
verify every download against that digest.

## 4. Quick verification (after the registry patch)

```r
devtools::load_all(".")
loc  <- foundation_weights_download("edaphos-cerrado-moco-v1",
                                      verbose = TRUE)
moco <- foundation_weights_load("edaphos-cerrado-moco-v1")
moco
```

Expected output:

```
<edaphos_foundation_moco>  (MoCo v2 -- Pillar 4)
   n_channels   : 31
   feature_dim  : 64
   proj_dim     : 32
   source       : edaphos-cerrado-moco-v1
```

If the SHA-256 of the downloaded file doesn't match the one in the
registry the loader errors loudly — that's the guarantee of
byte-level reproducibility between the deposit and every user.
