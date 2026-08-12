#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# tools/status/apply-findings.R -- apply verified verdicts to the register.
#
# WHY THIS EXISTS. tools/status/findings.json is the work order STATUS.md
# renders, and it went four months without an update while a long correctness
# campaign ran through the repository. The result was a register wrong in both
# directions: findings listed OPEN that had been fixed, and evidence citing
# line numbers that now hold unrelated code.
#
# The closing protocol was documented in STATUS.md all along -- `resolved`,
# `resolved_in`, `resolution` -- and used fourteen times, none of them during
# the campaign. Closing by hand is why: it is tedious, and a register nobody
# can update cheaply is a register nobody updates.
#
# INPUT is a JSON array of verified verdicts, one object per finding that
# changes state:
#
#   [{"id": "F0BC16C", "status": "RESOLVED",
#     "resolution": "what changed, with file:line",
#     "resolved_in": "abc1234",
#     "current_evidence": ""}, ...]
#
# WHAT IT REFUSES. A verdict for an id the register does not hold; a RESOLVED
# with no resolution text; a status it does not recognise. Each is an error,
# not a warning, because a register that silently drops a verdict is back to
# being untrustworthy.
#
#   Rscript tools/status/apply-findings.R verdicts.json [--dry-run]
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
dry  <- "--dry-run" %in% args
path <- setdiff(args, "--dry-run")[1]
if (is.na(path) || !file.exists(path))
  stop("usage: Rscript tools/status/apply-findings.R <verdicts.json> [--dry-run]",
       call. = FALSE)

`%||%` <- function(a, b) if (is.null(a)) b else a

REG <- "tools/status/findings.json"
reg <- jsonlite::fromJSON(REG, simplifyDataFrame = FALSE)
items <- if (!is.null(reg$findings)) reg$findings else reg
stopifnot(is.list(items), length(items) > 0)

v <- jsonlite::fromJSON(path, simplifyDataFrame = FALSE)
if (!is.null(v$verdicts)) v <- v$verdicts
stopifnot(is.list(v))

ids <- vapply(items, function(x) as.character(x$id %||% ""), character(1))

VALID <- c("RESOLVED", "OPEN", "MISSTATED", "NOT_A_DEFECT", "NOT_VERIFIED")
n_closed <- n_refreshed <- n_dropped <- 0L
unknown <- character(0)

for (u in v) {
  id <- as.character(u$id %||% "")
  st <- toupper(as.character(u$status %||% ""))
  if (!nzchar(id)) stop("a verdict has no id", call. = FALSE)
  if (!st %in% VALID)
    stop(sprintf("verdict for %s has unrecognised status '%s'", id, st), call. = FALSE)
  k <- match(id, ids)
  if (is.na(k)) { unknown <- c(unknown, id); next }

  if (identical(st, "RESOLVED")) {
    res <- as.character(u$resolution %||% "")
    if (!nzchar(res))
      stop(sprintf("%s is marked RESOLVED with no resolution text; refusing", id),
           call. = FALSE)
    items[[k]]$resolved    <- TRUE
    items[[k]]$resolved_in <- as.character(u$resolved_in %||% "")
    items[[k]]$resolution  <- res
    n_closed <- n_closed + 1L
  } else if (identical(st, "NOT_A_DEFECT")) {
    items[[k]]$resolved    <- TRUE
    items[[k]]$resolved_in <- as.character(u$resolved_in %||% "")
    items[[k]]$resolution  <- paste0("withdrawn: ",
                                     as.character(u$resolution %||% "not a defect"))
    items[[k]]$verdict     <- "REFUTED"
    n_dropped <- n_dropped + 1L
  } else {
    # Stays open. Refresh the evidence: a July line number pointing at code
    # that has since moved is worse than no citation, because it sends the
    # next reader to the wrong place.
    ce <- as.character(u$current_evidence %||% "")
    if (nzchar(ce)) {
      items[[k]]$evidence <- ce
      items[[k]]$evidence_refreshed_at <- format(Sys.Date())
      n_refreshed <- n_refreshed + 1L
    }
    if (identical(st, "MISSTATED")) items[[k]]$verdict <- "PARTIALLY_TRUE"
  }
}

if (length(unknown))
  stop(sprintf("%d verdicts name ids the register does not hold: %s",
               length(unknown), paste(unknown, collapse = ", ")), call. = FALSE)

open_now <- sum(!vapply(items, function(x) isTRUE(x$resolved), TRUE))
cat(sprintf("closed %d, withdrawn %d, evidence refreshed %d\n",
            n_closed, n_dropped, n_refreshed))
cat(sprintf("open findings: %d -> %d\n",
            sum(!vapply(items, function(x) isTRUE(x$resolved), TRUE)) + n_closed + n_dropped,
            open_now))

if (dry) { cat("(dry run; nothing written)\n"); quit(save = "no") }

if (!is.null(reg$findings)) reg$findings <- items else reg <- items
jsonlite::write_json(reg, REG, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("wrote", REG, "\n")
cat("now re-render:  Rscript tools/status/render.R\n")
