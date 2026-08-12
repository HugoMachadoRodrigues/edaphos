# ---------------------------------------------------------------------------
# Binding a shipped bundle to the script that produced it.
#
# WHY THIS EXISTS. Every published number in the manuscript and the README is
# read from an .rds in inst/extdata. Until now nothing connected a bundle to
# the code that built it: bundles stamped four incompatible conventions
# (`version`, `edaphos_ver`, `built_by`, `date_computed`, `created_at`), only
# three of twenty-five carried the current package version, and no test read
# any of those fields.
#
# The cost of that was not hypothetical. inst/extdata/case_cerrado_results.rds
# published a conclusion for four months that its own -- already fixed --
# defect had produced: the fix landed in data-raw/case_cerrado_run.R and the
# bundle was never re-run, while its stamped version and date sat frozen. It
# was caught by reading, not by a check.
#
# WHY A HASH AND NOT A TIMESTAMP. A timestamp records when a bundle was built,
# which does not answer the question that matters -- has the script changed
# since? File mtimes are not in git and differ in every clone, and a recorded
# date cannot be compared to anything a checkout knows. A hash of the
# producing script's CONTENT can: store it at build time, recompute it at test
# time, and a mismatch means the script moved on without the bundle.
#
# Line endings are normalised before hashing, so a checkout with different
# `core.autocrlf` settings does not report every bundle as stale.
# ---------------------------------------------------------------------------

# Hash a script's content, normalised. Returns NA_character_ when the file is
# unreadable, so a caller can record the failure rather than a wrong value.
.script_hash <- function(path) {
  if (!length(path) || length(path) > 1L || is.na(path) || !file.exists(path))
    return(c(hash = NA_character_, algo = NA_character_))
  txt <- tryCatch(paste(readLines(path, warn = FALSE), collapse = "\n"),
                  error = function(e) NULL)
  if (is.null(txt)) return(c(hash = NA_character_, algo = NA_character_))
  # THE ALGORITHM TRAVELS WITH THE HASH. `digest` is a Suggests, so on a
  # machine without it the fallback is an md5 of the file -- a different
  # algorithm over different bytes. An earlier version of this stored that md5
  # into a field named `script_sha256` and compared it against a sha256, which
  # is never equal: every provenanced bundle would have reported "has changed,
  # re-run it" on any machine lacking an optional package. Returning the
  # algorithm alongside lets the check REFUSE to compare rather than report a
  # false mismatch.
  if (requireNamespace("digest", quietly = TRUE))
    return(c(hash = digest::digest(txt, algo = "sha256"), algo = "sha256"))
  c(hash = unname(tools::md5sum(path)), algo = "md5-file")
}

# Resolve a repo-relative script path against the package root rather than
# getwd(). The hash was computed against getwd() and the check against `root`,
# so calling this from tests/testthat/ silently produced NA -- which made a
# skip_if() fire and quietly disabled the assertions that prove detection
# works at all.
.provenance_root <- function(start = ".") {
  d <- tryCatch(normalizePath(start, mustWork = FALSE), error = function(e) start)
  for (i in 1:6) {
    if (file.exists(file.path(d, "DESCRIPTION")) && dir.exists(file.path(d, "data-raw")))
      return(d)
    up <- dirname(d)
    if (identical(up, d)) break
    d <- up
  }
  NA_character_
}

