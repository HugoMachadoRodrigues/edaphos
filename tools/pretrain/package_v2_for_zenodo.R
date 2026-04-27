## tools/pretrain/package_v2_for_zenodo.R
##
## Packages the trained edaphos-cerrado-moco-v2 weights into a
## single ZIP ready to upload via Zenodo's "New Version" UI.
##
## Run this AFTER `data-raw/pretrain_cerrado_train_v2.R` reaches
## 200000 steps.  Pre-flight: state.rds$next_epoch >= 200001.
##
## Output:
##   tools/pretrain/zenodo-upload/
##   tools/pretrain/zenodo-upload.zip
##
## Usage:
##   Rscript tools/pretrain/package_v2_for_zenodo.R

suppressPackageStartupMessages({
  if (!requireNamespace("digest",   quietly = TRUE)) install.packages("digest")
  if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")
})

V2_DIR <- "tools/pretrain/edaphos-cerrado-moco-v2"
OUT    <- "tools/pretrain/zenodo-upload"
ZIP    <- "tools/pretrain/zenodo-upload.zip"

stopifnot(file.exists(file.path(V2_DIR, "encoder_q.pt")))
stopifnot(file.exists(file.path(V2_DIR, "metadata.json")))
stopifnot(file.exists(file.path(V2_DIR, "loss_history.rds")))

# Pre-flight: confirm we hit 200k steps
ck <- readRDS(file.path(V2_DIR, "checkpoints", "state.rds"))
if (ck$next_epoch <= 200000L) {
  stop(sprintf(
    "Encoder still at step %d / 200000.  Resume training first via\n",
    ck$next_epoch - 1L,
    "  Rscript data-raw/pretrain_cerrado_train_v2.R"
  ))
}
message(sprintf("[zenodo-pkg] v2 confirmed at step %d (loss %.4f).",
                 ck$next_epoch - 1L, tail(ck$loss_history, 1L)))

# Stage the upload bundle
if (dir.exists(OUT)) unlink(OUT, recursive = TRUE)
dir.create(OUT, recursive = TRUE)

# Copy artefacts the user must upload to Zenodo
files <- c("encoder_q.pt", "metadata.json", "loss_history.rds",
            "encoder_q.pt.sha256")
for (f in files) {
  src <- file.path(V2_DIR, f)
  if (file.exists(src)) {
    file.copy(src, file.path(OUT, f), overwrite = TRUE)
    message(sprintf("  added: %s (%.1f KB)", f, file.size(src) / 1024))
  } else {
    warning(sprintf("MISSING %s -- run pretrain_cerrado_train_v2.R again.", f))
  }
}

# README that ships inside the Zenodo deposit
readme <- c(
  "# edaphos-cerrado-moco-v2",
  "",
  sprintf("Final InfoNCE loss: %.4f at step %d.",
           tail(ck$loss_history, 1L), ck$next_epoch - 1L),
  "",
  "## Files",
  "",
  "* `encoder_q.pt`       -- query-encoder state dict (torch_save).",
  "* `encoder_q.pt.sha256`-- SHA-256 digest for verification.",
  "* `metadata.json`      -- training config + AoI + per-channel stats.",
  "* `loss_history.rds`   -- 200,000-element InfoNCE loss vector.",
  "",
  "## How to load",
  "",
  "```r",
  "library(edaphos)",
  "moco <- foundation_weights_load(\"edaphos-cerrado-moco-v2\")",
  "```",
  "",
  "Once this deposit is published, the maintainer of `edaphos` will",
  "register the resulting DOI in `R/foundation_weights.R` so the load",
  "above pulls the right URL.",
  "",
  "## Citation",
  "",
  "Rodrigues, H. (2026). *edaphos-cerrado-moco-v2: a 200k-step MoCo v2",
  "encoder for the Brazilian Cerrado soil covariate stack.*  Zenodo.",
  "doi:10.5281/zenodo.<TBD>"
)
writeLines(readme, file.path(OUT, "README.md"))

# Build the ZIP
if (file.exists(ZIP)) unlink(ZIP)
old_wd <- setwd(dirname(OUT))
on.exit(setwd(old_wd), add = TRUE)
zip::zip(zipfile = basename(ZIP), files = "zenodo-upload")
setwd(old_wd)

sz_mb <- file.size(ZIP) / 1024 / 1024
message(sprintf("\n=== DONE ===\n  Bundle : %s (%.1f MB)\n  Files  : %s",
                 ZIP, sz_mb,
                 paste(list.files(OUT), collapse = ", ")))
message("\nNext step: upload the .zip on Zenodo via 'New Version'")
message("           on https://zenodo.org/records/19701276")
message("           (the v1 concept-DOI parent).")
