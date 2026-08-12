#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# tools/build_s2_pipeline.R -- assemble S2 File.
#
# The manuscript offers "Scripts that regenerate the soil-profile and covariate
# datasets from their public sources, train the foundation encoder, and produce
# the result bundles" as supporting information, and until now no artefact
# existed: `.Rbuildignore` excludes `data-raw` from the package tarball, so a
# reader following S2 File found nothing to download.
#
# This builds one: every data-raw script, plus a RUN-ORDER derived from the
# scripts themselves rather than written by hand. The order is read from what
# each script CONSUMES (readRDS of an inst/extdata bundle) and what it
# PRODUCES (saveRDS to one), so a script that reads another's output is placed
# after it. Anything the parse cannot resolve is listed as unordered rather
# than guessed at.
#
# Also records, per script, whether it needs the network, a Python runtime, or
# torch -- because "reproducible" means something different for a script that
# downloads 2 GB than for one that reads a shipped bundle.
#
# Output: paper/S2_File_pipeline.zip
# ---------------------------------------------------------------------------

root <- normalizePath(".")
setwd(root)
scripts <- sort(list.files("data-raw", pattern = "[.]R$", full.names = TRUE))
stopifnot(length(scripts) > 0)

reads <- writes <- needs <- vector("list", length(scripts))
names(reads) <- names(writes) <- names(needs) <- basename(scripts)

for (i in seq_along(scripts)) {
  txt <- paste(readLines(scripts[i], warn = FALSE), collapse = "\n")
  # what it consumes and produces, by the bundle names it names
  # A call like saveRDS(list(a = 1), "x.rds") defeats a [^)]* scan, because
  # the scan stops at the ')' closing list(). Take instead the FIRST .rds
  # literal that follows each readRDS/saveRDS token.
  after <- function(tok) {
    pos <- gregexpr(tok, txt, fixed = TRUE)[[1]]
    if (pos[1] == -1L) return(character(0))
    out <- character(0)
    for (p0 in pos) {
      tail_txt <- substr(txt, p0, min(nchar(txt), p0 + 4000L))
      m <- regmatches(tail_txt, regexpr('["\'][^"\']+\\.rds["\']', tail_txt))
      if (length(m)) out <- c(out, gsub('^["\']|["\']$', "", m))
    }
    unique(basename(out))
  }
  # Some scripts write through a variable -- `saveRDS(out, OUT)` with
  # `OUT <- "inst/extdata/x.rds"` above -- so the literal is not adjacent to
  # the call. Resolve simple top-level assignments of .rds paths and treat a
  # saveRDS whose target is such a name as writing that file. Without this the
  # WoSIS builder looked like it produced nothing and ten dependent scripts
  # fell into "unordered".
  assign_rds <- regmatches(txt, gregexpr(
    '[A-Za-z._][A-Za-z0-9._]*[ ]*<-[ ]*["\'][^"\']+\\.rds["\']', txt))[[1]]
  var_of <- list()
  for (a in assign_rds) {
    nm <- trimws(sub("<-.*", "", a))
    fl <- basename(gsub('.*["\']([^"\']+\\.rds)["\'].*', "\\1", a))
    var_of[[nm]] <- fl
  }
  via_var <- function(tok) {
    pos <- gregexpr(tok, txt, fixed = TRUE)[[1]]
    if (pos[1] == -1L) return(character(0))
    out <- character(0)
    for (p0 in pos) {
      call_txt <- substr(txt, p0, min(nchar(txt), p0 + 300L))
      for (nm in names(var_of))
        # perl = TRUE: R's default engine is POSIX extended, where \\b is not a
        # word boundary and this silently never matches.
        if (grepl(paste0("\\b", nm, "\\b"), call_txt, perl = TRUE))
          out <- c(out, var_of[[nm]])
    }
    unique(out)
  }
  r_lit <- after("readRDS(");  w_lit <- after("saveRDS(")
  # Variable resolution only fills a GAP. Using it additively made
  # piml_depth_benchmark.R appear to write the bundle it reads, because a
  # variable holding that path happens to sit near its saveRDS call.
  reads[[i]]  <- if (length(r_lit)) r_lit else via_var("readRDS(")
  writes[[i]] <- if (length(w_lit)) w_lit else via_var("saveRDS(")
  # A script cannot be its own producer.
  writes[[i]] <- setdiff(writes[[i]], reads[[i]])
  # what it needs from the environment
  n <- character(0)
  if (grepl("download\\.file|httr2|req_perform|GET\\(|WFS|https://", txt)) n <- c(n, "network")
  if (grepl("reticulate|qiskit|import\\(", txt)) n <- c(n, "python")
  if (grepl("torch::|torch_is_installed", txt)) n <- c(n, "torch")
  if (grepl("ollama|causal_llm_extract", txt)) n <- c(n, "local LLM")
  needs[[i]] <- n
}

