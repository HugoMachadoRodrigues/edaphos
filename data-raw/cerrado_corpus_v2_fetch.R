## data-raw/cerrado_corpus_v2_fetch.R  (v1.8.2 preparation)
##
## Fetches ~100-150 real Cerrado-pedology abstracts from OpenAlex,
## deduplicates, applies quality filters, and writes the corpus
## JSONL consumed downstream by `edaphos::llm_preannotate()`.
##
## Usage
##   Rscript data-raw/cerrado_corpus_v2_fetch.R
##
## Env vars
##   EDAPHOS_CORPUS_MAILTO   Your email (goes into OpenAlex User-Agent;
##                            gets you a higher rate limit. Recommended).
##   EDAPHOS_CORPUS_MAX_PER  Integer, max abstracts per query (default 60).
##   EDAPHOS_CORPUS_OUTPUT   Output path (default below).
##
## Requires network access. Respects OpenAlex's recommended ~10 req/s
## via their throttling; 4 queries × 60 results ≈ 40 seconds.

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))

OUT_PATH <- Sys.getenv(
  "EDAPHOS_CORPUS_OUTPUT",
  unset = "inst/extdata/cerrado_corpus_openalex_v2.jsonl"
)
MAX_PER  <- as.integer(Sys.getenv("EDAPHOS_CORPUS_MAX_PER", unset = "60"))
MAILTO   <- Sys.getenv("EDAPHOS_CORPUS_MAILTO", unset = "")

if (!nzchar(MAILTO)) {
  message("  [note] EDAPHOS_CORPUS_MAILTO not set.  OpenAlex applies a",
          " lower rate-limit (~1 req/s) to unauthenticated clients.",
          "\n         Set it to an email you check to get the polite-pool",
          " (~10 req/s).")
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Orthogonal queries
# ─────────────────────────────────────────────────────────────────────────────
queries <- c(
  "cerrado AND (pedogenesis OR \"soil formation\")",
  "cerrado AND \"soil organic carbon\"",
  "(cerrado OR savanna) AND (clay OR texture) AND soil",
  "cerrado AND (\"land use change\" OR deforestation) AND soil",
  "cerrado AND (erosion OR \"soil erosion\") AND brazil",
  "cerrado AND (\"bulk density\" OR compaction) AND soil"
)

message(sprintf("=== Fetching %d queries × up to %d results each ===",
                length(queries), MAX_PER))

all_corpus <- list()
for (q in seq_along(queries)) {
  qt <- queries[q]
  message(sprintf("  [%d/%d] %s", q, length(queries), qt))
  res <- tryCatch(
    causal_corpus_openalex(
      query        = qt,
      max_results  = MAX_PER,
      from_year    = 2010L,
      mailto       = if (nzchar(MAILTO)) MAILTO else NULL,
      timeout_sec  = 180L
    ),
    error = function(e) {
      message(sprintf("    [warn] query failed: %s", conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(res) && nrow(res) > 0L) {
    res$query <- qt
    all_corpus[[q]] <- res
    message(sprintf("    -> %d abstracts", nrow(res)))
  }
}

if (length(all_corpus) == 0L) {
  stop("No corpus rows retrieved. Check network + EDAPHOS_CORPUS_MAILTO.",
       call. = FALSE)
}

raw <- bind_rows(all_corpus)
message(sprintf("Raw total: %d rows", nrow(raw)))

# ─────────────────────────────────────────────────────────────────────────────
# 2. Deduplication (DOI + title) and quality filters
# ─────────────────────────────────────────────────────────────────────────────
dedup <- causal_corpus_deduplicate(raw, by = c("doi", "title"))
message(sprintf("After dedup  : %d rows", nrow(dedup)))

quality <- dedup |>
  filter(
    !is.na(abstract),
    nchar(abstract) >= 250,          # must be informative
    nchar(abstract) <= 3000,         # OpenAlex sometimes has stitched books
    !is.na(year), year >= 2010L
  )
message(sprintf("After quality: %d rows", nrow(quality)))

# Cap at 150 by most-recent first, then shuffle deterministically within
# year so the sample is balanced across years
set.seed(20260425L)
quality <- quality[order(-quality$year, stats::runif(nrow(quality))), ]
if (nrow(quality) > 150L) quality <- head(quality, 150L)
message(sprintf("After cap    : %d rows", nrow(quality)))

# ─────────────────────────────────────────────────────────────────────────────
# 3. Convert to the schema expected by llm_preannotate()
# ─────────────────────────────────────────────────────────────────────────────
records <- lapply(seq_len(nrow(quality)), function(i) {
  list(
    abstract_id   = sprintf("OA_%04d", i),
    title         = quality$title[i],
    abstract_text = quality$abstract[i],
    year          = as.integer(quality$year[i]),
    doi           = if (nzchar(quality$doi[i] %||% ""))
                        quality$doi[i]  else NULL,
    url           = if (nzchar(quality$url[i] %||% ""))
                        quality$url[i]  else NULL,
    source        = quality$source[i],
    query         = quality$query[i]
  )
})

# Write JSONL
if (!dir.exists(dirname(OUT_PATH))) dir.create(dirname(OUT_PATH), recursive = TRUE)
con <- file(OUT_PATH, "w")
on.exit(close(con), add = TRUE)
for (r in records) {
  writeLines(jsonlite::toJSON(r, auto_unbox = TRUE, null = "null"), con)
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Year / source descriptive stats
# ─────────────────────────────────────────────────────────────────────────────
year_tab   <- sort(table(quality$year),   decreasing = TRUE)
source_tab <- sort(table(quality$source), decreasing = TRUE)

message(sprintf("\n=== DONE | %s | %d abstracts | %.1f KB ===",
                OUT_PATH, length(records), file.size(OUT_PATH) / 1024))
message(sprintf("Years  : %s",
                paste(sprintf("%s=%d", names(year_tab), year_tab),
                      collapse = ", ")))
message(sprintf("Sources: %s",
                paste(sprintf("%s=%d", names(source_tab), source_tab),
                      collapse = ", ")))
message("")
message("Next step:")
message(sprintf("  edaphos::llm_preannotate('%s',", OUT_PATH))
message("                            backend     = 'ollama',")
message("                            model       = 'gemma4:latest',")
message("                            output_path = 'inst/extdata/cerrado_gold_standard_v2_draft.jsonl',")
message("                            cache_dir   = '~/.cache/edaphos_annotation')")

invisible(records)
