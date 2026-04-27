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
patches <- list(
  c('NA_character_           # filled after the user\'s Zenodo upload',
    sprintf('"%s"', URL)),
  c('NA_character_           # filled by tools/pretrain/package_v2_for_zenodo.R',
    sprintf('"%s"', SHA256)),
  c('NA_character_           # filled after the user\'s Zenodo upload',
    sprintf('"%s"', DOI)),
  c('NA_character_\n    ),\n    edaphos_version = c\\("1.2.0", "3.11.0"\\)',
    sprintf('"%s"\n    ),\n    edaphos_version = c("1.2.0", "3.11.0")', PUB_AT))
)

# We do textual line-by-line rewrites so the diff stays tiny.
new <- txt
new <- sub('NA_character_           # filled after the user\\\'s Zenodo upload',
            sprintf('"%s"', URL), new, fixed = TRUE)
new <- sub('NA_character_           # filled by tools/pretrain/package_v2_for_zenodo.R',
            sprintf('"%s"', SHA256), new, fixed = TRUE)
# DOI placeholder occurs once after URL, so the next sub picks it up
new <- sub('NA_character_           # filled after the user\\\'s Zenodo upload',
            sprintf('"%s"', DOI), new, fixed = TRUE)
# published_at: one NA_character_ remains in the published_at vector
ix <- which(grepl('NA_character_', new))
if (length(ix) > 0L) {
  # the lone NA_character_ in published_at = c(...)
  new[ix[1L]] <- sub('NA_character_',
                       sprintf('"%s"', PUB_AT),
                       new[ix[1L]], fixed = TRUE)
}

writeLines(new, src)
message(sprintf("[wire-up-v2] patched %s with DOI %s.", src, DOI))
message("Now run:")
message("  Rscript -e 'devtools::document(); devtools::test()'")
message("  # then commit + push:")
message("  git add R/foundation_weights.R")
message("  git commit -m \"feat(v3.11.0): wire up edaphos-cerrado-moco-v2 DOI\"")
message("  git push origin main")
