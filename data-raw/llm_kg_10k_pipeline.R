## data-raw/llm_kg_10k_pipeline.R  (edaphos v3.10.0)
##
## End-to-end orchestrator for the Pilar 1 LLM Knowledge-Graph
## pipeline at scale (10 000+ abstracts).
##
## Usage:
##   1. Start a local Ollama instance and pull a Gemma 3 12B model:
##        $ ollama serve
##        $ ollama pull gemma3:12b
##   2. Provide a JSONL corpus at the path below (one
##      `{"source": ..., "abstract": ...}` object per line).
##   3. Run this script:
##        $ Rscript data-raw/llm_kg_10k_pipeline.R
##   4. Output goes to `inst/extdata/llm_kg_10k_claims.jsonl`.
##
## Resumability:
##   The pipeline writes a `.done` file alongside the output JSONL
##   listing successfully processed `source` ids; a re-run skips
##   them.  Errors are written to `.errors` (one line per failure).
##
## Performance budget (Gemma 3 12B on a modern Apple Silicon):
##   ~2-4 s / abstract -> 10 000 abstracts in ~6-11 hours.
##   Disk: ~50 MB JSONL claims output for ~5 claims / abstract.

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))

# ---------------------------------------------------------------------------
# Paths and parameters
# ---------------------------------------------------------------------------
CORPUS_PATH <- file.path("inst", "extdata", "cerrado_abstracts.jsonl")
OUTPUT_PATH <- file.path("inst", "extdata", "llm_kg_10k_claims.jsonl")

BACKEND <- "ollama"
MODEL   <- "gemma3:12b"
HOST    <- "http://localhost:11434"

# Override CORPUS_PATH from CLI if a path is given:
args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1L && nzchar(args[[1L]])) CORPUS_PATH <- args[[1L]]
if (length(args) >= 2L && nzchar(args[[2L]])) OUTPUT_PATH <- args[[2L]]

# ---------------------------------------------------------------------------
# Pre-flight check
# ---------------------------------------------------------------------------
message("=== [1/3] Pre-flight checks ===")
chk <- llm_kg_ollama_check(host = HOST, model = MODEL, timeout_sec = 3)
if (!chk$reachable) {
  stop("Ollama is not reachable at ", HOST,
        ".  Start `ollama serve` first.")
}
if (isFALSE(chk$model_present)) {
  warning("Model '", MODEL, "' is not present on the Ollama server.\n",
           "Pull it with `ollama pull ", MODEL, "`.\n",
           "Available models: ",
           paste(utils::head(chk$models_available, 6), collapse = ", "))
}
if (!file.exists(CORPUS_PATH)) {
  stop("Corpus not found at ", CORPUS_PATH,
        ".  Provide a JSONL with one {source, abstract} object per line.")
}

n_lines <- length(readLines(CORPUS_PATH, warn = FALSE))
message(sprintf("Corpus  : %s  (%d lines)", CORPUS_PATH, n_lines))
message(sprintf("Output  : %s",            OUTPUT_PATH))
message(sprintf("Backend : %s @ %s  model = %s",
                 BACKEND, HOST, MODEL))

# ---------------------------------------------------------------------------
# Run the pipeline
# ---------------------------------------------------------------------------
message("=== [2/3] Running extraction ===")
res <- llm_kg_pipeline_run(
  corpus_path    = CORPUS_PATH,
  output_path    = OUTPUT_PATH,
  backend        = BACKEND,
  model          = MODEL,
  host           = HOST,
  temperature    = 0,
  timeout_sec    = 180,
  max_retries    = 3L,
  min_confidence = 0.5,
  verbose        = TRUE
)

# ---------------------------------------------------------------------------
# Aggregate diagnostics
# ---------------------------------------------------------------------------
message("=== [3/3] KG diagnostics ===")
kg <- res$kg
message(sprintf("Processed           : %d", res$n_processed))
message(sprintf("Skipped (resumed)   : %d", res$n_skipped))
message(sprintf("Errors              : %d", res$n_errors))
n_edges <- nrow(igraph::as_edgelist(kg$graph))
n_nodes <- length(igraph::V(kg$graph))
message(sprintf("KG nodes            : %d", n_nodes))
message(sprintf("KG edges            : %d", n_edges))

invisible(res)
