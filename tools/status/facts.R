#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# tools/status/facts.R -- measure the repository, emit tools/status/facts.json
#
# Every number in STATUS.md comes from this script.  Nothing here is typed by
# hand: each field is read from git, the filesystem, the package metadata, a
# live test run, or a real `R CMD check` log.  A measurement that cannot be
# taken records an explicit error string rather than a plausible-looking value.
#
#   Rscript tools/status/facts.R                      # measure, run the tests
#   Rscript tools/status/facts.R --no-test            # skip the test run
#   Rscript tools/status/facts.R --check-log=path.log # also parse a check log
#
# Then render the document:  Rscript tools/status/render.R
# ---------------------------------------------------------------------------

args     <- commandArgs(trailingOnly = TRUE)
run_test <- !("--no-test" %in% args)
check_log_path <- sub("^--check-log=", "",
                      grep("^--check-log=", args, value = TRUE)[1])

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=",
          commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
setwd(root)

# -- helpers ----------------------------------------------------------------

sh <- function(cmd) {
  out <- suppressWarnings(system(cmd, intern = TRUE, ignore.stderr = TRUE))
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0L) return(character())
  out
}
sh1  <- function(cmd) { o <- sh(cmd); if (length(o)) trimws(o[1]) else NA_character_ }
shn  <- function(cmd) { o <- sh1(cmd); if (is.na(o)) NA_integer_ else as.integer(o) }
safe <- function(expr) tryCatch(expr, error = function(e)
          list(error = conditionMessage(e)))

# count regex hits across a set of files
grep_count <- function(pattern, files, perl = TRUE) {
  if (!length(files)) return(0L)
  sum(vapply(files, function(f)
    sum(grepl(pattern, readLines(f, warn = FALSE), perl = perl)),
    integer(1)))
}
r_files    <- sort(Sys.glob("R/*.R"))
test_files <- sort(Sys.glob("tests/testthat/test-*.R"))
rd_files   <- sort(Sys.glob("man/*.Rd"))
src_files  <- sort(c(Sys.glob("src/*.cpp"), Sys.glob("src/*.h")))

# ---------------------------------------------------------------------------
# 1. Provenance of this measurement
# ---------------------------------------------------------------------------
environment_facts <- safe(list(
  measured_at_utc = format(as.POSIXct(Sys.time(), tz = "UTC"),
                           "%Y-%m-%dT%H:%M:%SZ"),
  r_version       = paste(R.version$major, R.version$minor, sep = "."),
  r_nickname      = R.version$nickname,
  platform        = R.version$platform,
  os              = Sys.info()[["sysname"]],
  os_release      = Sys.info()[["release"]]
))

# ---------------------------------------------------------------------------
# 2. Git: the clock, the tags, the remote
# ---------------------------------------------------------------------------
git_facts <- safe({
  per_day <- sh("git log --format=%cd --date=short")
  tab     <- if (length(per_day)) table(per_day) else integer()
  tags    <- sh("git tag -l --sort=v:refname")
  first   <- sh1("git log --reverse --format=%cI | head -1")
  last    <- sh1("git log -1 --format=%cI")
  span    <- if (!is.na(first) && !is.na(last))
    as.numeric(difftime(as.POSIXct(last,  format = "%Y-%m-%dT%H:%M:%S"),
                        as.POSIXct(first, format = "%Y-%m-%dT%H:%M:%S"),
                        units = "days")) else NA_real_
  ab <- sh1("git rev-list --left-right --count main...origin/main")
  list(
    head_sha        = sh1("git rev-parse HEAD"),
    head_sha_short  = sh1("git rev-parse --short HEAD"),
    branch          = sh1("git rev-parse --abbrev-ref HEAD"),
    remote_url      = sh1("git remote get-url origin"),
    commit_count    = shn("git rev-list --count HEAD"),
    first_commit    = first,
    first_subject   = sh1("git log --reverse --format=%s | head -1"),
    last_commit     = last,
    last_subject    = sh1("git log -1 --format=%s"),
    span_days       = span,
    active_days     = length(tab),
    commits_per_day = as.list(tab),
    days_since_last = if (!is.na(last)) as.numeric(difftime(Sys.time(),
                        as.POSIXct(last, format = "%Y-%m-%dT%H:%M:%S"),
                        units = "days")) else NA_real_,
    tags            = tags,
    tag_count       = length(tags),
    worktree_clean  = length(sh("git status --porcelain")) == 0L,
    ahead_behind_origin_main = ab,
    remote_tag_count = length(unique(sub("\\^\\{\\}$", "",
                          sub(".*refs/tags/", "", sh("git ls-remote --tags origin"))))),
    commits_since_last_tag = if (length(tags))
      shn(sprintf("git rev-list --count %s..HEAD", tail(tags, 1))) else NA_integer_,
    last_tag        = if (length(tags)) tail(tags, 1) else NA_character_
  )
})

