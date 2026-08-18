## tools/pretrain/wire_up_v2_doi.R
##
## After the v2 encoder is published on Zenodo, run this script with
## the new DOI/URL/SHA256 to patch R/foundation_weights.R and
## R/foundation_finetune.R to point at the published artefact.
##
## Usage:
##   Rscript tools/pretrain/wire_up_v2_doi.R \
##     <DOI>  <URL>  <SHA256>  <PUBLISHED_AT_ISO8601>
##
## Example:
##   Rscript tools/pretrain/wire_up_v2_doi.R \
##     10.5281/zenodo.20000001 \
##     https://zenodo.org/records/20000001/files/encoder_q.pt \
##     a1b2c3...e8f9 \
##     2026-05-01T18:30:00Z

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
  stop("Usage: wire_up_v2_doi.R <DOI> <URL> <SHA256> <PUBLISHED_AT_ISO8601>",
        call. = FALSE)
}
DOI    <- args[[1L]]
URL    <- args[[2L]]
SHA256 <- args[[3L]]
PUB_AT <- args[[4L]]

stopifnot(grepl("^10\\.5281/zenodo\\.", DOI))
stopifnot(grepl("^https://zenodo\\.org/", URL))
stopifnot(nchar(SHA256) == 64L)
stopifnot(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T", PUB_AT))

src <- "R/foundation_weights.R"
txt <- readLines(src, warn = FALSE)

# Replace the three NA placeholders for v2 in the registry table.
# WHY THIS BLOCK WAS REWRITTEN.
#
# The patterns were written as single-quoted R strings containing \', which
# yields a literal backslash followed by an apostrophe. Matched with
# fixed = TRUE against R/foundation_weights.R, they hit ZERO lines -- the
# file has "user's", not "user\'s". Measured: the mis-escaped pattern matches
# 0 lines, the correct one matches 2.
#
# Both sub() calls therefore did nothing, silently, and the positional
# fallback below then wrote the PUBLISHED_AT timestamp into ix[1] = line 67,
# which sits inside `url = c(`. The registry ended up with a timestamp where
# a URL belongs and NA in doi and published_at, and the file stayed
# syntactically valid R -- so nothing failed and nothing warned.
#
# Double quotes now, so the apostrophe needs no escaping at all; the
# published_at write is anchored to its own field instead of to a line
# index; and the script asserts the end state before exiting.

new <- txt

.replace_once <- function(x, pattern, value, what) {
  hits <- grep(pattern, x, fixed = TRUE)
  if (length(hits) == 0L)
    stop(sprintf("no line matches the %s placeholder; refusing to guess", what),
         call. = FALSE)
  x[hits[1L]] <- sub(pattern, value, x[hits[1L]], fixed = TRUE)
  x
}

# Anchor each write inside the field it belongs to, rather than trusting the
# order in which identical placeholders appear.
.field_bounds <- function(x, field) {
  open <- grep(sprintf("^\\s+%s\\s+= c\\(", field), x)
  if (length(open) != 1L)
    stop(sprintf("expected exactly one '%s = c(' opener, found %d",
                 field, length(open)), call. = FALSE)
  close <- open + which(grepl("^\\s*\\)", x[(open + 1L):length(x)]))[1L]
  c(open, close)
}

.set_in_field <- function(x, field, value, placeholder = "NA_character_") {
  b <- .field_bounds(x, field)
  rel <- grep(placeholder, x[b[1]:b[2]], fixed = TRUE)
  if (!length(rel))
    stop(sprintf("no %s placeholder inside '%s'", placeholder, field),
         call. = FALSE)
  k <- b[1] + rel[1] - 1L
  x[k] <- sub(placeholder, sprintf('"%s"', value), x[k], fixed = TRUE)
  x
}

new <- .set_in_field(new, "url",          URL)
new <- .set_in_field(new, "sha256",       SHA256)
new <- .set_in_field(new, "doi",          DOI)
new <- .set_in_field(new, "published_at", PUB_AT)

# ASSERT THE END STATE. The original script could complete having changed
# nothing, or having written the right value into the wrong field, and exit 0
# either way.
for (f in c("url", "sha256", "doi", "published_at")) {
  b <- .field_bounds(new, f)
  if (any(grepl("NA_character_", new[b[1]:b[2]], fixed = TRUE)))
    stop(sprintf("'%s' still holds NA_character_ after the rewrite", f),
         call. = FALSE)
}
if (!any(grepl(URL,    new, fixed = TRUE))) stop("URL was not written",    call. = FALSE)
if (!any(grepl(SHA256, new, fixed = TRUE))) stop("SHA256 was not written", call. = FALSE)
if (!any(grepl(DOI,    new, fixed = TRUE))) stop("DOI was not written",    call. = FALSE)
if (!any(grepl(PUB_AT, new, fixed = TRUE))) stop("published_at was not written", call. = FALSE)

writeLines(new, src)
message(sprintf("[wire-up-v2] patched %s with DOI %s.", src, DOI))
message("Now run:")
message("  Rscript -e 'devtools::document(); devtools::test()'")
message("  # then commit + push:")
message("  git add R/foundation_weights.R")
message("  git commit -m \"feat(v3.11.0): wire up edaphos-cerrado-moco-v2 DOI\"")
message("  git push origin main")
