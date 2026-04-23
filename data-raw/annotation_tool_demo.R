## data-raw/annotation_tool_demo.R  (v1.8.1)
##
## Produces a DRAFT gold-standard by running Gemma 4 (or the
## deterministic simulator) over the 30 synthetic abstracts of
## inst/extdata/cerrado_gold_standard_v1.jsonl, discarding the
## hand-annotated claims and keeping only the LLM drafts.
##
## The resulting inst/extdata/cerrado_gold_standard_v1_draft.jsonl
## is what `llm_annotation_launch()` consumes to demonstrate the
## Shiny reviewer.
##
## For the production v2 run (v1.8.2), replace step (0) with a real
## OpenAlex / SciELO corpus fetch producing ~100 abstracts.

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))

# ─────────────────────────────────────────────────────────────────────────────
# 0. Load the 30-abstract seed and strip its gold claims
# ─────────────────────────────────────────────────────────────────────────────
seed_path  <- "inst/extdata/cerrado_gold_standard_v1.jsonl"
draft_path <- "inst/extdata/cerrado_gold_standard_v1_draft.jsonl"

stopifnot(file.exists(seed_path))
seed_records <- lapply(readLines(seed_path, warn = FALSE),
                        jsonlite::fromJSON, simplifyVector = TRUE)

# Keep abstract fields only; drop the claims (they'd leak into the
# reviewer as already-labelled).
corpus <- lapply(seed_records, function(r) {
  list(
    abstract_id   = r$abstract_id,
    title         = r$title,
    abstract_text = r$abstract_text,
    year          = r$year,
    topic         = r$topic
  )
})

message(sprintf("Loaded %d abstracts from %s", length(corpus), seed_path))

# ─────────────────────────────────────────────────────────────────────────────
# 1. Pre-annotate
# ─────────────────────────────────────────────────────────────────────────────
backend <- if (identical(Sys.getenv("EDAPHOS_USE_REAL_LLM", ""), "1")) {
  "ollama"
} else {
  "simulator"
}
message(sprintf("Backend: %s", backend))

edaphos::llm_preannotate(
  corpus      = corpus,
  backend     = backend,
  model       = if (backend == "ollama") "gemma4:latest" else "simulator",
  output_path = draft_path,
  cache_dir   = NULL,
  verbose     = TRUE
)

# ─────────────────────────────────────────────────────────────────────────────
# 2. Validate the draft
# ─────────────────────────────────────────────────────────────────────────────
v <- edaphos::llm_annotation_validate(draft_path, strict_vocab = FALSE)
message(sprintf(
  "Validation: ok=%s, errors=%d",
  v$ok, length(v$errors)
))
if (length(v$errors) > 0L) {
  message("First 5 errors:")
  for (e in head(v$errors, 5)) message("  ", e)
}

message(sprintf(
  "\n=== DONE | draft: %s | next: llm_annotation_launch('%s') ===",
  draft_path, draft_path
))