#' Provenance for a generated data bundle
#'
#' Builds the block every `data-raw/` script attaches to the object it saves,
#' so a shipped bundle names the script that produced it and carries a hash of
#' that script's content.
#'
#' @section What the hash is for:
#' Not integrity — reproducibility. A recorded build date cannot tell a reader
#' whether the script has changed since; a content hash can. `edaphos` shipped
#' a published conclusion for four months after the defect that produced it was
#' fixed, because the code changed and the bundle did not. Comparing the stored
#' hash against the current script is what makes that state visible, and
#' `tests/testthat/test-bundle-provenance.R` does exactly that for every
#' bundle in `inst/extdata`.
#'
#' @param script Path to the producing script, relative to the package root
#'   (e.g. `"data-raw/piml_depth_benchmark.R"`). When `NULL`, it is derived
#'   from the running script's own path, which is what a `data-raw` script
#'   wants and cannot easily determine itself.
#' @param ... Extra named fields to record alongside — anything the script
#'   knows and a reader would want, such as the number of profiles used.
#'
#' @return A named list with `script`, `script_sha256`, `hash_algo`,
#'   `package_version`, `r_version`, `built_at` and any extras.
#'
#' @export
#' @examples
#' p <- edaphos_provenance(script = "data-raw/example.R", n_profiles = 42L)
#' names(p)
#' p$package_version
edaphos_provenance <- function(script = NULL, ...) {
  if (is.null(script)) {
    # Rscript exposes the running file as --file=; inside R CMD build or a
    # sourced call it does not, and NA is the honest answer.
    a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    script <- if (length(a)) sub("^--file=", "", a[1]) else NA_character_
    if (!is.na(script)) {
      script <- tryCatch(normalizePath(script, mustWork = FALSE),
                         error = function(e) script)
      # store it repo-relative, so the record means the same in any clone
      root <- tryCatch(normalizePath(".", mustWork = FALSE), error = function(e) "")
      if (nzchar(root) && startsWith(script, root))
        script <- sub("^/", "", substr(script, nchar(root) + 1L, nchar(script)))
    }
  }
  root <- .provenance_root()
  hpath <- if (!is.na(script) && !is.na(root) && !file.exists(script))
    file.path(root, script) else script
  h <- .script_hash(hpath)
  list(
    script          = script,
    script_sha256   = unname(h[["hash"]]),
    hash_algo       = unname(h[["algo"]]),
    package_version = as.character(utils::packageVersion("edaphos")),
    r_version       = paste(R.version$major, R.version$minor, sep = "."),
    built_at        = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    ...
  )
}

#' Check a bundle against the script that produced it
#'
#' Reads the provenance block written by [edaphos_provenance()] and reports
#' whether the producing script has changed since the bundle was built.
#'
#' @param bundle Either a path to an `.rds` or an already-loaded list.
#' @param root Package root to resolve the recorded script path against.
#'   Defaults to the current directory.
#'
#' @return A list with `ok` (logical, or `NA` when the bundle carries no
#'   provenance) and `reason`. `ok = NA` is deliberately not `FALSE`: a bundle
#'   with no block is unbindable rather than stale, and the two want different
#'   remedies.
#'
#' @seealso [edaphos_provenance()]
#' @export
#' @examples
#' # A bundle that carries no provenance reports NA, not FALSE.
#' edaphos_provenance_check(list(a = 1))
edaphos_provenance_check <- function(bundle, root = ".") {
  b <- if (is.character(bundle) && length(bundle) == 1L && file.exists(bundle))
    readRDS(bundle) else bundle
  p <- if (is.list(b)) b[["provenance"]] else NULL
  if (is.null(p) || is.null(p$script) || length(p$script) != 1L || is.na(p$script))
    return(list(ok = NA, reason = "no provenance block"))

  path <- file.path(root, p$script)
  if (!file.exists(path))
    return(list(ok = FALSE,
                reason = sprintf("producing script '%s' is not in this checkout",
                                 p$script)))
  h <- .script_hash(path)
  now <- unname(h[["hash"]])
  if (is.na(now) || is.null(p$script_sha256) || is.na(p$script_sha256))
    return(list(ok = NA, reason = "hash unavailable on one side"))
  # Refuse to compare across algorithms rather than report a false mismatch.
  if (!is.null(p$hash_algo) && !is.na(p$hash_algo) &&
      !identical(unname(h[["algo"]]), p$hash_algo))
    return(list(ok = NA,
                reason = sprintf(paste("recorded with %s, this machine computes",
                                       "%s; install `digest` to compare"),
                                 p$hash_algo, unname(h[["algo"]]))))
  if (!identical(now, p$script_sha256))
    return(list(ok = FALSE,
                reason = sprintf(paste("'%s' has changed since this bundle was",
                                       "built (%s); re-run it"),
                                 p$script, p$built_at %||% "date unrecorded")))
  list(ok = TRUE, reason = "")
}
