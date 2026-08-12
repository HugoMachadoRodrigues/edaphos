#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# tools/status/patch-readme-metrics.R -- rewrite README.md's measurable claims
#
# README.md carries live claims about the package: a test-count badge, a
# vignette-count badge, and a "Testing and continuous integration" section
# stating a check result.  All of them were typed by hand and all of them were
# wrong (the badge said 1345, the section said "109+ ... on v1.7.0").
#
# This script rewrites exactly those spans from tools/status/facts.json.  It
# touches nothing else in the README and fails loudly if an anchor it expects
# has moved, rather than silently doing nothing.
#
#   Rscript tools/status/facts.R
#   Rscript tools/status/patch-readme-metrics.R
# ---------------------------------------------------------------------------

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=",
          commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
setwd(root)

facts <- jsonlite::fromJSON("tools/status/facts.json", simplifyVector = TRUE)
tr <- facts$tests_run
ck <- facts$check
if (is.null(tr$passed) || is.na(tr$passed))
  stop("facts.json has no test run. Run Rscript tools/status/facts.R first.",
       call. = FALSE)

readme <- readLines("README.md", warn = FALSE, encoding = "UTF-8")
Encoding(readme) <- "UTF-8"
changed <- character()

replace_one <- function(pattern, value, what) {
  i <- grep(pattern, readme, perl = TRUE)
  if (length(i) != 1L)
    stop(sprintf("expected exactly 1 match for %s, found %d", what, length(i)),
         call. = FALSE)
  old <- readme[i]
  readme[i] <<- sub(pattern, value, readme[i], perl = TRUE)
  if (!identical(old, readme[i]))
    changed <<- c(changed, sprintf("README.md:%d  %s", i, what))
  invisible(TRUE)
}

# --- badges ----------------------------------------------------------------
replace_one("(?<=badge/tests-)[0-9]+(?=%20pass)",
            format(tr$passed, scientific = FALSE), "tests badge")
# The version badge read 3.10.0 -- ten minor versions behind DESCRIPTION -- and
# linked to releases/tag/v3.10.0. Take the number from DESCRIPTION, and note
# that the LINK must stay on /releases rather than /releases/tag/vX: the
# DESCRIPTION version is routinely ahead of any tag (last tag here is
# git$last_tag), so a per-tag link is a 404 waiting to happen.
# The badge may carry a status suffix -- "0.9.0--dev" -- which says more than
# the bare version and should not be erased to satisfy a regex. Match the
# numeric part wherever it sits and leave any suffix alone.
replace_one("(?<=badge/version-)[0-9]+[.][0-9]+[.][0-9]+(?=(--[a-z]+)?-informational)",
            facts$description$version, "version badge")
replace_one("(?<=badge/vignettes-)[0-9]+(?=-)",
            format(facts$docs$vignette_count, scientific = FALSE),
            "vignettes badge")

# --- the Testing and CI section --------------------------------------------
start <- grep("^## Testing and continuous integration\\s*$", readme)
if (length(start) != 1L)
  stop("could not locate a unique '## Testing and continuous integration' heading",
       call. = FALSE)
# the section runs to the next horizontal rule
rest  <- readme[(start + 1L):length(readme)]
stop_rel <- which(trimws(rest) == "---")[1]
if (is.na(stop_rel)) stop("no '---' terminator after the testing section",
                          call. = FALSE)
end <- start + stop_rel - 1L

miss <- facts$dependencies$suggests_missing
gates <- facts$tests_static$gate_counts
gated <- if (NROW(gates)) gates$dependency[gates$gate_sites > 0] else character()

section <- c(
  "",
  sprintf(paste0("- **%s passing expectations** across %s `test_that` blocks in ",
                 "%s test files (`testthat`), measured on %s, R %s. %s; ",
                 "every skip is an explicit `skip_if_not_installed()` gate."),
          format(tr$passed, big.mark = " "),
          format(facts$tests_static$test_that_blocks, big.mark = " "),
          format(tr$files, big.mark = " "),
          facts$environment$platform, facts$environment$r_version,
          # The skip count is down to 1 on this machine, so the sentence has to
          # agree with the number it is given rather than assume a plural.
          if (identical(as.integer(tr$skipped), 0L))
            "Nothing is skipped here"
          else if (identical(as.integer(tr$skipped), 1L))
            "One expectation is skipped here, because its optional dependency is absent"
          else sprintf(paste("%s expectations are skipped here, because their",
                             "optional dependencies are absent"),
                       format(tr$skipped, big.mark = " "))),
  sprintf("- **Gated dependencies:** %s.",
          if (length(gated)) paste0("`", gated, "`", collapse = ", ") else "none"),
  sprintf(paste0("- **`R CMD check --as-cran`:** `%s` at commit `%s`. ",
                 "The per-item breakdown, including which items are package ",
                 "defects and which are artefacts of the checking machine, is ",
                 "in [`cran-comments.md`](cran-comments.md); the log itself is ",
                 "committed at [`tools/status/check.log`](tools/status/check.log)."),
          if (length(ck$status_line)) sub("^Status:\\s*", "", ck$status_line[1])
            else "not measured",
          facts$git$head_sha_short),
  paste0("- **CI:** GitHub Actions matrix on ",
         paste0("`", vapply(facts$ci$matrix_legs, function(leg) {
                  os <- trimws(sub("^.*\\{os:\\s*([^,}]+).*$", "\\1", leg))
                  r  <- trimws(gsub("'", "", sub("^.*r:\\s*([^,}]+).*$", "\\1", leg)))
                  if (identical(os, r)) os else paste0(os, " / R ", r)
                }, character(1)), "`", collapse = ", "),
         ". Note that `TORCH_INSTALL: 0` is set, so libtorch is never installed",
         " on any leg and the torch-gated tests do not execute in CI."),
  "- These figures are generated by `tools/status/patch-readme-metrics.R`",
  "  from a real test run and a real check log. Do not edit them by hand.",
  ""
)

readme <- c(readme[seq_len(start)], section, readme[(end):length(readme)])
changed <- c(changed, sprintf("README.md:%d  Testing and CI section (%d lines)",
                              start, length(section)))

con <- file("README.md", open = "w", encoding = "UTF-8")
writeLines(readme, con)
close(con)

cat("patched README.md:\n")
cat(paste0("  ", changed, collapse = "\n"), "\n")
