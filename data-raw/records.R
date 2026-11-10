# ---------------------------------------------------------------------------
# data-raw/records.R
#
# Where record-level inputs live now that the package no longer ships them.
#
# Since the 2026-08-28 strip (commit 8f23ddf) inst/extdata holds aggregate
# tables only. The per-profile and per-horizon records that produced them --
# WoSIS profiles, the SoilData calibration set, held-out truths -- are
# third-party measurements under per-record licences, so they are neither
# shipped nor committed. Scripts that need them read them from a local cache:
#
#     data-raw/build/records/<bundle>.rds        (gitignored)
#
# The cache holds each bundle as it was BEFORE the strip, so a script that
# reads `read_records("piml_coverage")$coverage` gets the exact table the
# published aggregates were computed from. Two ways to fill it:
#
#   Rscript data-raw/restore_records.R   # the published snapshot, from git
#                                        # history, offline, sha256-checked
#   Rscript data-raw/piml_wosis_multihorizon.R  (and the other fetchers)
#                                        # a fresh pull from the public
#                                        # sources; numbers will move as
#                                        # WoSIS "latest" moves
#
# Source this file; it defines records_path() and read_records().
# ---------------------------------------------------------------------------

records_dir <- function() {
  root <- if (file.exists("DESCRIPTION")) "." else
    if (file.exists("../DESCRIPTION")) ".." else
      stop("run from the package root or from paper/")
  file.path(root, "data-raw", "build", "records")
}

records_path <- function(name) {
  name <- sub("[.]rds$", "", name)
  file.path(records_dir(), paste0(name, ".rds"))
}

read_records <- function(name) {
  p <- records_path(name)
  if (!file.exists(p))
    stop(sprintf(paste0(
      "record-level input '%s' is not in the local cache (%s).\n",
      "  Rebuild the cache with:  Rscript data-raw/restore_records.R\n",
      "  These records are third-party measurements and are not shipped ",
      "with the package; see PROVENANCE.md."), basename(p), records_dir()),
      call. = FALSE)
  readRDS(p)
}