# ---------------------------------------------------------------------------
# 3. Package metadata
# ---------------------------------------------------------------------------
desc_facts <- safe({
  d <- read.dcf("DESCRIPTION")[1, ]
  split_dep <- function(field) {
    if (!field %in% names(d) || is.na(d[[field]])) return(character())
    x <- strsplit(d[[field]], ",")[[1]]
    trimws(gsub("\\s*\\(.*\\)", "", x))
  }
  list(
    version   = unname(d[["Version"]]),
    depends   = split_dep("Depends"),
    imports   = split_dep("Imports"),
    suggests  = split_dep("Suggests"),
    n_imports = length(split_dep("Imports")),
    n_suggests= length(split_dep("Suggests")),
    linkingto = split_dep("LinkingTo"),
    license   = unname(d[["License"]]),
    language  = unname(d[["Language"]]),
    title     = unname(d[["Title"]]),
    lazydata  = if ("LazyData" %in% names(d)) unname(d[["LazyData"]]) else NA_character_
  )
})

news_facts <- safe({
  ln  <- readLines("NEWS.md", warn = FALSE)
  hdr <- grep("^# edaphos ", ln, value = TRUE)
  vs  <- sub("^# edaphos ", "", hdr)
  # a heading may carry a suffix, e.g. "1.2.0 (in development)"
  norm <- sub("\\s.*$", "", vs)
  list(
    section_count  = length(hdr),
    newest_version = if (length(norm)) norm[1] else NA_character_,
    oldest_version = if (length(norm)) tail(norm, 1) else NA_character_,
    versions       = norm,
    headings       = vs
  )
})

# Which NEWS versions have no git tag?
version_facts <- safe({
  tags <- sub("^v", "", git_facts$tags)
  vs   <- news_facts$versions
  list(
    news_versions_without_tag = setdiff(vs, tags),
    n_news_without_tag        = length(setdiff(vs, tags)),
    tags_without_news         = setdiff(tags, vs),
    description_version       = desc_facts$version,
    newest_news_version       = news_facts$newest_version,
    description_matches_news  = identical(desc_facts$version,
                                          news_facts$newest_version),
    description_has_tag       = paste0("v", desc_facts$version) %in% git_facts$tags,
    # every distinct "version-like" string other files claim for the package
    claims = list(
      DESCRIPTION = desc_facts$version,
      NEWS.md     = news_facts$newest_version,
      README.md   = unique(regmatches(
                      grep("Version [0-9]", readLines("README.md", warn = FALSE),
                           value = TRUE),
                      regexpr("[0-9]+\\.[0-9]+\\.[0-9]+",
                        grep("Version [0-9]", readLines("README.md", warn = FALSE),
                             value = TRUE)))),
      CITATION.cff = if (file.exists("CITATION.cff"))
        unique(trimws(gsub('"', "", sub("^\\s*version:\\s*", "",
          grep("^\\s*version:", readLines("CITATION.cff", warn = FALSE),
               value = TRUE))))) else NA_character_,
      zenodo.json_has_version = if (file.exists(".zenodo.json"))
        any(grepl('"version"', readLines(".zenodo.json", warn = FALSE))) else NA
    ),
    # git refs the README tells users to install
    readme_install_refs = local({
      ln <- grep("install_github", readLines("README.md", warn = FALSE), value = TRUE)
      refs <- unique(regmatches(ln, regexpr("@v?[0-9][0-9.]*", ln)))
      data.frame(
        ref      = sub("^@", "", refs),
        resolves = vapply(sub("^@", "", refs),
                     function(r) length(sh(sprintf("git rev-parse -q --verify %s", r))) > 0L,
                     logical(1)),
        row.names = NULL, stringsAsFactors = FALSE)
    })
  )
})

# ---------------------------------------------------------------------------
# 4. Code size and API surface
# ---------------------------------------------------------------------------
code_facts <- safe({
  loc <- function(fs) if (length(fs))
    sum(vapply(fs, function(f) length(readLines(f, warn = FALSE)), integer(1))) else 0L
  ns  <- readLines("NAMESPACE", warn = FALSE)
  exports <- sub("^export\\((.*)\\)$", "\\1", grep("^export\\(", ns, value = TRUE))
  list(
    r_file_count   = length(r_files),
    r_loc          = loc(r_files),
    src_file_count = length(src_files),
    src_loc        = loc(src_files),
    largest_r_files = local({
      n <- vapply(r_files, function(f) length(readLines(f, warn = FALSE)), integer(1))
      o <- order(n, decreasing = TRUE)[seq_len(min(10, length(n)))]
      data.frame(file = basename(r_files)[o], lines = unname(n[o]),
                 row.names = NULL, stringsAsFactors = FALSE)
    }),
    n_exports      = length(exports),
    exports        = exports,
    n_s3_methods   = length(grep("^S3method\\(", ns)),
    # naming schism: ordinal- vs domain-named modules, pilar vs pillar
    ordinal_named_r_files = basename(grep("R/pilar[0-9]", r_files, value = TRUE)),
    files_saying_pillar   = basename(r_files)[vapply(r_files, function(f)
      any(grepl("pillar", readLines(f, warn = FALSE), ignore.case = FALSE)), logical(1))],
    raw_stop_calls    = grep_count("\\bstop\\(", r_files),
    raw_warning_calls = grep_count("\\bwarning\\(", r_files),
    stopf_calls       = grep_count("\\.stopf\\(", r_files),
    not_implemented   = local({
      hits <- unlist(lapply(r_files, function(f) {
        ln <- readLines(f, warn = FALSE)
        i  <- grep("not yet implemented|not implemented", ln)
        if (length(i)) sprintf("%s:%d", f, i) else character()
      }))
      hits
    }),
    undeclared_base_namespaces = local({
      # base-distribution namespaces used via :: but absent from Imports
      used <- unique(unlist(lapply(r_files, function(f)
        regmatches(readLines(f, warn = FALSE),
          gregexpr("\\b(utils|tools|methods|grDevices|graphics|parallel)(?=::)",
                   readLines(f, warn = FALSE), perl = TRUE)))))
      miss <- setdiff(used, desc_facts$imports)
      data.frame(
        namespace = miss,
        source_lines_using_it = vapply(miss, function(nsx)
          grep_count(paste0("\\b", nsx, "::"), r_files), integer(1)),
        row.names = NULL, stringsAsFactors = FALSE)
    })
  )
})

