#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# tools/status/render-cran-comments.R -- generate cran-comments.md
#
# cran-comments.md is a statement to CRAN about what a real check reported.
# Writing it by hand is how it came to claim "0 errors | 0 warnings | 0 notes"
# for a tree that produced 2 errors.  This script derives every quantity from
# tools/status/facts.json (written by tools/status/facts.R from a real
# `R CMD check --as-cran` log) so the file cannot drift from the check again.
#
#   Rscript tools/status/facts.R --check-log=<log>
#   Rscript tools/status/render-cran-comments.R
#
# Prose that is a judgement rather than a measurement -- why a NOTE is
# acceptable -- lives in tools/status/check-classification.json, keyed by the
# check name, so it too is reviewable rather than improvised.
# ---------------------------------------------------------------------------

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=",
          commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
setwd(root)

facts <- jsonlite::fromJSON("tools/status/facts.json", simplifyVector = TRUE)
cls   <- jsonlite::fromJSON("tools/status/check-classification.json",
                            simplifyVector = TRUE)

ck <- facts$check
if (is.null(ck$status_line))
  stop("facts.json carries no parsed check log. Run:\n",
       "  R CMD build . && R CMD check --as-cran edaphos_*.tar.gz 2>&1 | tee check.log\n",
       "  Rscript tools/status/facts.R --check-log=check.log", call. = FALSE)

e  <- facts$environment
d  <- facts$description
tr <- facts$tests_run
sz <- facts$size

`%||%` <- function(a, b) if (is.null(a) || !length(a) ||
                            (length(a) == 1L && is.na(a))) b else a
out <- character()
add <- function(...) out <<- c(out, ...)
mb  <- function(b) if (is.null(b) || !length(b) || is.na(b)) "unknown" else
         sprintf("%.1f MB", as.numeric(b) / 1024^2)

add("<!-- GENERATED FILE -- DO NOT EDIT BY HAND.",
    "     Regenerate:  Rscript tools/status/facts.R --check-log=<log>",
    "                  Rscript tools/status/render-cran-comments.R",
    "     Every figure below is read from a real R CMD check log. -->",
    "",
    sprintf("# cran-comments for edaphos %s", d$version %||% "?"),
    "")

# ---- test environments (measured) -----------------------------------------
add("## Test environments", "",
    sprintf("* %s %s, %s, R %s (%s)",
            e$os %||% "?", e$os_release %||% "?", e$platform %||% "?",
            e$r_version %||% "?", e$r_nickname %||% "?"),
    "")
legs <- facts$ci$matrix_legs
if (length(legs))
  add("GitHub Actions `R-CMD-check` also runs:", "",
      paste0("* ", gsub("^\\s*-\\s*", "", legs)), "")
miss <- facts$dependencies$suggests_missing
if (length(miss))
  add(sprintf(paste("The local check ran with `_R_CHECK_FORCE_SUGGESTS_=false`",
                    "because %d Suggests are not installable on the checking",
                    "machine: %s. Tests and vignette chunks that need them are",
                    "skipped there and exercised on CI instead."),
              length(miss), paste(miss, collapse = ", ")), "")

# ---- results (verbatim) ---------------------------------------------------
add("## R CMD check results", "",
    "`R CMD build . && R CMD check --as-cran` reported:", "",
    "```", ck$status_line, "```", "")

lvl_items <- function(level) {
  key <- switch(level, ERROR = "errors", WARNING = "warnings",
                NOTE = "notes", INFO = "infos")
  v <- ck[[key]]
  v[!is.na(v) & nzchar(v)]
}

for (level in c("ERROR", "WARNING", "NOTE", "INFO")) {
  items <- lvl_items(level)
  if (!length(items)) next
  add(sprintf("### %ss (%d)", level, length(items)), "")
  for (nm in items) {
    row <- cls$items[cls$items$check == nm, ]
    if (!NROW(row)) {
      add(sprintf("* **%s** — no classification recorded for this item yet; see `tools/status/check-classification.json`.",
                  nm))
      next
    }
    row <- row[1, ]
    add(sprintf("* **%s**", nm),
        sprintf("  * %s", row$summary),
        sprintf("  * Origin: %s", row$class),
        sprintf("  * %s", row$fix))
  }
  add("")
}

