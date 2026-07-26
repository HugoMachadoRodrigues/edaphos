#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# tools/status/render.R -- render STATUS.md from measured facts + audit register
#
# Inputs (never edited by hand):
#   tools/status/facts.json    <- written by tools/status/facts.R (live measurement)
#   tools/status/findings.json <- frozen output of the 12-agent audit
#
# Output:
#   STATUS.md
#
# The ONLY editorial content in this script is the phase mapping in
# `PHASES` below, which groups findings into a work order.  Every quantity
# rendered is read from facts.json; if a fact was not measured, the document
# says so instead of printing a number.
# ---------------------------------------------------------------------------

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=",
          commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
setwd(root)

facts <- jsonlite::fromJSON("tools/status/facts.json", simplifyVector = TRUE)
reg   <- jsonlite::fromJSON("tools/status/findings.json", simplifyVector = TRUE)
cls   <- if (file.exists("tools/status/check-classification.json"))
  jsonlite::fromJSON("tools/status/check-classification.json", simplifyVector = TRUE) else NULL
F     <- reg$findings

# -- formatting helpers -----------------------------------------------------

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L ||
                            (length(a) == 1L && is.na(a))) b else a
nz     <- function(x) x[!is.na(x) & nzchar(as.character(x))]
num    <- function(x, d = 0) if (is.null(x) || length(x) == 0L || is.na(x))
            "_not measured_" else formatC(as.numeric(x), format = "f",
                                          digits = d, big.mark = " ")
mb     <- function(bytes) {
  if (is.null(bytes) || length(bytes) == 0L) return("_not measured_")
  b <- as.numeric(bytes)
  ifelse(is.na(b), "_not measured_",
    ifelse(b >= 1024^2, sprintf("%.2f MB", b / 1024^2),
                        sprintf("%.0f KB", b / 1024)))
}
sig    <- function(x, d = 3) {
  if (is.null(x) || length(x) == 0L) return(character())
  ifelse(is.na(x), "", format(signif(as.numeric(x), d), scientific = NA,
                              trim = TRUE))
}
code   <- function(x) paste0("`", x, "`")
yn     <- function(x) if (isTRUE(x)) "yes" else if (isFALSE(x)) "no" else "_unknown_"
tick   <- function(x) if (isTRUE(x)) "✅" else "❌"

# collapse a character vector into an inline list, capped
inline <- function(x, cap = 12) {
  x <- as.character(nz(x))
  if (!length(x)) return("_none_")
  if (length(x) <= cap) return(paste(code(x), collapse = ", "))
  paste0(paste(code(x[seq_len(cap)]), collapse = ", "),
         sprintf(" … (+%d more)", length(x) - cap))
}