# ---------------------------------------------------------------------------
# 5. Documentation coverage
# ---------------------------------------------------------------------------
doc_facts <- safe({
  has <- function(f, pat) any(grepl(pat, readLines(f, warn = FALSE), fixed = TRUE))
  with_ex   <- rd_files[vapply(rd_files, has, logical(1), "\\examples")]
  dontrun   <- with_ex[vapply(with_ex, has, logical(1), "\\dontrun")]
  donttest  <- with_ex[vapply(with_ex, has, logical(1), "\\donttest")]
  # aliases documented anywhere in man/
  aliases <- unique(unlist(lapply(rd_files, function(f)
    sub("^\\\\alias\\{(.*)\\}$", "\\1",
        grep("^\\\\alias\\{", readLines(f, warn = FALSE), value = TRUE)))))
  # which exports appear in an Rd that has \examples
  ex_aliases <- unique(unlist(lapply(with_ex, function(f)
    sub("^\\\\alias\\{(.*)\\}$", "\\1",
        grep("^\\\\alias\\{", readLines(f, warn = FALSE), value = TRUE)))))
  runnable <- setdiff(with_ex, union(dontrun, donttest))
  list(
    rd_count            = length(rd_files),
    rd_with_examples    = length(with_ex),
    rd_examples_dontrun = length(dontrun),
    rd_examples_donttest= length(donttest),
    rd_examples_runnable= length(runnable),
    exports_without_examples   = setdiff(code_facts$exports, ex_aliases),
    n_exports_without_examples = length(setdiff(code_facts$exports, ex_aliases)),
    exports_without_rd         = setdiff(code_facts$exports, aliases),
    rd_with_references         = sum(vapply(rd_files, has, logical(1), "\\references")),
    vignette_count             = length(Sys.glob("vignettes/*.Rmd")),
    vignettes                  = basename(Sys.glob("vignettes/*.Rmd")),
    article_count              = length(Sys.glob("articles/*.Rmd")),
    cheatsheet_count           = length(Sys.glob("cheatsheets/*.md")),
    # the six-vs-ten pillar schism, counted rather than asserted
    pillar_wording = data.frame(
      file = c("DESCRIPTION", "R/pillars_roadmap.R", "R/edaphos-package.R", "README.md"),
      says_six = vapply(c("DESCRIPTION", "R/pillars_roadmap.R",
                          "R/edaphos-package.R", "README.md"),
        function(f) if (file.exists(f))
          sum(grepl("six (research )?pillars", readLines(f, warn = FALSE),
                    ignore.case = TRUE)) else NA_integer_, integer(1)),
      says_ten = vapply(c("DESCRIPTION", "R/pillars_roadmap.R",
                          "R/edaphos-package.R", "README.md"),
        function(f) if (file.exists(f))
          sum(grepl("ten (research )?pillars", readLines(f, warn = FALSE),
                    ignore.case = TRUE)) else NA_integer_, integer(1)),
      row.names = NULL, stringsAsFactors = FALSE),
    readme_bytes = if (file.exists("README.md")) file.size("README.md") else NA_integer_,
    readme_mentions_getting_started = if (file.exists("README.md"))
      sum(grepl("getting-started", readLines("README.md", warn = FALSE),
                ignore.case = TRUE)) else NA_integer_
  )
})

