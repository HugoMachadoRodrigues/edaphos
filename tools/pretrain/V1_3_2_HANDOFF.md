# v1.3.2 hand-off: complete the MoCo v2 encoder + publish to Zenodo

This is your step-by-step.  The package is already prepared:

* The training script `data-raw/pretrain_cerrado_train_v2.R` is
  **resume-aware** as of v3.11.0 -- a re-run picks up at step
  110 001 from the existing checkpoint.
* The Zenodo packaging helper is at
  `tools/pretrain/package_v2_for_zenodo.R`.
* The catalog `R/foundation_weights.R` already has a v2 row with
  the URL / DOI / SHA256 / published_at fields parked at
  `NA_character_`.  A single helper
  (`tools/pretrain/wire_up_v2_doi.R`) patches them for you.

You will execute four steps total.  Steps 1, 2, 4 are scripts you
run.  Step 3 is the Zenodo web UI.

---

## Step 1.  Resume training: 110k -> 200k steps  (~2 hours on MPS)

```bash
cd /path/to/GeoVersa
Rscript data-raw/pretrain_cerrado_train_v2.R
```

What happens:

* The script reads
  `tools/pretrain/edaphos-cerrado-moco-v2/checkpoints/state.rds`
  and prints
  `[train-v2] resuming from epoch 110000 (loss 0.815)`.
* It runs another 90 000 InfoNCE steps on the MPS device
  (~2 hours on an M1 Max; ~1.3 hours on an M3 Pro).
* Checkpoints land every 10 000 epochs in the same directory
  (so a Ctrl-C is safe -- the next `Rscript` call resumes from
  the latest checkpoint, never wasting more than 10 000 steps).
* On completion you'll see
  `[train-v2] done in NN.N min  (final InfoNCE = 0.NNNN)`
  and the artefacts will be written to
  `tools/pretrain/edaphos-cerrado-moco-v2/`:

    encoder_q.pt           # ~470 KB, the trained query encoder
    encoder_q.pt.sha256    # the 64-char hex digest
    metadata.json          # training config + AoI + per-channel stats
    loss_history.rds       # 200000-element InfoNCE vector

If your Mac sleeps mid-training, just re-run the same command --
resume picks up cleanly.

---

## Step 2.  Build the Zenodo upload ZIP  (~5 seconds)

```bash
Rscript tools/pretrain/package_v2_for_zenodo.R
```

What happens:

* Verifies the v2 dir actually contains a 200k-step checkpoint
  (errors out otherwise).
* Stages `encoder_q.pt`, `encoder_q.pt.sha256`, `metadata.json`,
  `loss_history.rds`, and a `README.md` into
  `tools/pretrain/zenodo-upload/`.
* Bundles them into `tools/pretrain/zenodo-upload.zip`.

Print at the end:

    === DONE ===
      Bundle : tools/pretrain/zenodo-upload.zip (~0.5 MB)
      Files  : encoder_q.pt, encoder_q.pt.sha256, metadata.json,
               loss_history.rds, README.md

---

## Step 3.  Upload to Zenodo  (~10 minutes, in your browser)

This is the only step I cannot do for you (CRAN-class
publication action tied to your ORCID).

1. Go to <https://zenodo.org/records/19701276> -- this is the
   v1 concept-DOI parent.
2. Click **New version**.  Zenodo creates a draft inheriting the
   v1 metadata.
3. **Files**: delete the v1 `encoder_q.pt` from the draft and
   upload `tools/pretrain/zenodo-upload.zip` (or unzip first and
   upload the four files individually -- Zenodo accepts both).
4. **Metadata** patches:
    * Title: append `(v2 -- 200k InfoNCE steps)`
    * Description: paste the contents of
      `tools/pretrain/edaphos-cerrado-moco-v2/metadata.json` ->
      `description` field.
    * Version: `2.0.0`
    * Related identifiers: keep the v1 link as
      `isNewVersionOf 10.5281/zenodo.19701276`.
5. Click **Save** -> **Publish**.  Zenodo mints a fresh DOI like
   `10.5281/zenodo.20000001`.

Capture three values from the published deposit:

* **DOI**         e.g. `10.5281/zenodo.20000001`
* **URL**         e.g. `https://zenodo.org/records/20000001/files/encoder_q.pt`
* **published_at** e.g. `2026-05-01T18:30:00Z`  (use `Z` for UTC)

The SHA-256 is already on disk in
`tools/pretrain/edaphos-cerrado-moco-v2/encoder_q.pt.sha256`.

---

## Step 4.  Wire the DOI into the package catalog  (~30 seconds)

```bash
SHA256=$(cat tools/pretrain/edaphos-cerrado-moco-v2/encoder_q.pt.sha256)

Rscript tools/pretrain/wire_up_v2_doi.R \
  10.5281/zenodo.20000001 \
  https://zenodo.org/records/20000001/files/encoder_q.pt \
  $SHA256 \
  2026-05-01T18:30:00Z
```

Replace the three string values with the ones from Step 3.

What happens:

* The four `NA_character_` placeholders in
  `R/foundation_weights.R` (URL / SHA256 / DOI / published_at)
  are replaced by your real values.
* Diff is tiny (4 single-line substitutions); review with
  `git diff R/foundation_weights.R` before committing.
* The script prints the suggested follow-up commands:

    Rscript -e 'devtools::document(); devtools::test()'
    git add R/foundation_weights.R
    git commit -m "feat(v3.11.0): wire up edaphos-cerrado-moco-v2 DOI"
    git push origin main

---

## (Optional) Step 5.  Re-run the IV benchmark with v2 instruments

Once the catalog is wired, you can swap the v1 encoder for the v2
in `data-raw/causal_iv_benchmark_real.R`:

```r
ENCODER_TAG <- "edaphos-cerrado-moco-v2"   # was "...moco-v1"
```

Then:

```bash
EDAPHOS_IV_REAL_STACK=1 Rscript data-raw/causal_iv_benchmark_real.R
```

The clay -> SOC stage-1 F (currently 2.7 with v1) is the metric
to watch -- the v1.3.2 hypothesis is that a fairly-trained
encoder lifts F above the 10 weak-instrument threshold.  Whatever
the result, it is the FAIR test the v1.3.0 NEWS asked for.

---

## Total wall-clock budget

  Step 1 (your MPS):     ~2 h
  Step 2 (R script):     ~5 s
  Step 3 (Zenodo UI):    ~10 min
  Step 4 (R script):     ~30 s
  Step 5 (optional):     ~3 min
  --
  ~2 h 15 min + the time you choose to spend in the Zenodo UI

After Step 4, the v1.3.2 roadmap line is closed and the README
badge / catalog automatically picks up the v2 weights for any
user who calls `foundation_weights_load("edaphos-cerrado-moco-v2")`.
