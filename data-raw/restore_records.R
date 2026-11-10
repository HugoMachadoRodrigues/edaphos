#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/restore_records.R
#
# Rebuild the local record cache (data-raw/build/records/, gitignored) from
# the last commits before the two removals -- 2026-08-28 (8f23ddf, the strip)
# and the one before it (d8c1998, which deleted two bundles outright and moved
# them to data-raw/build) -- so that the scripts that need
# record-level inputs run offline against the exact snapshot the published
# aggregates were computed from.
#
# Restores every bundle that the strip deleted or reduced, under its current
# name (three were later renamed "pilar" -> "pillar"). Each file is checked
# against the git blob it came from, and the manifest of what was restored is
# written next to it. Nothing here is written to inst/extdata.
#
# Needs a git checkout with history; no network.
# ---------------------------------------------------------------------------

source("data-raw/records.R")

parent_of <- function(commit)
  system2("git", c("rev-parse", paste0(commit, "^")), stdout = TRUE)
pre <- parent_of("8f23ddf")
# deleted by d8c1998 rather than by the strip, so read from ITS parent
EARLIER <- c(piml_parameter_variograms = "piml_parameter_variograms",
             benchmark_wosis_p4_p5_p7  = "benchmark_wosis_p4_p5_p7")
pre_earlier <- parent_of("d8c1998")

# bundle names in the pre-strip tree, and what they are called today
RESTORE <- c(
  benchmark_wosis_6pilar        = "benchmark_wosis_6pillar",
  capstone_campaign_results     = "capstone_campaign_results",
  capstone_native_calibration   = "capstone_native_calibration",
  case_cerrado_results          = "case_cerrado_results",
  causal_cerrado_real           = "causal_cerrado_real",
  causal_cerrado_real_v2        = "causal_cerrado_real_v2",
  interval_width_vs_extrapolation = "interval_width_vs_extrapolation",
  pilar10_gat_tuning            = "pillar10_gat_tuning",
  pilar8_real_pedons            = "pillar8_real_pedons",
  piml_coverage                 = "piml_coverage",
  piml_depth_benchmark          = "piml_depth_benchmark",
  piml_external_anchors         = "piml_external_anchors",
  piml_prior_sensitivity        = "piml_prior_sensitivity",
  piml_ptf_bulk_density         = "piml_ptf_bulk_density",
  piml_stock_at_scale           = "piml_stock_at_scale",
  piml_stock_validation         = "piml_stock_validation",
  piml_wosis_cerrado            = "piml_wosis_cerrado",
  soildata_uberaba_bd           = "soildata_uberaba_bd",
  temporal_cerrado_results      = "temporal_cerrado_results"
)

dir.create(records_dir(), recursive = TRUE, showWarnings = FALSE)

from <- c(stats::setNames(rep(pre, length(RESTORE)), names(RESTORE)),
          stats::setNames(rep(pre_earlier, length(EARLIER)), names(EARLIER)))
RESTORE <- c(RESTORE, EARLIER)

rows <- lapply(names(RESTORE), function(old) {
  pre  <- from[[old]]
  src  <- paste0("inst/extdata/", old, ".rds")
  blob <- system2("git", c("rev-parse", paste0(pre, ":", src)), stdout = TRUE)
  dst  <- records_path(RESTORE[[old]])
  ok <- system2("git", c("show", paste0(pre, ":", src)), stdout = dst)
  if (!identical(ok, 0L)) stop("git show failed for ", src)
  # the file must hash back to the blob it was read from
  got <- system2("git", c("hash-object", dst), stdout = TRUE)
  if (!identical(got, blob)) stop("blob mismatch for ", src)
  data.frame(bundle = RESTORE[[old]], from = src, git_blob = blob,
             sha256 = digest::digest(dst, algo = "sha256", file = TRUE),
             bytes = file.size(dst), restored_from_commit = pre,
             stringsAsFactors = FALSE)
})
man <- do.call(rbind, rows)
utils::write.csv(man, file.path(records_dir(), "MANIFEST.csv"), row.names = FALSE)

cat(sprintf("restored %d bundles into %s\n", nrow(man), records_dir()))
print(man[, c("bundle", "bytes")], row.names = FALSE)