# Rd portability: characters R CMD check's LaTeX pass cannot typeset, and
# version strings the code claims that no NEWS section declares.
rd_portability <- safe({
  # LaTeX (pdflatex, inputenc latin1) fails on non-latin1 code points.
  scan_files <- function(fs, pat) {
    do.call(rbind, lapply(fs, function(f) {
      ln <- readLines(f, warn = FALSE, encoding = "UTF-8")
      Encoding(ln) <- "UTF-8"
      i  <- grep(pat, ln, perl = TRUE)
      if (!length(i)) return(NULL)
      data.frame(file = f, line = i, text = trimws(ln[i]),
                 row.names = NULL, stringsAsFactors = FALSE)
    }))
  }
  # code points above latin1 (U+00FF) are the ones that break the PDF manual
  non_latin1 <- scan_files(rd_files, "[^\\x00-\\xFF]")
  chars <- if (NROW(non_latin1)) {
    cp <- unlist(strsplit(paste(non_latin1$text, collapse = ""), ""))
    cp <- cp[utf8ToInt2 <- vapply(cp, function(ch)
      utf8ToInt(ch) > 255L, logical(1))]
    tb <- sort(table(cp), decreasing = TRUE)
    ch <- names(tb); Encoding(ch) <- "UTF-8"
    data.frame(char = ch,
               codepoint = sprintf("U+%04X", vapply(ch, utf8ToInt, integer(1))),
               occurrences = as.integer(tb),
               row.names = NULL, stringsAsFactors = FALSE)
  } else NULL
  # Characters R's Rd -> LaTeX conversion already maps safely; their presence
  # is cosmetic and does not break the PDF manual.
  mapped_ok <- c("\u2014", "\u2013", "\u2026", "\u00d7")
  breaks <- if (!is.null(chars)) chars[!chars$char %in% mapped_ok, ] else NULL
  list(
    rd_files_with_non_latin1 = if (NROW(non_latin1))
      unique(non_latin1$file) else character(),
    n_rd_files_with_non_latin1 = if (NROW(non_latin1))
      length(unique(non_latin1$file)) else 0L,
    non_latin1_chars = chars,
    latex_breaking_chars = breaks,
    latex_breaking_sites = if (NROW(breaks)) local({
      pat <- paste0("[", paste(breaks$char, collapse = ""), "]")
      scan_files(rd_files, pat)
    }) else NULL,
    escaped_latex_specials = scan_files(rd_files, "\\\\[~^]"),
    # man/*.Rd are roxygen-generated, so a fix must land in R/ and be
    # re-documented.  Report the roxygen source lines for the breaking chars
    # and the escaped specials only -- not the 165 cosmetic em-dashes.
    roxygen_sources_to_fix = local({
      pats <- character()
      if (NROW(breaks)) pats <- paste0("[", paste(breaks$char, collapse = ""), "]")
      pats <- c(pats, "\\\\[~^]")
      do.call(rbind, lapply(pats, function(p) scan_files(r_files, p)))
    })
  )
})

version_drift <- safe({
  declared <- news_facts$versions   # already normalised
  # version-like strings asserted inside shipped code / docs
  sites <- do.call(rbind, lapply(c(r_files, rd_files), function(f) {
    ln <- readLines(f, warn = FALSE)
    m  <- gregexpr("(?<![0-9.])[0-9]+\\.[0-9]+\\.[0-9]+(?![0-9.])", ln, perl = TRUE)
    v  <- regmatches(ln, m)
    i  <- which(lengths(v) > 0L)
    if (!length(i)) return(NULL)
    data.frame(file = f, line = i,
               version = vapply(v[i], function(x) paste(unique(x), collapse = ","),
                                character(1)),
               row.names = NULL, stringsAsFactors = FALSE)
  }))
  undeclared <- if (NROW(sites)) {
    vs <- unique(unlist(strsplit(sites$version, ",")))
    setdiff(vs, declared)
  } else character()
  # A version string is a PHANTOM when neither a NEWS section nor a git tag
  # declares it -- i.e. the shipped code names a release that never existed.
  tagged  <- sub("^v", "", git_facts$tags)
  phantom <- setdiff(undeclared, tagged)
  list(
    versions_asserted_in_code = if (NROW(sites)) sites else NULL,
    versions_not_declared_in_news = undeclared,
    phantom_versions = phantom,
    n_phantom_versions = length(phantom),
    sites_claiming_phantom_version = if (NROW(sites) && length(phantom))
      sites[vapply(strsplit(sites$version, ","),
                   function(x) any(x %in% phantom), logical(1)), ]
      else NULL
  )
})

# cheatsheet / README function names that do not exist in the package
phantom_facts <- safe({
  md <- c(Sys.glob("cheatsheets/*.md"), "INTRO.md")
  md <- md[file.exists(md)]
  called <- unique(unlist(lapply(md, function(f) {
    ln <- readLines(f, warn = FALSE)
    m  <- regmatches(ln, gregexpr(
      "\\b(foundation|temporal|causal|piml|quantum|al|bhs|no|dm|gnn|uncertainty|edaphos)_[a-z0-9_]+(?=\\()",
      ln, perl = TRUE))
    unlist(m)
  })))
  defined <- unique(unlist(lapply(r_files, function(f)
    sub("^\\s*([.A-Za-z][A-Za-z0-9._]*)\\s*<-\\s*function.*$", "\\1",
        grep("^\\s*[.A-Za-z][A-Za-z0-9._]*\\s*<-\\s*function",
             readLines(f, warn = FALSE), value = TRUE)))))
  phantom <- setdiff(called, union(defined, code_facts$exports))
  list(
    files_scanned  = md,
    names_called   = length(called),
    phantom_names  = sort(phantom),
    n_phantom      = length(phantom)
  )
})

# ---------------------------------------------------------------------------
# 6. Test suite: static shape + live run
# ---------------------------------------------------------------------------
test_static <- safe({
  gates <- c("torch", "dagitty", "bnlearn", "dbarts", "spBayes", "reticulate",
             "terra", "geodata", "Matrix", "shiny", "igraph")
  list(
    test_file_count = length(test_files),
    test_that_blocks= grep_count("\\btest_that\\(", test_files),
    expect_calls    = grep_count("\\bexpect_[a-z_]+\\(", test_files),
    skip_if_not_installed = grep_count("skip_if_not_installed\\(", test_files),
    skip_on_cran    = grep_count("skip_on_cran\\(", test_files),
    set_seed_calls  = grep_count("set\\.seed\\(", test_files),
    gate_counts     = local({
      data.frame(
        dependency = gates,
        gate_sites = vapply(gates, function(g)
          grep_count(sprintf("skip_if_not_installed\\(\\s*[\"']%s[\"']", g),
                     test_files), integer(1)),
        row.names = NULL, stringsAsFactors = FALSE)
    }),
    tests_reading_extdata = basename(test_files[vapply(test_files, function(f)
      any(grepl("extdata", readLines(f, warn = FALSE))), logical(1))]),
    result_bundles = basename(Sys.glob("inst/extdata/*.rds")),
    exports_never_in_tests = local({
      body <- unlist(lapply(test_files, readLines, warn = FALSE))
      code_facts$exports[!vapply(code_facts$exports, function(e)
        any(grepl(paste0("\\b", e, "\\b"), body)), logical(1))]
    })
  )
})