# markdown table from a data.frame
mdtable <- function(df, align = NULL) {
  if (is.null(df) || !NROW(df)) return("_no rows_")
  df[] <- lapply(df, function(c) {
    c <- as.character(c)
    c[is.na(c)] <- ""
    gsub("|", "\\|", c, fixed = TRUE)
  })
  al <- align %||% rep("---", ncol(df))
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("| ", paste(al, collapse = " | "), " |"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

# blockquote a captured log tail verbatim
verbatim <- function(x, lang = "") {
  x <- as.character(nz(x))
  if (!length(x)) return("_not captured_")
  c(paste0("```", lang), x, "```")
}

SEV_ORDER <- c("blocker", "high", "medium", "low", "non-issue")
sev <- function(f) f$severity_verified %||% f$severity_reported
sevv <- ifelse(is.na(F$severity_verified), F$severity_reported, F$severity_verified)
F$sev <- factor(sevv, levels = SEV_ORDER)
AREA <- c(science = "Scientific reproducibility", release = "Release consistency",
          cran = "CRAN readiness", tests = "Test coverage", ci = "CI & infra",
          stubs = "Incomplete implementations", code = "Code quality",
          roadmap = "Roadmap promises", other = "Other")

# ---- the one editorial layer: work order ---------------------------------
PHASES <- list(
  # Phase 0 is named explicitly: the smallest set that makes `R CMD check`
  # truthful, so every later phase can be verified rather than asserted.
  list(id = "0", name = "Make R CMD check truthful",
       why = paste("Nothing else can be verified while the check is red and the",
                   "release paperwork asserts it is green. Every item here is",
                   "minutes-to-hours and needed before any claim can be re-stated."),
       pick = function(F) intersect(
         c("FF20A54",   # "0 errors / 0 notes" is false
           "FC68E1D",   # foundation_weights_load gates on torch before validating
           "FAEC54C",   # al_fit num.trees has no guard; test unseeded
           "FA81F77",   # utils / tools undeclared in Imports
           "F52C0B8",   # cran-comments.md self-contradictory
           "F2F16E8",   # cran-comments.md sizes wrong
           "F5F7D9A",   # the "1 345 tests" figure
           "F64B0F0"),  # reticulate required but never used
         F$id)),
  list(id = "1", name = "Scientific integrity",
       why = "In a research package the empirical claims are the product.",
       pick = function(F) F$id[F$area == "science" &
                               F$sev %in% c("blocker", "high", "medium")]),
  list(id = "2", name = "Version coherence",
       why = "One version number, asserted in one place, tagged once.",
       pick = function(F) F$id[F$area == "release" &
                               F$sev %in% c("blocker", "high", "medium")]),
  list(id = "3", name = "Close the ten-pillar promise",
       why = "DESCRIPTION claims ten pillars; the shipped docs document six.",
       pick = function(F) F$id[F$area %in% c("roadmap", "stubs") &
                               F$sev %in% c("blocker", "high", "medium")]),
  list(id = "4", name = "CRAN submission",
       why = "Only meaningful once phases 0-3 hold.",
       pick = function(F) F$id[F$area %in% c("cran", "ci") &
                               F$sev %in% c("high", "medium")]),
  list(id = "5", name = "Code quality and tech debt",
       why = "Non-blocking, but cheaper to fix before the API is frozen by CRAN.",
       pick = function(F) F$id[F$area %in% c("code", "tests") &
                               F$sev %in% c("high", "medium")])
)

out <- character()
add <- function(...) out <<- c(out, ...)

# ===========================================================================
# Header
# ===========================================================================
g <- facts$git; d <- facts$description; e <- facts$environment
add(
  "<!-- GENERATED FILE -- DO NOT EDIT BY HAND.",
  "     Regenerate:  Rscript tools/status/facts.R [--check-log=LOG]",
  "                  Rscript tools/status/render.R                     -->",
  "",
  "# edaphos — development status",
  "",
  sprintf("**Commit** `%s` (`%s`) — **DESCRIPTION version** `%s` — **measured** %s",
          g$head_sha_short %||% "?", g$branch %||% "?",
          d$version %||% "?", e$measured_at_utc %||% "?"),
  "",
  "Every quantity in this document is measured at render time by",
  "[`tools/status/facts.R`](tools/status/facts.R) and rendered by",
  "[`tools/status/render.R`](tools/status/render.R). Nothing is typed by hand.",
  "A quantity that could not be measured prints `_not measured_` rather than a",
  "plausible-looking value. The findings register comes from",
  "[`tools/status/findings.json`](tools/status/findings.json), the frozen output of an",
  sprintf("adversarial audit of commit `%s`.", substr(reg$provenance$audited_commit, 1, 7)),
  ""
)

# ===========================================================================
# 1. Headline
# ===========================================================================
tr <- facts$tests_run
ck <- facts$check
has_test <- !is.null(tr$passed) && !is.na(tr$passed)
has_check <- !is.null(ck$status_line)

add("## 1. Headline", "",
  mdtable(data.frame(
    Measure = c("Commits", "First → last commit", "Days since last commit",
                "NEWS release sections", "Git tags",
                "NEWS versions with no tag", "R/ source lines",
                "Exported functions", "Test blocks",
                "Tests passing", "Tests skipped", "Test failures + errors",
                "R CMD check status", "Shipped bytes",
                "Findings open (blocker/high)"),
    Value = c(
      num(g$commit_count),
      sprintf("%s → %s (%s calendar days, %s with commits)",
              substr(g$first_commit %||% "?", 1, 10),
              substr(g$last_commit %||% "?", 1, 10), num(g$span_days, 1),
              num(g$active_days)),
      num(g$days_since_last, 0),
      num(facts$news$section_count),
      num(g$tag_count),
      num(facts$versioning$n_news_without_tag),
      num(facts$code$r_loc),
      num(facts$code$n_exports),
      num(facts$tests_static$test_that_blocks),
      if (has_test) num(tr$passed) else "_not measured_",
      if (has_test) num(tr$skipped) else "_not measured_",
      if (has_test) num(tr$failed + tr$errored) else "_not measured_",
      if (has_check) paste(ck$status_line, collapse = "; ") else
        paste0("_", ck$status %||% "not measured", "_"),
      mb(facts$size$shipped_bytes),
      num(sum(F$sev %in% c("blocker", "high")))
    ), stringsAsFactors = FALSE),
    align = c("---", "---")),
  "")

add("### Stage assessment", "",
    "From the audit's completeness critic (editorial, not measured):", "",
    paste0("> ", strwrap(reg$critique$stage_verdict, 100)), "",
    "**Strongest single piece of evidence:**", "",
    paste0("> ", strwrap(reg$critique$strongest_evidence, 100)), "")

# ===========================================================================
# 2. Measurement provenance
# ===========================================================================
dep <- facts$dependencies
add("## 2. Measurement provenance", "",
  mdtable(data.frame(
    Field = c("R version", "Platform", "OS", "Worktree clean",
              "Local vs origin/main", "Optional deps missing"),
    Value = c(sprintf("%s (%s)", e$r_version %||% "?", e$r_nickname %||% "?"),
              e$platform %||% "?",
              sprintf("%s %s", e$os %||% "?", e$os_release %||% "?"),
              yn(g$worktree_clean),
              sprintf("`%s` (ahead / behind)",
                      gsub("\\s+", " / ", g$ahead_behind_origin_main %||% "?")),
              num(dep$n_missing)),
    stringsAsFactors = FALSE)), "")

if (length(nz(dep$suggests_missing)))
  add(sprintf("Suggests **not installed** in the measuring environment: %s.",
              inline(dep$suggests_missing, 20)),
      "Every test and vignette gated on these is skipped, so the pass counts below",
      "are a floor, not a total.", "")

# ===========================================================================
# 3. The git clock
# ===========================================================================
add("## 3. The git clock", "",
    sprintf("`%s` — %s commits across %s active days.",
            g$head_sha_short %||% "?", num(g$commit_count), num(g$active_days)),
    "")
if (length(g$commits_per_day)) {
  cpd <- unlist(g$commits_per_day)
  add(mdtable(data.frame(Date = names(cpd), Commits = as.integer(cpd),
                         stringsAsFactors = FALSE), c("---", "--:")), "")
}
add(sprintf("Releases declared in `NEWS.md`: **%s**. Git tags: **%s**.",
            num(facts$news$section_count), num(g$tag_count)),
    sprintf("Tags present: %s.", inline(g$tags, 25)),
    sprintf("Commits since the newest tag (`%s`): **%s**.",
            g$last_tag %||% "?", num(g$commits_since_last_tag)), "")
if (length(nz(facts$versioning$news_versions_without_tag)))
  add(sprintf("`NEWS.md` versions with **no git tag** (%s): %s.",
              num(facts$versioning$n_news_without_tag),
              inline(facts$versioning$news_versions_without_tag, 40)), "")

# ===========================================================================
# 4. Version coherence
# ===========================================================================
vf <- facts$versioning
add("## 4. Version coherence", "",
  mdtable(data.frame(
    Check = c("DESCRIPTION version equals newest NEWS section",
              "DESCRIPTION version has a git tag",
              "HEAD is the tagged release commit",
              "Every NEWS release is tagged"),
    Result = c(paste(tick(vf$description_matches_news),
                     sprintf("(DESCRIPTION `%s`, NEWS `%s`)",
                             vf$description_version %||% "?",
                             vf$newest_news_version %||% "?")),
               paste(tick(vf$description_has_tag),
                     sprintf("(`v%s`)", vf$description_version %||% "?")),
               paste(tick(isTRUE(g$commits_since_last_tag == 0L)),
                     sprintf("(%s commits past `%s`)",
                             num(g$commits_since_last_tag), g$last_tag %||% "?")),
               paste(tick(isTRUE(vf$n_news_without_tag == 0L)),
                     sprintf("(%s of %s untagged)",
                             num(vf$n_news_without_tag),
                             num(facts$news$section_count)))),
    stringsAsFactors = FALSE)), "")

cl <- vf$claims
add("Version strings each artefact claims for the package:", "",
  mdtable(data.frame(
    Artefact = c("DESCRIPTION", "NEWS.md", "README.md", "CITATION.cff",
                 ".zenodo.json"),
    Claims = c(code(cl$DESCRIPTION %||% "?"), code(cl$NEWS.md %||% "?"),
               inline(cl$README.md), inline(cl$CITATION.cff),
               if (isTRUE(cl$zenodo.json_has_version)) "has a version field"
                 else "**no version field at all**"),
    stringsAsFactors = FALSE)), "")

vdr <- facts$version_drift
if (length(nz(vdr$phantom_versions))) {
  add(sprintf("Version strings asserted inside shipped `R/` or `man/` that **neither a `NEWS.md` section nor a git tag declares** (%s): %s. Each names a release that never existed.",
              num(vdr$n_phantom_versions),
              inline(vdr$phantom_versions, 20)), "")
  sc <- vdr$sites_claiming_phantom_version
  if (NROW(sc))
    add(mdtable(data.frame(File = code(sc$file), Line = sc$line,
                           Version = code(sc$version),
                           row.names = NULL, stringsAsFactors = FALSE),
                c("---", "--:", "---")), "")
}
if (length(nz(vf$tags_without_news)))
  add(sprintf("Conversely, git tags with **no `NEWS.md` section**: %s.",
              inline(paste0("v", vf$tags_without_news), 20)), "")

ri <- vf$readme_install_refs
if (NROW(ri))
  add("Git refs the README tells users to install:", "",
      mdtable(data.frame(Ref = code(ri$ref),
                         Resolves = vapply(ri$resolves, tick, character(1)),
                         stringsAsFactors = FALSE)), "")

# ===========================================================================
# 5. Build and check
# ===========================================================================
add("## 5. `R CMD build` / `R CMD check --as-cran`", "")
if (has_check) {
  add(mdtable(data.frame(
        Result = c("Status", "ERRORs", "WARNINGs", "NOTEs"),
        Value  = c(paste(ck$status_line, collapse = "; "),
                   num(ck$n_errors), num(ck$n_warnings), num(ck$n_notes)),
        stringsAsFactors = FALSE)), "")
  add(sprintf("Counts are taken from R's own `Status:` line; an independent walk of the log %s.",
              if (isTRUE(ck$counts_reconcile)) "agrees" else
                "**disagrees — treat the item lists below as incomplete**"), "")
  for (nm in c("errors", "warnings", "notes", "infos")) {
    v <- nz(ck[[nm]])
    if (length(v)) add(sprintf("**%s:**", toupper(nm)), "",
                       paste0("- ", code(v)), "")
  }
  ci_ <- ck$cran_incoming
  if (!is.null(ci_)) {
    add("#### `checking CRAN incoming feasibility`", "",
      mdtable(data.frame(
        Field = c("Maintainer", "CRAN status", "Tarball size",
                  "URLs flagged as invalid"),
        Value = c(code(ci_$maintainer %||% "?"),
                  if (isTRUE(ci_$is_new_submission))
                    "**New submission** — R's own confirmation that nothing named `edaphos` exists on CRAN"
                  else "not a new submission",
                  sprintf("%s (CRAN guidance: %s)", mb(ci_$tarball_bytes),
                          mb(5 * 1024^2)),
                  num(ci_$n_invalid_urls)),
        stringsAsFactors = FALSE)), "")
    if (length(nz(ci_$invalid_urls)))
      add(verbatim(ci_$invalid_urls), "")
  }
  if (length(nz(ck$test_summary)))
    add(sprintf("Test summary as the check itself reported it: `%s`.",
                trimws(ck$test_summary[1])), "")
  if (length(nz(ck$suggests_unavailable)))
    add(sprintf("Suggests unavailable to the check (so their tests and vignette chunks were skipped): %s.",
                paste(nz(ck$suggests_unavailable), collapse = " ")), "")
  if (length(nz(ck$installed_size)))
    add("Installed size, verbatim from the log:", "",
        verbatim(ck$installed_size), "")
  add(sprintf("Log: `%s` (%s lines, sha256 `%s`). Verbatim tail:",
              ck$log_path %||% "?", num(ck$log_lines),
              substr(ck$log_sha256 %||% "?", 1, 16)), "",
      verbatim(ck$tail), "")
  if (!is.null(cls) && NROW(cls$items)) {
    it <- cls$items
    add("#### Each reported item: package defect or measuring environment?", "",
        "Item names and levels come from the log above; the classification and",
        sprintf("source attribution are editorial and live in [`%s`](%s).",
                "tools/status/check-classification.json",
                "tools/status/check-classification.json"), "",
        mdtable(data.frame(
          Item = code(it$check), Level = it$level,
          Class = ifelse(it$class == "defect", "**defect**", "environment"),
          `Blocks CRAN` = vapply(it$blocks_cran, function(b)
            if (isTRUE(b)) "yes" else "no", character(1)),
          Source = it$source,
          check.names = FALSE, row.names = NULL, stringsAsFactors = FALSE)), "")
    add(sprintf("Of %s reported items, **%s are package defects** and %s are artefacts of this measuring environment. %s block CRAN acceptance.",
                num(NROW(it)), num(sum(it$class == "defect")),
                num(sum(it$class == "environment")),
                num(sum(it$blocks_cran %in% TRUE))), "")
    add("Fixes, per item:", "",
        paste0("- ", code(it$check), " — ", it$fix), "")
    if ("note" %in% names(it))
      for (k in which(!is.na(it$note) & nzchar(it$note %||% "")))
        add(sprintf("> **%s**: %s", it$check[k], it$note[k]), "")
  }
} else {
  add(sprintf("_%s_", ck$status %||% "not measured"), "",
      sprintf("Measure it with: `%s`", ck$hint %||%
        "Rscript tools/status/facts.R --check-log=<log>"), "")
}

rp <- facts$rd_portability
add("### Rd portability (the source of the PDF-manual check items)", "",
    sprintf("`man/*.Rd` files containing characters outside latin1: **%s** of %s. Most are cosmetic — R's Rd-to-LaTeX pass maps dashes and ellipses. Distinct characters found:",
            num(rp$n_rd_files_with_non_latin1), num(facts$docs$rd_count)), "")
if (NROW(rp$non_latin1_chars))
  add(mdtable(data.frame(
        Character = rp$non_latin1_chars$char,
        Codepoint = code(rp$non_latin1_chars$codepoint),
        Occurrences = rp$non_latin1_chars$occurrences,
        `Breaks LaTeX` = vapply(rp$non_latin1_chars$char, function(ch)
          tick(!is.null(rp$latex_breaking_chars) &&
               ch %in% rp$latex_breaking_chars$char), character(1)),
        check.names = FALSE, row.names = NULL, stringsAsFactors = FALSE),
      c("---", "---", "--:", ":-:")), "")
if (NROW(rp$roxygen_sources_to_fix)) {
  add("`man/` is roxygen-generated, so the fix belongs in `R/`. Exact source lines:", "",
      mdtable(data.frame(
        Source = code(sprintf("%s:%d", rp$roxygen_sources_to_fix$file,
                              rp$roxygen_sources_to_fix$line)),
        Line = rp$roxygen_sources_to_fix$text,
        row.names = NULL, stringsAsFactors = FALSE)), "")
}

# ===========================================================================
# 6. Test suite
# ===========================================================================
ts <- facts$tests_static
add("## 6. Test suite", "",
  mdtable(data.frame(
    Measure = c("Test files", "`test_that` blocks", "`expect_*` calls",
                "`skip_if_not_installed` gates", "`skip_on_cran` gates",
                "`set.seed` calls"),
    Value = c(num(ts$test_file_count), num(ts$test_that_blocks),
              num(ts$expect_calls), num(ts$skip_if_not_installed),
              num(ts$skip_on_cran), num(ts$set_seed_calls)),
    stringsAsFactors = FALSE)), "")

if (has_test) {
  add("Live run in this environment:", "",
    mdtable(data.frame(
      Outcome = c("Passed", "Skipped", "Failed", "Errored", "Warnings",
                  "Wall clock (s)"),
      Count = c(num(tr$passed), num(tr$skipped), num(tr$failed),
                num(tr$errored), num(tr$warnings), num(tr$real_seconds, 1)),
      stringsAsFactors = FALSE)), "")
  if (length(nz(tr$failing_files)))
    add(sprintf("Files with failures or errors: %s.",
                inline(basename(tr$failing_files), 20)), "")
} else {
  add("_Test run skipped in this render._", "")
}

gc_ <- ts$gate_counts
if (NROW(gc_)) {
  gc_ <- gc_[gc_$gate_sites > 0, , drop = FALSE]
  gc_ <- gc_[order(-gc_$gate_sites), , drop = FALSE]
  gc_$installed <- vapply(gc_$dependency,
    function(p) tick(p %in% dep$suggests_installed), character(1))
  add("Conditional skipping by dependency (static gate count):", "",
      mdtable(setNames(gc_, c("Dependency", "Gate sites", "Installed here")),
              c("---", "--:", ":-:")), "")
}

add(sprintf("Result bundles in `inst/extdata/`: **%s**. Test files that read `inst/extdata`: %s.",
            num(facts$artefacts$n_result_bundles),
            inline(ts$tests_reading_extdata, 10)), "")
if (length(nz(ts$exports_never_in_tests)))
  add(sprintf("Exported functions never named in any test (**%d**): %s.",
              length(nz(ts$exports_never_in_tests)),
              inline(ts$exports_never_in_tests, 20)), "")

# ===========================================================================
# 7. Documentation
# ===========================================================================
df_ <- facts$docs
add("## 7. Documentation coverage", "",
  mdtable(data.frame(
    Measure = c("`man/*.Rd` files", "Rd with `\\examples`",
                "— wrapping `\\dontrun`", "— wrapping `\\donttest`",
                "— with an example `R CMD check` runs",
                "Exports with no example anywhere", "Exports with no `.Rd`",
                "Rd with `\\references`", "Vignettes", "Root `articles/`",
                "Cheatsheets", "README size"),
    Value = c(num(df_$rd_count), num(df_$rd_with_examples),
              num(df_$rd_examples_dontrun), num(df_$rd_examples_donttest),
              num(df_$rd_examples_runnable),
              num(df_$n_exports_without_examples),
              num(length(nz(df_$exports_without_rd))),
              num(df_$rd_with_references), num(df_$vignette_count),
              num(df_$article_count), num(df_$cheatsheet_count),
              mb(df_$readme_bytes)),
    stringsAsFactors = FALSE)), "")

pw <- df_$pillar_wording
if (NROW(pw))
  add("\"six pillars\" vs \"ten pillars\", counted per file:", "",
      mdtable(setNames(pw, c("File", "says \"six\"", "says \"ten\"")),
              c("---", "--:", "--:")), "")

add(sprintf("Occurrences of `getting-started` in README.md: **%s**.",
            num(df_$readme_mentions_getting_started)), "")

ph <- facts$phantoms
if (length(nz(ph$phantom_names)))
  add(sprintf("Function names called in %s that are **defined nowhere** in `R/` (**%d** of %s referenced): %s.",
              inline(basename(ph$files_scanned), 12), ph$n_phantom,
              num(ph$names_called), inline(ph$phantom_names, 20)), "")

# ===========================================================================
# 8. Install size
# ===========================================================================
sz <- facts$size
add("## 8. Install size", "")
if (NROW(sz$by_dir)) {
  bd <- sz$by_dir
  bd <- bd[!is.na(bd$bytes) & bd$bytes > 0, , drop = FALSE]
  bd <- bd[order(-bd$bytes), , drop = FALSE]
  add(mdtable(data.frame(Directory = code(bd$dir), Size = mb(bd$bytes),
                         `Ships in tarball` = vapply(bd$ships_in_tarball, tick,
                                                     character(1)),
                         check.names = FALSE, stringsAsFactors = FALSE),
              c("---", "--:", ":-:")), "")
}
add(sprintf("Total shipped: **%s** against the CRAN 5 MB soft cap (%s) — %s.",
            mb(sz$shipped_bytes), mb(sz$cran_soft_cap_bytes),
            if (!is.na(sz$shipped_bytes) &&
                sz$shipped_bytes > sz$cran_soft_cap_bytes)
              "**over, so an installed-size NOTE is unavoidable**" else "under"),
    "")
if (NROW(sz$largest_shipped_files))
  add("Largest shipped files:", "",
      mdtable(data.frame(File = code(sz$largest_shipped_files$file),
                         Size = mb(sz$largest_shipped_files$bytes),
                         stringsAsFactors = FALSE), c("---", "--:")), "")

# ===========================================================================
# 9. CI
# ===========================================================================
ci <- facts$ci
add("## 9. CI and infrastructure", "",
    sprintf("Workflows (%s): %s.", num(ci$workflow_count),
            inline(ci$workflows, 12)), "")
if (length(nz(ci$matrix_legs)))
  add("`R-CMD-check` matrix legs:", "", paste0("- ", code(nz(ci$matrix_legs))), "")
if (length(nz(ci$torch_install_setting)))
  add(sprintf("`TORCH_INSTALL` setting found in the workflows: %s — with `0`, libtorch is never installed, so every torch-gated test skips on every leg.",
              inline(ci$torch_install_setting, 6)), "")
add(mdtable(data.frame(
      Check = c("Dependabot config", "`inst/WORDLIST` has a consumer",
                "Absent workflows a project at this stage wants"),
      Result = c(yn(ci$dependabot), yn(ci$wordlist_has_consumer),
                 inline(ci$missing_workflows, 12)),
      stringsAsFactors = FALSE)), "")

# ===========================================================================
# 10. Shipped artefacts vs published claims
# ===========================================================================
af <- facts$artefacts
add("## 10. Shipped artefacts vs published claims", "",
    "Loaded from `inst/extdata/` at render time. These are the values the package",
    "actually ships, independent of what the README says about them.", "")

iv <- af$causal_iv
if (!is.null(iv) && is.null(iv$error)) {
  es <- iv$embedding_sample
  add("### `causal_iv_cerrado_real.rds`", "",
      mdtable(data.frame(
        Field = c("Bundle version", "Computed", "Used real stack",
                  "Stack layers", "Resolution (deg)", "Profiles"),
        Value = c(code(iv$bundle_version %||% "?"),
                  substr(iv$date_computed %||% "?", 1, 19),
                  yn(iv$used_real_stack), num(iv$stack_nlyr),
                  as.character(iv$stack_res_deg %||% "?"),
                  num(iv$n_profiles)),
        stringsAsFactors = FALSE)), "")
  if (!is.null(es$length))
    add("Health of the stored embedding sample (measured, not characterised):", "",
        mdtable(data.frame(
          Statistic = c("Values stored", "Exactly zero", "Share exactly zero",
                        "Min", "Max", "SD"),
          Value = c(num(es$length), num(es$n_exact_zero),
                    sprintf("%.0f%%", 100 * (es$frac_exact_zero %||% NA_real_)),
                    sig(es$min), sig(es$max), sig(es$sd)),
          stringsAsFactors = FALSE), c("---", "--:")), "",
        paste("A healthy standardised embedding contains no exact zeros. A",
              "large share of exact zeros indicates channels that were never",
              "populated, or normalisation statistics left at their placeholder",
              "values."), "")
  est <- iv$estimates
  if (NROW(est))
    add("Estimates as shipped, all rows:", "",
        mdtable(data.frame(
          Exposure  = est$exposure,
          Estimator = est$estimator,
          beta      = sig(est$beta, 4),
          `Stage-1 F` = sig(est$stage1_F, 4),
          `Sargan p`  = sig(est$sargan_p, 3),
          check.names = FALSE, stringsAsFactors = FALSE),
          c("---", "---", "--:", "--:", "--:")), "")
  if (length(nz(iv$readme_claimed_sargan)))
    add("What `README.md` publishes at the same place, verbatim:", "",
        verbatim(iv$readme_claimed_sargan), "")
}

lb <- af$llm_benchmark
if (!is.null(lb) && is.null(lb$error))
  add("### `llm_benchmark_results.rds`", "",
      sprintf("`mode = \"%s\"`, bundle version `%s`, computed %s. %s",
              lb$mode %||% "?", lb$bundle_version %||% "?",
              substr(lb$date_computed %||% "?", 1, 19),
              if (isTRUE(lb$is_simulated))
                "**No API was called; the published vendor comparison reports its own simulator inputs.**"
              else ""), "")

qf <- af$quantum_foundation
if (!is.null(qf) && is.null(qf$error) && NROW(qf$cv_summary))
  add("### `quantum_foundation_cerrado.rds`", "",
      mdtable(local({
        z <- qf$cv_summary
        num_cols <- vapply(z, is.numeric, logical(1))
        z[num_cols] <- lapply(z[num_cols], function(v) sig(v, 4))
        z
      })), "",
      sprintf("Methods reporting R² of exactly zero: **%s** — a consequence of the clamp sites below.",
              num(qf$methods_with_r2_exactly_zero)), "")

if (length(nz(af$r2_clamp_sites)))
  add(sprintf("R² clamped with `max(0, 1 - ...)` at: %s.",
              inline(af$r2_clamp_sites, 10)), "")
if (length(nz(af$synthetic_covariate_sites)))
  add(sprintf("Benchmark covariate rasters filled with `rnorm()` at: %s.",
              inline(af$synthetic_covariate_sites, 10)), "")

# ===========================================================================
# 11. Findings register
# ===========================================================================
add("## 11. Findings register", "",
    sprintf("%d findings from the audit of `%s`, each passed through an adversarial verification lens.",
            reg$counts$total, substr(reg$provenance$audited_commit, 1, 7)),
    "Severity below is the **verified** severity, which may differ from what the",
    "original auditor reported.", "")

vc <- reg$counts$verdicts
add(mdtable(data.frame(Verdict = names(unlist(vc)),
                       Count = as.integer(unlist(vc)),
                       stringsAsFactors = FALSE), c("---", "--:")), "")
add(mdtable(as.data.frame(table(Severity = F$sev), stringsAsFactors = FALSE),
            c("---", "--:")), "")

refuted <- F[F$verdict == "REFUTED", , drop = FALSE]
if (NROW(refuted)) {
  add("### Refuted by verification (retained for the record, excluded from the plan)", "")
  for (i in seq_len(NROW(refuted)))
    add(sprintf("- **%s** — %s", refuted$id[i], refuted$title[i]),
        sprintf("  - Why it does not hold: %s", refuted$correction[i]), "")
}

open <- F[F$verdict != "REFUTED" & F$sev != "non-issue", , drop = FALSE]
open <- open[order(open$sev, open$area, open$id), , drop = FALSE]

add("### All open findings", "",
    mdtable(data.frame(
      ID = open$id, Sev = as.character(open$sev),
      Verdict = ifelse(open$verdict == "CONFIRMED", "confirmed", "partial"),
      Area = unname(AREA[open$area]), Kind = open$kind, Effort = open$effort,
      Finding = open$title, stringsAsFactors = FALSE)), "")

add("### Detail — blocker and high severity", "")
det <- open[open$sev %in% c("blocker", "high"), , drop = FALSE]
for (i in seq_len(NROW(det))) {
  r <- det[i, ]
  add(sprintf("#### %s — %s", r$id, r$title), "",
      sprintf("`%s` · %s · %s · effort: %s · verdict: **%s**",
              unname(AREA[r$area]), r$kind, r$sev, r$effort, r$verdict), "",
      "**Evidence**", "", paste0("> ", strsplit(r$evidence, "\n")[[1]]), "",
      "**Impact**", "", paste0("> ", strsplit(r$impact, "\n")[[1]]), "")
  if (!is.na(r$correction) && nzchar(r$correction))
    add("**Verification correction**", "", paste0("> ",
        strsplit(r$correction, "\n")[[1]]), "")
  add("**Action**", "", paste0("> ", strsplit(r$action, "\n")[[1]]), "")
}

add("### Detail — medium severity (action lines only)", "")
med <- open[open$sev == "medium", , drop = FALSE]
for (i in seq_len(NROW(med)))
  add(sprintf("- **%s** (%s, %s) — %s", med$id[i], unname(AREA[med$area[i]]),
              med$effort[i], med$title[i]),
      sprintf("  - %s", gsub("\n", " ", med$action[i])), "")

low <- open[open$sev == "low", , drop = FALSE]
if (NROW(low))
  add("### Low severity", "",
      mdtable(data.frame(ID = low$id, Area = unname(AREA[low$area]),
                         Effort = low$effort, Finding = low$title,
                         stringsAsFactors = FALSE)), "")

# ===========================================================================
# 12. Areas the eight dimension audits could not see
# ===========================================================================
ma <- reg$critique$missed_areas
if (NROW(ma)) {
  add("## 12. Gaps found by the completeness critic", "")
  ma <- ma[order(factor(ma$severity, levels = SEV_ORDER)), , drop = FALSE]
  for (i in seq_len(NROW(ma)))
    add(sprintf("### %s (%s, %s)", ma$title[i], ma$severity[i], ma$effort[i]), "",
        "**Evidence**", "", paste0("> ", strsplit(ma$evidence[i], "\n")[[1]]), "",
        "**Action**", "", paste0("> ", strsplit(ma$recommended_action[i], "\n")[[1]]), "")
}

# ===========================================================================
# 13. Work order
# ===========================================================================
add("## 13. Work order", "",
    "Grouping of the open findings into phases. The grouping is the only",
    "editorial content in this file; it lives in `PHASES` in",
    "[`tools/status/render.R`](tools/status/render.R). Each entry links back to a",
    "finding ID above, so nothing here is a new claim.", "")
claimed <- character()
for (p in PHASES) {
  ids <- setdiff(p$pick(open), claimed)
  claimed <- c(claimed, ids)
  sub <- open[match(ids, open$id), , drop = FALSE]
  sub <- sub[order(sub$sev, sub$effort), , drop = FALSE]
  add(sprintf("### Phase %s — %s", p$id, p$name), "",
      sprintf("_%s_", p$why), "",
      if (!NROW(sub)) "_no open findings in this phase_" else
        mdtable(data.frame(Done = "[ ]", ID = sub$id,
                           Sev = as.character(sub$sev), Effort = sub$effort,
                           Item = sub$title, stringsAsFactors = FALSE)),
      "")
}
rest <- open[!open$id %in% claimed, , drop = FALSE]
if (NROW(rest))
  add("### Unphased", "",
      mdtable(data.frame(Done = "[ ]", ID = rest$id,
                         Sev = as.character(rest$sev), Area = unname(AREA[rest$area]),
                         Item = rest$title, stringsAsFactors = FALSE)), "")

# ===========================================================================
# 14. Regenerating
# ===========================================================================
add("## 14. Regenerating this document", "",
    "```sh",
    "# 1. real check log (needed for section 5)",
    "R CMD build . && R CMD check --as-cran edaphos_*.tar.gz 2>&1 | tee /tmp/check.log",
    "",
    "# 2. measure, then render",
    "Rscript tools/status/facts.R --check-log=/tmp/check.log",
    "Rscript tools/status/render.R",
    "```", "",
    "`tools/status/facts.json` is the measurement snapshot and is regenerated in",
    "full each run. `tools/status/findings.json` is frozen audit input: edit it only",
    "to record a finding as resolved, never to change a measured number.", "")

con <- file(file.path(root, "STATUS.md"), open = "w", encoding = "UTF-8")
writeLines(out, con, useBytes = FALSE)
close(con)
cat("wrote STATUS.md —", length(out), "lines,",
    NROW(open), "open findings,", NROW(refuted), "refuted\n")
