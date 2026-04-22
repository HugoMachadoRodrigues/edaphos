# Ingest ~100 real abstracts from OpenAlex via Gemma 4 (Ollama).
# Caches per-row JSONs so the run is resumable. Saves the unique
# claims into inst/extdata/cerrado_claims_real_corpus.jsonl so the
# package can ship a ready-to-use dataset without forcing vignette
# consumers to re-run the full LLM pipeline.

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
})
reticulate::use_virtualenv("r-reticulate", required = FALSE)

cache_dir <- "tools/.llm_cache"
dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)

# Query three complementary slices of the Cerrado pedology literature
# for a total of ~150 candidates -> dedup -> take 100.
queries <- c(
  "Brazilian Cerrado soil organic carbon",
  "Cerrado land use change soil fertility",
  "Brazilian tropical soils pedogenesis"
)
pages <- lapply(queries, function(q) {
  message(">>> OpenAlex: ", q)
  causal_corpus_openalex(q, max_results = 60L, mailto = "edaphos@local")
})
corpus <- do.call(rbind, pages)
corpus <- causal_corpus_deduplicate(corpus)
corpus <- corpus[!is.na(corpus$abstract) & nzchar(corpus$abstract), ]
# Shuffle and cap.
set.seed(1L)
corpus <- corpus[sample(nrow(corpus)), , drop = FALSE]
corpus <- utils::head(corpus, 100L)
message("corpus after dedup + cap: ", nrow(corpus), " rows")

# Run the LLM extractor with disk cache. Cached rows skip the LLM
# call entirely on re-runs.
kg <- causal_kg_new()
kg <- causal_llm_ingest_corpus(
  kg, corpus,
  abstract_col = "abstract", source_col = "source",
  backend        = "ollama",
  model          = "gemma4:latest",
  min_confidence = 0.6,
  cache_dir      = cache_dir,
  max_retries    = 2L,
  timeout_sec    = 180
)

edges <- causal_kg_edges(kg)
message("edges extracted: ", nrow(edges))

# Write claims as JSONL for inst/extdata.
out_path <- "inst/extdata/cerrado_claims_real_corpus.jsonl"
lines <- vapply(seq_len(nrow(edges)), function(i) {
  jsonlite::toJSON(as.list(edges[i, ]), auto_unbox = TRUE)
}, character(1L))
writeLines(lines, out_path)
message("wrote ", length(lines), " claim lines to ", out_path)