test_run <- if (!run_test) list(skipped = "--no-test") else safe({
  stopifnot(requireNamespace("testthat", quietly = TRUE))
  stopifnot(requireNamespace("pkgload",  quietly = TRUE))
  pkgload::load_all(root, quiet = TRUE)
  rep <- testthat::test_local(root, reporter = "silent", stop_on_failure = FALSE)
  df  <- as.data.frame(rep)
  list(
    passed   = sum(df$passed),
    failed   = sum(df$failed),
    errored  = sum(df$error),
    skipped  = sum(df$skipped),
    warnings = sum(df$warning),
    files    = length(unique(df$file)),
    results  = nrow(df),
    real_seconds = round(sum(df$real, na.rm = TRUE), 1),
    failing_files = df$file[df$failed > 0 | df$error > 0]
  )
})

# installed / missing optional dependencies -- the reason skips happen
dep_facts <- safe({
  ip <- rownames(installed.packages())
  sg <- desc_facts$suggests
  list(
    suggests_installed = sort(intersect(sg, ip)),
    suggests_missing   = sort(setdiff(sg, ip)),
    n_missing          = length(setdiff(sg, ip))
  )
})

# ---------------------------------------------------------------------------
# 7. R CMD check --as-cran (parsed from a real log, never asserted)
# ---------------------------------------------------------------------------
if (is.na(check_log_path)) {
  # most recent check first, falling back to the frozen pre-remediation baseline
  default_log <- file.path(root, "tools", "status", "check.log")
  if (!file.exists(default_log))
    default_log <- file.path(root, "tools", "status", "baseline-check-272b378.log")
  if (file.exists(default_log)) check_log_path <- default_log
}
check_facts <- if (is.na(check_log_path) || !file.exists(check_log_path)) {
  list(status = "not measured in this run",
       hint   = "Rscript tools/status/facts.R --check-log=<path to R CMD check log>")
} else safe({
  ln <- readLines(check_log_path, warn = FALSE, encoding = "UTF-8")
  Encoding(ln) <- "UTF-8"
  # R quotes file names and identifiers with U+2018/U+2019; strip them so the
  # rendered document carries the value, not the typography.
  # NOTE: must not trim -- leading whitespace is how the log marks continuation
  # lines, and the parsers below anchor on it.
  unquote <- function(x) gsub("[\u2018\u2019\u201c\u201d]", "", x)
  ln <- unquote(ln)

  # R CMD check prints the outcome either on the "* checking ..." line itself
  # or, when the step was timed, on a continuation line such as " [46s/33s] ERROR".
  # Walk the log so both forms are captured.
  starts <- grep("^\\* checking|^\\* using|^\\* this is", ln)
  step_i <- grep("^\\* checking", ln)
  items  <- do.call(rbind, lapply(seq_along(step_i), function(k) {
    i <- step_i[k]
    j <- if (k < length(step_i)) step_i[k + 1L] - 1L else length(ln)
    block <- ln[i:j]
    lvl <- regmatches(block,
             regexpr("\\b(ERROR|WARNING|NOTE|INFO|OK|SKIPPED)\\s*$", block))
    lvl <- trimws(unlist(lvl))
    name <- trimws(sub("\\.\\.\\..*$", "", ln[i]))
    name <- trimws(sub("^\\* ", "", name))
    if (!length(lvl)) return(NULL)
    # detail = the block minus the header, minus the level-only continuation
    detail <- block[-1L]
    detail <- detail[nzchar(trimws(detail))]
    data.frame(step = name, level = lvl[1],
               detail = paste(utils::head(detail, 8), collapse = " | "),
               row.names = NULL, stringsAsFactors = FALSE)
  }))

  status_line <- grep("^Status:", ln, value = TRUE)
  # counts as R itself reports them, so the document never disagrees with the log
  from_status <- function(what) {
    if (!length(status_line)) return(NA_integer_)
    m <- regmatches(status_line[1],
           regexpr(sprintf("[0-9]+ %ss?", what), status_line[1]))
    if (!length(m)) 0L else as.integer(sub(" .*$", "", m))
  }
  parsed <- if (NROW(items)) table(items$level) else integer()
  getp <- function(k) if (k %in% names(parsed)) as.integer(parsed[[k]]) else 0L

  n_err <- from_status("ERROR"); n_warn <- from_status("WARNING")
  n_note <- from_status("NOTE")

  list(
    log_path   = check_log_path,
    log_lines  = length(ln),
    log_sha256 = if (requireNamespace("digest", quietly = TRUE))
      digest::digest(file = check_log_path, algo = "sha256") else NA_character_,
    status_line = status_line,
    n_errors = n_err, n_warnings = n_warn, n_notes = n_note,
    # reconciliation: if the walk disagrees with R's own Status line, say so
    parsed_counts = list(ERROR = getp("ERROR"), WARNING = getp("WARNING"),
                         NOTE = getp("NOTE"), INFO = getp("INFO"),
                         OK = getp("OK")),
    counts_reconcile = identical(c(n_err, n_warn, n_note),
                                 c(getp("ERROR"), getp("WARNING"), getp("NOTE"))),
    items       = items,
    errors      = if (NROW(items)) items$step[items$level == "ERROR"]   else character(),
    warnings    = if (NROW(items)) items$step[items$level == "WARNING"] else character(),
    notes       = if (NROW(items)) items$step[items$level == "NOTE"]    else character(),
    infos       = if (NROW(items)) items$step[items$level == "INFO"]    else character(),
    # the installed-size block, header plus its indented continuation lines
    installed_size = local({
      i <- grep("installed size is", ln)
      if (!length(i)) return(character())
      j <- i[1]
      out <- ln[j]
      k <- j + 1L
      while (k <= length(ln) && grepl("^\\s", ln[k])) { out <- c(out, ln[k]); k <- k + 1L }
      out
    }),
    # the CRAN incoming-feasibility NOTE is the most decision-relevant block
    cran_incoming = local({
      i <- grep("^\\* checking CRAN incoming feasibility", ln)
      if (!length(i)) return(NULL)
      j <- grep("^\\* checking", ln); j <- j[j > i[1]]
      block <- ln[i[1]:(if (length(j)) j[1] - 1L else length(ln))]
      urls <- grep("^\\s+URL: ", block, value = TRUE)
      list(
        is_new_submission = any(grepl("^New submission", block)),
        maintainer = trimws(sub(".*Maintainer:\\s*", "",
                       grep("Maintainer:", block, value = TRUE)[1])),
        invalid_urls = trimws(sub("^\\s+URL: ", "", urls)),
        n_invalid_urls = length(urls),
        tarball_bytes = local({
          m <- grep("Size of tarball:", block, value = TRUE)
          if (!length(m)) NA_real_ else
            as.numeric(gsub("[^0-9]", "", m[1]))
        }),
        block = block[!grepl("bioconductor|cannot open URL", block)]
      )
    }),
    test_summary = grep("\\[ FAIL", ln, value = TRUE),
    suggests_unavailable = local({
      i <- grep("Packages suggested but not available", ln)
      if (!length(i)) return(character())
      j <- i[1] + 1L; out <- character()
      while (j <= length(ln) && grepl("^\\s", ln[j])) { out <- c(out, trimws(ln[j])); j <- j + 1L }
      out
    }),
    tail = utils::tail(ln, 20)
  )
})

