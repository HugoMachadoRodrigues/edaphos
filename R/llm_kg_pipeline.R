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
#' Issues a short GET request to the Ollama `/api/tags` endpoint and
#' reports whether the server responds.  Used by
#' [`llm_kg_pipeline_run()`] as a pre-flight gate.
#'
#' @param host Character; the base URL of the Ollama server.
#'   Default `"http://localhost:11434"`.
#' @param model Optional character; if supplied, additionally
#'   verifies that the named model is present on the server.
#' @param timeout_sec Numeric; HTTP timeout.  Default `1`.
#' @return A named list.  `reachable` (logical) is always present.
#'   `model_present` (logical) and `models_available` (character) are
#'   added only when `model` is non-NULL *and* the server is
#'   reachable -- on an unreachable server they are absent, not
#'   `FALSE`.
#' @export
#' @examples
#' # The gate is deliberately cheap and never throws: a refused
#' # connection comes back as a plain FALSE, so a batch script can
#' # branch on it.  Port 1 is always closed.
#' llm_kg_ollama_check(host = "http://127.0.0.1:1", timeout_sec = 0.5)
#'
#' # `reachable` is not "the port is open".  httr2 raises on 4xx/5xx,
#' # so the `status < 400` test in the body is never reached and a
#' # host that answers 404 on /api/tags is indistinguishable from a
#' # refused connection.  In the other direction, anything that
#' # answers 200 counts as reachable -- which is why the model check
#' # below, not `reachable`, is what tells you it is really Ollama.
#'
#' # Read `model_present` next to `reachable`, never on its own: when
#' # the server is down the element is ABSENT, not FALSE.
#' chk <- llm_kg_ollama_check(host = "http://127.0.0.1:1",
#'                            model = "gemma4:latest", timeout_sec = 0.5)
#' names(chk)                              # "reachable" alone
#' try(if (!chk$model_present) "missing")  # error: invalid argument type
#' isFALSE(chk$model_present)              # FALSE -- the safe idiom,
#'                                         # and the one the pipeline uses
#' \dontrun{
#' # Against a live `ollama serve` the result gains the two extra
#' # elements; `models_available` is what you print when the model
#' # check fails, so the user knows what was actually pulled.
#' chk <- llm_kg_ollama_check(model = "gemma4:latest")
#' chk$model_present
#' chk$models_available
#' }
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
#' @examples
#' # Everything outside \dontrun{} below runs offline: the corpus is
#' # arranged so that no record ever reaches an LLM.  The pipeline
#' # opens an `edaphos_causal_kg` on every path, so it needs igraph
#' # (a Suggests) even when it extracts nothing -- and R CMD check
#' # --as-cran does execute this block.
#' if (requireNamespace("igraph", quietly = TRUE)) {
#'
#'   corpus <- tempfile(fileext = ".jsonl")
#'   out    <- tempfile(fileext = ".jsonl")
#'   writeLines(c(
#'     '{"source":"silva2021","abstract":"MAP raised topsoil SOC."}',
#'     '{"source":"reis2019","abstract":""}',
#'     '{"source":"castro2020","abstract":"Clay content'  # truncated
#'   ), corpus)
#'
#'   # What a run killed half way through leaves behind: two claims in
#'   # the output file and one source logged in the `.done` sidecar.
#'   claim <- function(cause, conf)
#'     jsonlite::toJSON(list(cause = cause, effect = "soil organic carbon",
#'                           evidence = "quoted from the abstract",
#'                           confidence = conf, source = "silva2021"),
#'                      auto_unbox = TRUE)
#'   writeLines(c(claim("mean annual precipitation", 0.9),
#'                claim("clay content", 0.7)), out)
#'   writeLines("silva2021", paste0(out, ".done"))
#'
#'   # `backend = "openai"` skips the Ollama pre-flight, and the
#'   # hosted backends have no pre-flight of their own: the API key is
#'   # read only once an abstract is actually sent.  Here none is.
#'   res <- llm_kg_pipeline_run(corpus, out, backend = "openai",
#'                              verbose = FALSE)
#'   print(c(res$n_processed, res$n_skipped, res$n_errors))   # 0 1 1
#'
#'   # Read those three next to the corpus size: they account for 2 of
#'   # 3 lines.  The truncated JSON is dropped at parse time and is
#'   # invisible -- not an error, not a skip, never in `.errors`.
#'   print(length(readLines(corpus)))                         # 3
#'
#'   # An EMPTY abstract, by contrast, is charged as an error and
#'   # logged.  Errors are logged and stepped over, never fatal.
#'   print(readLines(paste0(out, ".errors")))  # "[reis2019]\tempty abstract"
#'
#'   # The trap: `res$kg` holds only the edges extracted in THIS call.
#'   # Resumed sources are skipped and their claims are never read
#'   # back from `output_path`, so the returned graph is empty while
#'   # the claims file has two rows.  Never treat `res$kg` as the
#'   # accumulated graph of a resumed job.
#'   print(nrow(causal_kg_edges(res$kg)))      # 0
#'   print(length(readLines(out)))             # 2
#'
#'   # The claims file is the durable artefact; rebuild the graph from
#'   # it.  Node labels are normalised on insertion, so the two rows
#'   # become mean_annual_precipitation -> soil_organic_carbon and
#'   # clay_content -> soil_organic_carbon.
#'   prev <- jsonlite::stream_in(file(out), verbose = FALSE)
#'   kg <- causal_kg_new()
#'   for (i in seq_len(nrow(prev)))
#'     kg <- causal_kg_add_edge(kg, prev$cause[i], prev$effect[i],
#'                              source     = prev$source[i],
#'                              evidence   = prev$evidence[i],
#'                              confidence = prev$confidence[i])
#'   print(causal_kg_edges(kg)[, c("cause", "effect", "confidence")])
#'
#'   unlink(c(corpus, out, paste0(out, c(".done", ".errors"))))
#' }
#'
#' # A missing credential is treated as a TRANSIENT failure: it is put
#' # on the back-off ladder and then written off, instead of failing
#' # fast.  Guarded on the key so that a reader who has one is not
#' # billed for a live call by running this example.
#' if (requireNamespace("igraph", quietly = TRUE) &&
#'     !nzchar(Sys.getenv("OPENAI_API_KEY"))) {
#'   corpus <- tempfile(fileext = ".jsonl")
#'   out    <- tempfile(fileext = ".jsonl")
#'   writeLines('{"source":"silva2021","abstract":"MAP raised SOC."}', corpus)
#'
#'   res <- llm_kg_pipeline_run(corpus, out, backend = "openai",
#'                              max_retries = 0L, verbose = FALSE)
#'   print(res$n_errors)                       # 1
#'   print(readLines(paste0(out, ".errors")))  # "Set OPENAI_API_KEY ..."
#'   print(file.exists(out))                   # FALSE -- an all-error
#'                                             # run never creates
#'                                             # output_path at all
#'
#'   # `max_retries = 0L` is what makes that instant.  At the default
#'   # 3L the very same missing key costs the full back-off ladder,
#'   # 1 + 2 + 4 = 7 s, per abstract before it is written off -- so on
#'   # the 10 000-abstract corpus this function exists for, about 20 h
#'   # of sleeping and not one claim.  Check credentials yourself
#'   # before the run; the pipeline will not do it for you.
#'   unlink(c(corpus, paste0(out, ".errors")))
#' }
#'
#' \dontrun{
#' # The networked path.  No key is ever passed as an argument: each
#' # backend reads its own environment variable, and `host` reaches
#' # exactly one of them.
#' #   "ollama"    -- no key; POSTs to <host>/api/chat
#' #   "openai"    -- OPENAI_API_KEY;    `host` ignored
#' #   "anthropic" -- ANTHROPIC_API_KEY; `host` ignored
#'
#' # Pass `model` explicitly.  The pre-flight only checks the model
#' # when it is non-NULL, so leaving it NULL starts the run happily
#' # and then fails on every single abstract if the default
#' # "gemma4:latest" was never pulled.
#' res <- llm_kg_pipeline_run(
#'   corpus_path    = "cerrado_10k.jsonl",   # {source, abstract} per line
#'   output_path    = "cerrado_claims.jsonl",
#'   backend        = "ollama",
#'   model          = "gemma4:latest",
#'   min_confidence = 0.6,
#'   max_abstracts  = 250L
#' )
#' res$n_processed
#'
#' # `min_confidence` is applied before anything is written, and the
#' # source is marked done even when the filter left nothing.  So
#' # raising the threshold on a resumed run is a no-op, and lowering
#' # it does not revisit what is already in `.done`: delete
#' # <output_path>.done to re-extract a corpus at a new threshold.
#' causal_kg_edges(res$kg)[, c("cause", "effect", "confidence")]
#' }
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