if (!isTRUE(ck$counts_reconcile))
  add(paste("> The item lists above were extracted by parsing the log and do",
            "not add up to R's own `Status:` line. Treat them as incomplete",
            "and read the log directly."), "")

# ---- size, verbatim from the log -----------------------------------------
if (length(ck$installed_size)) {
  add("## Installed size", "",
      "Verbatim from the check log:", "",
      "```", ck$installed_size, "```", "")
  # The justification is a reviewed statement, not something this script
  # invents: it lives on the installed-size item in check-classification.json.
  row <- cls$items[cls$items$check == "checking installed package size", ]
  if (NROW(row) && !is.null(row$cran_note) && !is.na(row$cran_note[1]))
    add(row$cran_note[1], "")
  add(sprintf("Git-tracked payload that ships in the tarball: %s across %d tracked files.",
              mb(sz$shipped_bytes), sz$tracked_file_count %||% NA), "")
}

ci_ <- ck$cran_incoming
if (!is.null(ci_)) {
  add("## CRAN incoming feasibility", "")
  if (isTRUE(ci_$is_new_submission))
    add("This is a new submission. The package has not been on CRAN before.", "")
  if (length(ci_$invalid_urls))
    add(sprintf("The check flagged %d redirecting URL(s); each has been updated in this tree:",
                length(ci_$invalid_urls)), "",
        paste0("* ", ci_$invalid_urls), "")
  # `R CMD check` only prints "Size of tarball:" above a threshold, so this
  # is legitimately absent on most runs and arrives as NULL through JSON.
  # Prefer the direct on-disk measurement, and say so when neither exists --
  # a missing measurement must not abort the render.
  tb <- if (length(sz$tarball_bytes) == 1L &&
            !is.na(sz$tarball_bytes)) sz$tarball_bytes
        else if (length(ci_$tarball_bytes) == 1L &&
                 !is.na(ci_$tarball_bytes)) ci_$tarball_bytes
        else NULL
  if (!is.null(tb)) {
    add(sprintf("Source tarball: %s (CRAN's guidance is 5 MB).", mb(tb)), "")
  } else {
    add("Source tarball size: _not measured_.", "")
  }
}

# ---- tests ---------------------------------------------------------------
if (!is.null(tr$passed) && !is.na(tr$passed)) {
  add("## Tests", "",
      sprintf(paste("`testthat` on the checking machine: **%d passing**, %d",
                    "skipped, %d failing, %d erroring, across %d test files",
                    "(%d `test_that` blocks, %d expectations in source)."),
              tr$passed, tr$skipped, tr$failed, tr$errored, tr$files,
              facts$tests_static$test_that_blocks,
              facts$tests_static$expect_calls), "")
  if (length(ck$test_summary))
    add("As the check itself reported it:", "",
        "```", trimws(ck$test_summary[1]), "```", "")
  add(sprintf(paste("The skips are `skip_if_not_installed()` gates on optional",
                    "Suggests; %d of the %d gate sites in the suite are for",
                    "packages absent from the checking machine."),
              length(miss), facts$tests_static$skip_if_not_installed), "")
}

# ---- downstream ----------------------------------------------------------
add("## Downstream dependencies", "",
    if (isTRUE(ci_$is_new_submission))
      "None: this is a new submission, so there are no reverse dependencies."
    else "See revdep/ for the reverse-dependency check results.", "")

add("---", "",
    sprintf(paste("Generated by `tools/status/render-cran-comments.R` from",
                  "`%s` (sha256 `%s`) at commit `%s`."),
            basename(ck$log_path %||% "?"),
            substr(ck$log_sha256 %||% "?", 1, 16),
            facts$git$head_sha_short %||% "?"))

con <- file(file.path(root, "cran-comments.md"), open = "w", encoding = "UTF-8")
writeLines(out, con)
close(con)
cat("wrote cran-comments.md —", length(out), "lines from",
    basename(ck$log_path), "\n")