# ---------------------------------------------------------------------------
# 8. Install size
# ---------------------------------------------------------------------------
size_facts <- safe({
  # Measure GIT-TRACKED files only.  A working tree that has just been built
  # carries src/*.o and src/*.so, which are not part of the tarball; counting
  # them would inflate every figure here.
  tracked <- sh("git ls-files")
  tracked <- tracked[file.exists(tracked)]
  bytes   <- file.size(tracked)
  top     <- ifelse(grepl("/", tracked), sub("/.*$", "", tracked), "<root>")
  agg     <- tapply(bytes, top, sum)
  # a source tarball ships these top-level directories plus the root files
  # Apply .Rbuildignore rather than guessing from the top-level directory.
  # The previous heuristic counted every root file as shipping, so STATUS.md
  # (231 KB) and the other ignored top-level files inflated the figure that
  # this document uses to argue about the CRAN size limit.
  rb <- if (file.exists(".Rbuildignore"))
    grep("^\\s*(#|$)", readLines(".Rbuildignore", warn = FALSE),
         value = TRUE, invert = TRUE) else character()
  ignored <- function(paths) {
    if (!length(rb)) return(rep(FALSE, length(paths)))
    Reduce(`|`, lapply(rb, function(pat)
      grepl(pat, paths, perl = TRUE)), rep(FALSE, length(paths)))
  }
  shipped_dirs <- c("R", "src", "man", "data", "inst", "tests", "vignettes")
  ship_file <- (top %in% c(shipped_dirs, "<root>")) & !ignored(tracked)
  agg_ship  <- tapply(bytes[ship_file], top[ship_file], sum)
  is_ship <- names(agg) %in% names(agg_ship)
  big <- local({
    # Rank among files that actually ship.  Ranking over all tracked files
    # and flagging the rest put findings.json (442 KB) and STATUS.md (226 KB)
    # -- both .Rbuildignore'd -- at the top of a table headed "shipped".
    i <- which(ship_file)
    o <- i[order(bytes[i], decreasing = TRUE)][seq_len(min(12, length(i)))]
    data.frame(file = tracked[o], bytes = unname(bytes[o]),
               ships = TRUE, row.names = NULL, stringsAsFactors = FALSE)
  })
  list(
    measured_over = "git-tracked files only (build artefacts excluded)",
    tracked_file_count = length(tracked),
    by_dir = data.frame(dir = names(agg), bytes = unname(as.numeric(agg)),
                        ships_in_tarball = is_ship,
                        row.names = NULL, stringsAsFactors = FALSE)[
                          order(-as.numeric(agg)), ],
    shipped_bytes = sum(bytes[ship_file], na.rm = TRUE),
    shipped_file_count = sum(ship_file),
    # The size CRAN actually applies its 5 MB guidance to is the built
    # tarball, which is larger than the git-tracked sources because
    # `R CMD build` adds inst/doc (the rendered vignettes).  Measure the
    # real artefact when one is present rather than scraping the check
    # log, which only prints "Size of tarball:" above a threshold.
    tarball_bytes = local({
      f <- list.files(".", pattern = "^edaphos_.*\\.tar\\.gz$",
                      full.names = TRUE)
      if (!length(f)) return(NA_real_)
      f <- f[order(file.mtime(f), decreasing = TRUE)][1L]
      as.numeric(file.size(f))
    }),
    tarball_file = local({
      f <- list.files(".", pattern = "^edaphos_.*\\.tar\\.gz$")
      if (!length(f)) NA_character_ else
        f[order(file.mtime(file.path(".", f)), decreasing = TRUE)][1L]
    }),
    # Where the tarball's bytes actually are.  The git-tracked figures above
    # cannot answer this, because the largest single contributor -- inst/doc --
    # does not exist in the repository: `R CMD build` renders the vignettes
    # into it.  Any argument about the 5 MB guidance that reasons from tracked
    # sources is therefore reasoning about the wrong artefact.  Measured by
    # unpacking the real tarball.
    tarball_composition = local({
      f <- list.files(".", pattern = "^edaphos_.*\\.tar\\.gz$", full.names = TRUE)
      if (!length(f)) return(NULL)
      f  <- f[order(file.mtime(f), decreasing = TRUE)][1L]
      ex <- file.path(tempdir(), "edaphos-tarball-composition")
      unlink(ex, recursive = TRUE)
      dir.create(ex, recursive = TRUE, showWarnings = FALSE)
      on.exit(unlink(ex, recursive = TRUE), add = TRUE)
      if (!identical(utils::untar(f, exdir = ex), 0L)) return(NULL)
      rt <- file.path(ex, "edaphos")
      if (!dir.exists(rt)) return(NULL)
      fs  <- list.files(rt, recursive = TRUE, all.files = TRUE,
                        full.names = TRUE, no.. = TRUE)
      fs  <- fs[!dir.exists(fs)]
      rel <- substring(fs, nchar(rt) + 2L)
      bs  <- file.size(fs)
      # group by the directory that owns the bytes: two levels under inst/ and
      # man/, one level elsewhere, root files together
      grp <- vapply(strsplit(rel, "/", fixed = TRUE), function(p)
        if (length(p) == 1L) "<root>" else
          paste(p[seq_len(min(2L, length(p) - 1L))], collapse = "/"),
        character(1))
      agg <- tapply(bs, grp, sum)
      agg <- agg[order(-as.numeric(agg))]
      # inst/doc is rendered HTML with its figures inlined as data: URIs.
      # base64 costs 4 bytes per 3, so this is the compressible part.
      html <- list.files(file.path(rt, "inst", "doc"), pattern = "\\.html$",
                         full.names = TRUE)
      b64 <- if (!length(html)) NULL else local({
        per <- vapply(html, function(p) {
          s <- readChar(p, file.size(p), useBytes = TRUE)
          m <- gregexpr("base64,[A-Za-z0-9+/=]+", s, useBytes = TRUE)[[1]]
          if (m[1L] == -1L) 0 else sum(attr(m, "match.length"))
        }, numeric(1))
        o <- order(-per)
        list(html_files = length(html),
             html_bytes = sum(file.size(html)),
             base64_bytes = sum(per),
             base64_share_of_html = sum(per) / max(sum(file.size(html)), 1),
             largest = data.frame(file = basename(html)[o],
                                  bytes = unname(file.size(html)[o]),
                                  base64_bytes = unname(per[o]),
                                  row.names = NULL, stringsAsFactors = FALSE)[
                                    seq_len(min(6L, length(html))), ])
      })
      list(total_bytes = sum(bs), file_count = length(fs),
           by_dir = data.frame(dir = names(agg),
                               bytes = unname(as.numeric(agg)),
                               in_repo = names(agg) != "inst/doc",
                               row.names = NULL, stringsAsFactors = FALSE),
           inst_doc = b64)
    }),
    excluded_by_rbuildignore = sum(!ship_file & top %in% c(shipped_dirs, "<root>")),
    repo_bytes    = sum(bytes, na.rm = TRUE),
    cran_soft_cap_bytes = 5 * 1024^2,
    largest_shipped_files = big,
    untracked_files = setdiff(sub("^\\?\\? ", "",
                        grep("^\\?\\? ", sh("git status --porcelain"), value = TRUE)),
                        character())
  )
})

