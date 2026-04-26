# Pilar 1 -- 10k LLM-KG pipeline (edaphos v3.10.0).
#
# Production-grade orchestrator for running `causal_llm_extract()`
# over a large abstract corpus (10 000+ abstracts), with:
#
#   * Pre-flight checks of the LLM backend (Ollama HTTP endpoint and
#     model availability, OpenAI / Anthropic API keys for the hosted
#     backends).
#   * Resumable JSONL checkpointing so a 10-hour run can be killed
#     and resumed without losing work.
#   * Throttle / retry with exponential back-off on transient LLM
#     failures.
#   * Streaming aggregate to an `edaphos_causal_kg` and a JSONL
#     claims file, ready for `causal_kg_to_dagitty()` /
#     `causal_kg_to_turtle()` consumption.
#
# Why a separate file vs `causal_llm.R`
# -------------------------------------
# `causal_llm_extract()` is the per-abstract primitive.
# `llm_kg_pipeline_run()` is the multi-hour, multi-thousand-abstract
# orchestrator with checkpointing -- distinct concerns, distinct
# failure modes (single-call resilience vs job-level resumability).

#' Check whether a local Ollama server is reachable
#'
#' Issues a 1-second HEAD request to the Ollama `/api/tags` endpoint
#' and reports whether the server responds.  Used by
#' [`llm_kg_pipeline_run()`] as a pre-flight gate.
#'
#' @param host Character; the base URL of the Ollama server.
#'   Default `"http://localhost:11434"`.
#' @param model Optional character; if supplied, additionally
#'   verifies that the named model is present on the server.
#' @param timeout_sec Numeric; HTTP timeout.  Default `1`.
#' @return Named logical list with `reachable` (bool) and (when
#'   `model` is non-NULL) `model_present` (bool).
#' @export
llm_kg_ollama_check <- function(host = "http://localhost:11434",
                                   model = NULL,
                                   timeout_sec = 1) {
  reachable <- tryCatch({
    req <- httr2::request(host)
    req <- httr2::req_url_path(req, "/api/tags")
    req <- httr2::req_method(req, "GET")
    req <- httr2::req_timeout(req, timeout_sec)
    resp <- httr2::req_perform(req)
    httr2::resp_status(resp) < 400L
  }, error = function(e) FALSE)
  out <- list(reachable = isTRUE(reachable))
  if (!is.null(model) && out$reachable) {
    body <- tryCatch({
      req <- httr2::request(host)
      req <- httr2::req_url_path(req, "/api/tags")
      req <- httr2::req_timeout(req, timeout_sec * 2)
      httr2::resp_body_json(httr2::req_perform(req),
                              simplifyVector = TRUE)
    }, error = function(e) NULL)
    names_present <- if (is.list(body) && !is.null(body$models)) {
      names_field <- body$models$name %||% body$models$model %||% character(0)
      as.character(names_field)
    } else character(0)
    out$model_present <- model %in% names_present
    out$models_available <- names_present
  }
  out
}

# Read a JSONL file into a data frame (cause, effect, ... per line).
.llm_kg_read_jsonl <- function(path) {
  if (!file.exists(path)) return(NULL)
  lines <- readLines(path, warn = FALSE)
  if (length(lines) == 0L) return(NULL)
  out <- lapply(lines, function(ln) {
    tryCatch(jsonlite::fromJSON(ln, simplifyVector = TRUE),
              error = function(e) NULL)
  })
  out <- out[!vapply(out, is.null, logical(1L))]
  if (length(out) == 0L) return(NULL)
  do.call(rbind, lapply(out, function(x) {
    as.data.frame(x[c("cause", "effect", "evidence",
                        "confidence", "source")],
                    stringsAsFactors = FALSE)
  }))
}

