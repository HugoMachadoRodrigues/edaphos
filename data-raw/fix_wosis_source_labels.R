## data-raw/fix_wosis_source_labels.R
##
## Corrects the declared SOC source of two shipped bundles. Metadata only:
## no number in either bundle changes.
##
## WHAT WAS WRONG. Both bundles were built from profiles fetched live from the
## `wosis_latest` WFS layer at maps.isric.org (see data-raw/case_cerrado_prepare.R,
## the wfs_url() calls, and data-raw/causal_cerrado_real_rebuild.R). Yet
## case_cerrado_results.rds declared "WoSIS snapshot 2019 (Batjes et al. 2020),
## CC-BY-4.0". Both halves of that are wrong:
##
##   * the 2019 snapshot is a fixed, DOI'd release; `wosis_latest` is the
##     continuously updated layer, documented by Batjes et al. 2024 (the
##     WoSIS snapshot 2023 paper, which describes the current procedures);
##   * the profiles do not share one licence. WoSIS records a licence per
##     profile, and this bundle's own dataset_summary$by_licence -- carried
##     through from that metadata -- holds four.
##
## causal_cerrado_real_v2.rds named the layer correctly but also declared a
## single "CC-BY-4.0". Its pull did not record per-profile licences (the
## pre-strip $profiles at commit d8c1998 has no licence column), so the
## correction says exactly that instead of inventing a breakdown.
##
## Run once from the package root. Like strip_third_party_records.R, it
## rewrites bundles in place and re-points their provenance to itself,
## keeping the previous producer in $provenance$chain so the history is
## not lost.

if (!file.exists("DESCRIPTION")) stop("run from the package root")

EXT <- file.path("inst", "extdata")
SCRIPT <- file.path("data-raw", "fix_wosis_source_labels.R")
h <- edaphos:::.script_hash(SCRIPT)

relabel <- function(name, soc) {
  f <- file.path(EXT, paste0(name, ".rds"))
  b <- readRDS(f)
  old <- b$sources$soc
  b$sources$soc <- soc
  p <- b$provenance
  p$chain <- unique(c(p$chain %||% p$built_from %||% character(0), p$script))
  p$chain <- p$chain[!is.na(p$chain) & nzchar(p$chain)]
  p$built_from <- p$script
  p$built_from_sha256 <- p$script_sha256
  p$script <- SCRIPT
  p$script_sha256 <- unname(h[["hash"]])
  p$hash_algo <- unname(h[["algo"]])
  p$package_version <- as.character(utils::packageVersion("edaphos"))
  p$r_version <- paste(R.version$major, R.version$minor, sep = ".")
  p$built_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  b$provenance <- p
  saveRDS(b, f, version = 3, compress = "xz")
  message(sprintf("%s\n  was: %s\n  now: %s", name, old, soc))
}

# The licence breakdown is read from the bundle, not typed here.
cc <- readRDS(file.path(EXT, "case_cerrado_results.rds"))
lic <- cc$dataset_summary$by_licence
# The stored strings are cut at 60 characters, so some end in ", " with the
# URL lost; strip a trailing URL *or* a dangling separator.
short <- sub(",? *(https?://.*)?$", "", lic$licence)
short <- sub("^Attribution 4\\.0 International \\((.*)\\)$", "\\1", short)
short <- sub("^Attribution-NonCommercial 4\\.0 International \\((.*)\\)$", "\\1", short)
short <- sub("^CC0 1\\.0 Universal \\(CC0 1\\.0\\).*$", "CC0 1.0", short)
short <- sub("^U\\.S\\. Public Domain.*$", "U.S. Public Domain", short)
breakdown <- paste(sprintf("%s (%d)", short, lic$Freq), collapse = ", ")

relabel("case_cerrado_results", paste0(
  "WoSIS latest, ISRIC WFS (maps.isric.org), fetched live; procedures per ",
  "Batjes et al. 2024. Per-profile licences recorded by WoSIS: ", breakdown))

relabel("causal_cerrado_real_v2", paste0(
  "WoSIS latest, ISRIC WFS (maps.isric.org), fetched live; procedures per ",
  "Batjes et al. 2024. Licences are per profile in WoSIS and were not ",
  "recorded by this pull."))