# Topological-ish ordering: a script comes after any script that writes a
# bundle it reads. Cycles and unresolved names fall through to "unordered",
# which is reported rather than silently linearised.
produced_by <- list()
for (i in seq_along(scripts))
  for (w in writes[[i]]) produced_by[[w]] <- c(produced_by[[w]], names(writes)[i])

placed <- character(0); pending <- names(reads); guard <- 0L
while (length(pending) && guard < 100L) {
  guard <- guard + 1L
  ready <- pending[vapply(pending, function(s) {
    dep <- unlist(produced_by[reads[[s]]])
    dep <- setdiff(dep, s)
    all(dep %in% placed) || !length(dep)
  }, TRUE)]
  if (!length(ready)) break
  placed <- c(placed, ready); pending <- setdiff(pending, ready)
}

fmt_needs <- function(n) if (!length(n)) "shipped data only" else paste(n, collapse = ", ")
lines <- c(
  "# S2 File -- data retrieval and analysis pipeline",
  "",
  sprintf("Generated by tools/build_s2_pipeline.R on %s from the edaphos repository.", Sys.Date()),
  "",
  "Every script in `data-raw/` is included. Run them from the repository root",
  "with `Rscript data-raw/<name>`.",
  "",
  "**On the ordering.** The `Consumes` and `Produces` columns are parsed from",
  "the scripts by matching `.rds` literals near `readRDS`/`saveRDS`, and the",
  "order places a script after whatever produces what it reads. That parse is",
  "a heuristic: a path built at run time, or held in a variable far from its",
  "call, is not resolved. Scripts it could not place are listed separately",
  "rather than folded into a sequence that would look authoritative and be",
  "guesswork. Check the header comment of any script before relying on its",
  "position here.",
  "",
  "The `Requires` column matters: a script marked `shipped data only` runs",
  "against the bundles in `inst/extdata/` and reproduces offline, while one",
  "marked `network` re-downloads from WoSIS, SoilData or Copernicus and will",
  "differ if those archives have changed.",
  "",
  "| # | Script | Requires | Produces |",
  "|---:|:---|:---|:---|")
for (i in seq_along(placed)) {
  s <- placed[i]
  lines <- c(lines, sprintf("| %d | `%s` | %s | %s |", i, s, fmt_needs(needs[[s]]),
                            if (length(writes[[s]])) paste0("`", paste(writes[[s]], collapse = "`, `"), "`") else "--"))
}
if (length(pending)) {
  lines <- c(lines, "",
    "## Unordered",
    "",
    "The parse could not place these: it did not resolve a producer for",
    "something they read, or they participate in a cycle it cannot break.",
    "Each names its inputs in its own header comment. Listed rather than",
    "guessed at:",
    "", paste0("- `", pending, "`"))
}
lines <- c(lines, "",
  "## What cannot be reproduced from here",
  "",
  "- The foundation encoder's training data is a 2 GB Sentinel-2 / Copernicus",
  "  extract that is downloaded, not shipped; `case_cerrado_prepare.R` fetches it.",
  "- The LLM extraction needs a local Ollama; without one the capstone builder",
  "  records that fact and leaves the slot empty rather than substituting",
  "  hand-written rows.",
  "- Scripts marked `torch` fall back to a pure-R reference implementation that",
  "  announces itself; the reference path is not the trained one.")

dir.create("paper", showWarnings = FALSE)
tmp <- file.path(tempdir(), "S2_File_pipeline")
unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
invisible(file.copy(scripts, file.path(tmp, basename(scripts))))
writeLines(lines, file.path(tmp, "RUN-ORDER.md"))

zipfile <- file.path(root, "paper", "S2_File_pipeline.zip")
unlink(zipfile)
old <- getwd(); setwd(dirname(tmp))
utils::zip(zipfile, basename(tmp), flags = "-rq")
setwd(old)

cat(sprintf("\nS2 File: %d scripts, %d ordered, %d unordered, %.0f KB\n",
            length(scripts), length(placed), length(pending),
            file.size(zipfile) / 1024))
cat(sprintf("network-dependent: %d | torch: %d | python: %d | offline: %d\n",
            sum(vapply(needs, function(n) "network" %in% n, TRUE)),
            sum(vapply(needs, function(n) "torch" %in% n, TRUE)),
            sum(vapply(needs, function(n) "python" %in% n, TRUE)),
            sum(vapply(needs, function(n) !length(n), TRUE))))
message("wrote paper/S2_File_pipeline.zip")