# ---------------------------------------------------------------------------
# 9. CI configuration
# ---------------------------------------------------------------------------
ci_facts <- safe({
  wf <- Sys.glob(".github/workflows/*.y*ml")
  rd <- function(f) readLines(f, warn = FALSE)
  list(
    workflows = basename(wf),
    workflow_count = length(wf),
    torch_install_setting = unlist(lapply(wf, function(f)
      trimws(grep("TORCH_INSTALL", rd(f), value = TRUE)))),
    matrix_legs = if (file.exists(".github/workflows/R-CMD-check.yaml"))
      trimws(grep("^\\s*- \\{os:", rd(".github/workflows/R-CMD-check.yaml"),
                  value = TRUE)) else character(),
    continue_on_error = unlist(lapply(wf, function(f)
      sprintf("%s: %s", basename(f),
              trimws(grep("continue-on-error", rd(f), value = TRUE))))),
    missing_workflows = setdiff(
      c("lint", "spelling", "urlcheck", "release", "revdep", "dependabot"),
      tolower(tools::file_path_sans_ext(basename(wf)))),
    dependabot = file.exists(".github/dependabot.yml"),
    wordlist_has_consumer = ("spelling" %in% desc_facts$suggests) ||
      file.exists("tests/spelling.R")
  )
})