# Append a single set of claims (a data frame) to the JSONL output.
.llm_kg_append_jsonl <- function(path, claims, source) {
  if (is.null(claims) || nrow(claims) == 0L) return(invisible(0L))
  con <- file(path, open = "at", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  for (i in seq_len(nrow(claims))) {
    rec <- list(
      cause      = as.character(claims$cause[i]),
      effect     = as.character(claims$effect[i]),
      evidence   = as.character(claims$evidence[i]),
      confidence = as.numeric(claims$confidence[i]),
      source     = source,
      timestamp  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    )
    cat(jsonlite::toJSON(rec, auto_unbox = TRUE), "\n",
         file = con, sep = "")
  }
  nrow(claims)
}

#' Run the Pilar 1 LLM-KG pipeline on a (potentially large) corpus
#'
#' Drives `causal_llm_extract()` over a JSONL corpus of abstracts
#' (one JSON object with `source` + `abstract` per line) with
#' resumable JSONL checkpointing and throttle / retry.  The function
#' is engineered for 10 000+ abstract runs that can take several
#' hours to a day on a local Ollama instance.
#'
#' @section Resumability:
#'
#' On every successful per-abstract extraction, claims are appended
#' to `output_path` and the source identifier is appended to
#' `output_path.done`.  When `llm_kg_pipeline_run()` is restarted
#' on the same `output_path`, abstracts whose source is already in
#' the `.done` file are skipped automatically.  This makes the
#' pipeline safe under arbitrary process kills, network drops, or
#' Ollama restarts.
#'
#' @section Throttle / retry:
#'
#' Transient errors (HTTP 5xx, timeouts, JSON parse failures) are
#' retried up to `max_retries` times with exponential back-off
#' (1s, 2s, 4s, ...).  Persistent errors are logged to
#' `output_path.errors` and skipped without halting the run.
#'
#' @param corpus_path Character path to a JSONL file with one
#'   `{"source": ..., "abstract": ...}` object per line.
#' @param output_path Character path to the JSONL claims output.
#'   Created on first run; appended on resume.
#' @param backend One of `"ollama"`, `"openai"`, `"anthropic"`.
#' @param model LLM model identifier; defaults to backend-appropriate.
#' @param host Ollama HTTP host (ignored for hosted backends).
#' @param temperature Numeric; LLM sampling temperature.  Default `0`.
#' @param timeout_sec Numeric; per-call HTTP timeout.  Default `120`.
#' @param max_retries Integer; transient-error retry budget.
#'   Default `3L`.
#' @param min_confidence Numeric; claims below this confidence are
#'   discarded.  Default `0.5`.
#' @param verbose Logical; emit progress messages.  Default `TRUE`.
#' @param max_abstracts Optional integer; for testing, cap the run.
#' @return Invisibly, a list with `n_processed`, `n_skipped`,
#'   `n_errors`, and the final `kg` object.
#' @export
llm_kg_pipeline_run <- function(corpus_path,
                                   output_path,
                                   backend = c("ollama", "openai", "anthropic"),
                                   model   = NULL,
                                   host    = "http://localhost:11434",
                                   temperature = 0,
                                   timeout_sec = 120,
                                   max_retries = 3L,
                                   min_confidence = 0.5,
                                   verbose = TRUE,
                                   max_abstracts = NULL) {
  backend <- match.arg(backend)
  if (!file.exists(corpus_path))
    .stopf("Corpus file not found: %s", corpus_path,
            hint = "Pass a JSONL with one {source, abstract} object per line.")
  if (backend == "ollama") {
    chk <- llm_kg_ollama_check(host = host, model = model,
                                  timeout_sec = 2)
    if (!chk$reachable)
      .stopf("Ollama is not reachable at %s.", host,
              hint = "Start the server with `ollama serve` (or pass `host = ...`) before calling this function.")
    if (!is.null(model) && isFALSE(chk$model_present))
      .stopf("Model '%s' is not present on the Ollama server.", model,
              hint = sprintf("Pull it with `ollama pull %s` or pick from %s.",
                              model,
                              paste(utils::head(chk$models_available, 6),
                                    collapse = ", ")))
  }

  # Resume bookkeeping
  done_path  <- paste0(output_path, ".done")
  err_path   <- paste0(output_path, ".errors")
  done_set <- if (file.exists(done_path))
    readLines(done_path, warn = FALSE) else character(0)
  if (verbose && length(done_set) > 0L)
    message(sprintf("[llm_kg_pipeline] resuming -- %d abstracts already done.",
                     length(done_set)))

  # Read the corpus
  lines <- readLines(corpus_path, warn = FALSE)
  records <- lapply(lines, function(ln)
    tryCatch(jsonlite::fromJSON(ln, simplifyVector = TRUE),
              error = function(e) NULL))
  records <- records[!vapply(records, is.null, logical(1L))]
  if (!is.null(max_abstracts) && length(records) > max_abstracts)
    records <- records[seq_len(max_abstracts)]

  kg <- causal_kg_new()
  if (verbose)
    message(sprintf("[llm_kg_pipeline] corpus has %d abstracts; %d to process.",
                     length(records),
                     length(records) - length(done_set)))

  n_processed <- 0L; n_skipped <- 0L; n_errors <- 0L

  for (i in seq_along(records)) {
    rec <- records[[i]]
    src <- rec$source %||% sprintf("abstract_%05d", i)
    if (src %in% done_set) {
      n_skipped <- n_skipped + 1L
      next
    }
    txt <- rec$abstract %||% rec$text %||% ""
    if (!nzchar(txt)) {
      n_errors <- n_errors + 1L
      cat(sprintf("[%s]\tempty abstract\n", src),
           file = err_path, append = TRUE)
      next
    }

    delay <- 1
    success <- FALSE
    for (attempt in seq_len(max_retries + 1L)) {
      claims <- tryCatch(
        causal_llm_extract(txt, backend = backend, model = model,
                              host = host, temperature = temperature,
                              timeout_sec = timeout_sec),
        error = function(e) e
      )
      if (inherits(claims, "data.frame")) {
        if (!is.null(min_confidence) && "confidence" %in% names(claims)) {
          claims <- claims[claims$confidence >= min_confidence, ,
                              drop = FALSE]
        }
        .llm_kg_append_jsonl(output_path, claims, source = src)
        if (nrow(claims) > 0L) {
          for (k in seq_len(nrow(claims))) {
            kg <- tryCatch(
              causal_kg_add_edge(kg,
                cause = claims$cause[k], effect = claims$effect[k],
                source = src, evidence = claims$evidence[k],
                confidence = claims$confidence[k]),
              error = function(e) kg
            )
          }
        }
        cat(src, "\n", file = done_path, sep = "", append = TRUE)
        success <- TRUE
        break
      }
      if (attempt <= max_retries) {
        if (verbose)
          message(sprintf("[llm_kg_pipeline] [%s] attempt %d failed; retrying in %.0fs...",
                            src, attempt, delay))
        Sys.sleep(delay); delay <- delay * 2
      } else {
        n_errors <- n_errors + 1L
        cat(sprintf("[%s]\t%s\n", src, conditionMessage(claims)),
             file = err_path, append = TRUE)
      }
    }
    if (success) n_processed <- n_processed + 1L
    if (verbose && (i %% 20L == 0L)) {
      message(sprintf("[llm_kg_pipeline] %d / %d processed (errors: %d)",
                       i, length(records), n_errors))
    }
  }

  if (verbose)
    message(sprintf("[llm_kg_pipeline] done -- processed=%d, skipped=%d, errors=%d.",
                     n_processed, n_skipped, n_errors))
  invisible(list(
    n_processed = n_processed,
    n_skipped   = n_skipped,
    n_errors    = n_errors,
    output_path = output_path,
    kg          = kg
  ))
}
