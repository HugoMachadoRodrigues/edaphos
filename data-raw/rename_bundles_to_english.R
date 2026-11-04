## data-raw/rename_bundles_to_english.R
##
## Gives three shipped bundles English file names and translates the
## Portuguese labels inside two others. Names and labels only: no number in
## any bundle changes, and the script checks that before it writes.
##
## One label was wrong as well as Portuguese. The capstone's MAP effect was
## tagged "g/kg per 100 mm", but data-raw/capstone_campaign_run.R fits it on
## wc_bio_12 in raw millimetres, so the estimate is per mm. The tag says so now.
##
## WHY. The package's identifiers used "pilar", the Portuguese word, and two
## capstone bundles carried Portuguese axis labels ("Cobertura arbórea (%)",
## "Argila (%)", "COS (g/kg)") and a column named `pilar`. From 2.0.0 the
## repository is English throughout.
##
## WHY A SCRIPT RATHER THAN `git mv`. Two of the renamed bundles and both
## relabelled ones record data-raw/strip_third_party_records.R as their
## producer, with a hash of its content. That script names the old files, but
## editing it would break the hash of every bundle it wrote, and it cannot be
## re-run: the third-party records it removed are no longer in the bundles.
## So it stays as written, and this script takes over as the recorded
## producer of the bundles it touches, keeping the previous one in
## $provenance$chain and the old file name in $provenance$renamed_from --
## the same pattern as data-raw/fix_wosis_source_labels.R.
##
## A bundle with no provenance block (pilar10_gat_tuning.rds) is moved byte
## for byte, since there is no record to update.
##
## Run once from the package root, with edaphos installed:
##   Rscript data-raw/rename_bundles_to_english.R

if (!file.exists("DESCRIPTION")) stop("run from the package root")

EXT <- file.path("inst", "extdata")
SCRIPT <- file.path("data-raw", "rename_bundles_to_english.R")
h <- edaphos:::.script_hash(SCRIPT)

LABELS <- c("Cobertura arbórea (%)" = "Tree cover (%)",
            "Argila (%)"            = "Clay (%)",
            "COS (g/kg)"            = "SOC (g/kg)",
            "g/kg por %"            = "g/kg per %",
            "g/kg per 100 mm"       = "g/kg per mm",
            "pilar"                 = "pillar")

# Replace exact strings in every character vector, factor level and name of
# a nested object. Exact matches only, so free text is never rewritten.
relabel_all <- function(x, map) {
  swap <- function(v) { i <- v %in% names(map); v[i] <- map[v[i]]; v }
  if (is.character(x)) x[] <- swap(x)
  else if (is.factor(x)) levels(x) <- swap(levels(x))
  else if (is.list(x) && !inherits(x, "numeric_version"))
    for (i in seq_along(x)) if (!is.null(x[[i]])) x[[i]] <- relabel_all(x[[i]], map)
  if (!is.null(names(x))) names(x) <- swap(names(x))
  x
}

strip_labels <- function(x) {
  if (is.character(x)) return(length(x))
  if (is.factor(x)) return(as.integer(x))
  if (is.list(x) && !inherits(x, "numeric_version")) {
    x <- lapply(unclass(x), function(e) if (is.null(e)) NULL else strip_labels(e))
  }
  attr(x, "names") <- NULL; attr(x, "levels") <- NULL
  if (is.list(x)) attr(x, "row.names") <- NULL
  x
}
all_strings <- function(x) {
  out <- c(names(x), if (is.factor(x)) levels(x), if (is.character(x)) x)
  if (is.list(x) && !inherits(x, "numeric_version"))
    for (e in x) out <- c(out, all_strings(e))
  out
}

chain_provenance <- function(p, extra) {
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
  utils::modifyList(p, extra)
}

process <- function(old, new = old, relabel = FALSE) {
  f_old <- file.path(EXT, paste0(old, ".rds"))
  f_new <- file.path(EXT, paste0(new, ".rds"))
  if (!file.exists(f_old)) {
    if (file.exists(f_new)) return(message(old, ": already done"))
    stop(f_old, " not found")
  }
  b <- readRDS(f_old)
  if (is.null(b$provenance)) {
    if (relabel) stop(old, " has no provenance to record a relabel in")
    stopifnot(file.rename(f_old, f_new))
    return(message(sprintf("%s -> %s (moved byte for byte)", old, new)))
  }

  out <- b
  if (relabel) {
    body <- b[setdiff(names(b), "provenance")]
    new_body <- relabel_all(body, LABELS)
    # Proof that only labels moved: with every string, factor level and
    # name stripped, the two objects are identical, and every string that
    # differs is one of the labels mapped above.
    stopifnot(identical(strip_labels(new_body), strip_labels(body)))
    was <- all_strings(body); now <- all_strings(new_body)
    stopifnot(length(was) == length(now))
    d <- which(is.na(was) != is.na(now) | (!is.na(was) & !is.na(now) & was != now))
    stopifnot(all(was[d] %in% names(LABELS)),
              identical(unname(now[d]), unname(LABELS[was[d]])))
    out[names(new_body)] <- new_body
  }
  extra <- list()
  if (!identical(old, new)) extra$renamed_from <- basename(f_old)
  if (relabel) extra$relabelled <- paste(sprintf("'%s' -> '%s'", names(LABELS), LABELS),
                                         collapse = "; ")
  out$provenance <- chain_provenance(b$provenance, extra)
  saveRDS(out, f_new, version = 3, compress = "xz")
  if (!identical(f_old, f_new)) file.remove(f_old)
  message(sprintf("%s -> %s%s", old, new, if (relabel) " (labels translated)" else ""))
}

process("pilar8_real_pedons",     "pillar8_real_pedons")
process("benchmark_wosis_6pilar", "benchmark_wosis_6pillar")
process("pilar10_gat_tuning",     "pillar10_gat_tuning")
process("capstone_campaign_results",    relabel = TRUE)
process("capstone_native_calibration",  relabel = TRUE)