# ---------------------------------------------------------------------------
# 10. Shipped-artefact vs published-claim cross-check
#     The audit's most serious findings.  Measured from the .rds, not quoted.
# ---------------------------------------------------------------------------
artefact_facts <- safe({
  ex <- function(p) file.path("inst/extdata", p)
  out <- list()

  out$causal_iv <- safe({
    iv  <- readRDS(ex("causal_iv_cerrado_real.rds"))
    bt  <- iv$benchmark_table
    emb <- iv$embedding_sample_first5_64
    list(
      bundle_version   = as.character(iv$version),
      date_computed    = as.character(iv$date_computed),
      used_real_stack  = iv$used_real_stack,
      stack_nlyr       = iv$stack_nlyr,
      stack_res_deg    = iv$stack_res_deg,
      n_profiles       = iv$n_profiles_extracted,
      # full estimate table, so the shipped numbers can be compared to README
      estimates = data.frame(
        exposure  = as.character(bt$exposure),
        estimator = as.character(bt$estimator),
        beta      = bt$beta,
        stage1_F  = bt$stage1_F,
        sargan_p  = bt$sargan_p,
        row.names = NULL, stringsAsFactors = FALSE),
      # embedding health, measured rather than characterised
      embedding_sample = list(
        length         = length(emb),
        n_exact_zero   = sum(emb == 0, na.rm = TRUE),
        frac_exact_zero= if (length(emb)) mean(emb == 0, na.rm = TRUE) else NA_real_,
        min            = suppressWarnings(min(emb, na.rm = TRUE)),
        max            = suppressWarnings(max(emb, na.rm = TRUE)),
        sd             = stats::sd(emb, na.rm = TRUE),
        values         = emb),
      readme_claimed_sargan = local({
        ln <- readLines("README.md", warn = FALSE)
        i  <- grep("Sargan p \\(real MoCo\\)", ln)
        if (length(i)) trimws(ln[seq(i[1], min(i[1] + 4, length(ln)))]) else character()
      })
    )
  })

  out$llm_benchmark <- safe({
    lb <- readRDS(ex("llm_benchmark_results.rds"))
    list(mode = lb$mode, bundle_version = as.character(lb$version),
         date_computed = as.character(lb$date_computed),
         is_simulated = identical(lb$mode, "simulated"))
  })

  out$quantum_foundation <- safe({
    qf <- readRDS(ex("quantum_foundation_cerrado.rds"))
    list(cv_summary = qf$cv_summary,
         methods_with_r2_exactly_zero =
           sum(qf$cv_summary$r2_mean == 0, na.rm = TRUE))
  })

  out$r2_clamp_sites <- local({
    fs <- c(r_files, Sys.glob("data-raw/*.R"))
    unlist(lapply(fs, function(f) {
      ln <- readLines(f, warn = FALSE)
      i  <- grep("max\\(\\s*0\\s*,\\s*1\\s*-", ln)
      if (length(i)) sprintf("%s:%d", f, i) else character()
    }))
  })

  out$synthetic_covariate_sites <- local({
    fs <- Sys.glob("data-raw/*.R")
    unlist(lapply(fs, function(f) {
      ln <- readLines(f, warn = FALSE)
      i  <- grep("terra::values\\(.*rnorm", ln)
      if (length(i)) sprintf("%s:%d", f, i) else character()
    }))
  })

  out$bundles_read_by_tests <- test_static$tests_reading_extdata
  out$n_result_bundles      <- length(test_static$result_bundles)
  out
})

# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------
facts <- list(
  schema      = "edaphos-status-facts/1",
  environment = environment_facts,
  git         = git_facts,
  description = desc_facts,
  news        = news_facts,
  versioning  = version_facts,
  code        = code_facts,
  docs        = doc_facts,
  rd_portability = rd_portability,
  version_drift  = version_drift,
  phantoms    = phantom_facts,
  tests_static= test_static,
  tests_run   = test_run,
  dependencies= dep_facts,
  check       = check_facts,
  size        = size_facts,
  ci          = ci_facts,
  artefacts   = artefact_facts
)

out <- file.path(root, "tools", "status", "facts.json")
writeLines(jsonlite::toJSON(facts, pretty = TRUE, auto_unbox = TRUE,
                            null = "null", na = "null", digits = NA), out)
cat("wrote", out, "\n")
cat("  commit      :", facts$git$head_sha_short, "\n")
cat("  version     :", facts$description$version, "\n")
if (is.null(facts$tests_run$skipped) || !is.character(facts$tests_run$skipped))
  cat("  tests       :", facts$tests_run$passed, "pass /",
      facts$tests_run$skipped, "skip /", facts$tests_run$failed, "fail /",
      facts$tests_run$errored, "error\n")
cat("  check       :", if (is.null(facts$check$status_line))
      "parsed" else paste(facts$check$status, collapse = " "), "\n")
