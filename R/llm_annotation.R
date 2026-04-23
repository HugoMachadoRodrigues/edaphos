# Pillar 1 — Gold-standard annotation tooling (v1.8.1).
#
# Two-phase workflow for scaling the Cerrado gold-standard beyond the
# 72-claim seed shipped in v1.8.0:
#
#   Phase 1 (pre-annotation)  — the LLM (Gemma 4 by default) reads each
#     abstract and produces a draft set of (cause, effect, polarity,
#     confidence) claims.  A deterministic simulator fallback keeps
#     the pipeline usable without Ollama.
#
#   Phase 2 (human review)    — a Shiny app presents one abstract at a
#     time, lets the annotator accept / edit / reject each draft
#     claim, and lets them add claims that the LLM missed.  Every
#     abstract save writes to disk, so interrupted sessions resume
#     exactly where they left off.
#
# The exported API is five functions:
#
#   llm_annotation_vocabulary() : the canonical pedometric vocabulary
#   llm_preannotate()           : corpus -> draft JSONL
#   llm_annotation_launch()     : launch Shiny review app
#   llm_annotation_validate()   : schema + vocab compliance check
#   llm_annotation_export()     : reviewed JSONL -> gold-standard JSONL

# ---------------------------------------------------------------------------
# Canonical vocabulary
# ---------------------------------------------------------------------------

#' Canonical pedometric vocabulary for LLM-KG claims
#'
#' Controlled list of variable names used by the prompt template in
#' [`causal_llm_extract()`] and by the gold-standard annotation
#' tooling.  Keeping these labels stable across thousands of abstracts
#' is essential for computing precision / recall against the gold
#' standard: free-form labels like `"tree_cover"` vs `"tree cover"`
#' vs `"vegetation_cover"` would artificially depress matching
#' accuracy.
#'
#' @return Character vector of canonical variable names.
#' @export
#' @examples
#' head(llm_annotation_vocabulary(), 10)
llm_annotation_vocabulary <- function() {
  c(
    # Climate
    "precipitation", "mean_annual_precipitation",
    "temperature",   "mean_annual_temperature",
    # Topography
    "elevation", "slope", "aspect", "twi",
    # Texture / physics
    "clay", "sand", "silt", "bulk_density",
    # Chemistry
    "soc", "ph", "cec", "parent_material",
    # Biological / land-use
    "vegetation", "ndvi", "land_use", "fire_frequency",
    # Processes
    "erosion", "weathering"
  )
}

# ---------------------------------------------------------------------------
# JSONL helpers (shared)
# ---------------------------------------------------------------------------

.jsonl_read <- function(path) {
  stopifnot(file.exists(path))
  lns <- readLines(path, warn = FALSE)
  lns <- lns[nzchar(trimws(lns))]
  lapply(lns, jsonlite::fromJSON, simplifyVector = TRUE)
}

.jsonl_write <- function(records, path) {
  if (!dir.exists(dirname(path)))
    dir.create(dirname(path), recursive = TRUE)
  con <- file(path, "w")
  on.exit(close(con), add = TRUE)
  for (r in records) {
    writeLines(
      jsonlite::toJSON(r, dataframe = "rows",
                        auto_unbox = TRUE, null = "null"),
      con
    )
  }
  invisible(path)
}

.record_hash <- function(rec) {
  body <- paste(
    rec$abstract_id %||% "",
    substr(rec$abstract_text %||% "", 1, 200)
  )
  # Stable MD5 of abstract id + first 200 chars
  tryCatch(digest::digest(body, algo = "md5"),
            error = function(e) substr(rec$abstract_id %||% "", 1, 8))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------------------
# Pre-annotation
# ---------------------------------------------------------------------------

#' Pre-annotate a corpus with an LLM to produce draft claims
#'
#' Runs [`causal_llm_extract()`] (real Ollama / OpenAI / Anthropic) or
#' the deterministic [`llm_benchmark_simulate()`] fallback over every
#' abstract in the corpus, and writes a **draft JSONL** in the same
#' schema as `cerrado_gold_standard_v1.jsonl` but with `claims`
#' marked `status = "draft"` so the Shiny reviewer can distinguish
#' machine-generated entries from human-added ones.
#'
#' @param corpus Either a path to a JSONL file with one record per line
#'   (records must have `abstract_id` and `abstract_text`), or a list
#'   of records already in memory.
#' @param backend One of `"ollama"`, `"openai"`, `"anthropic"`,
#'   `"simulator"`.  When `"simulator"` the function uses
#'   [`llm_benchmark_simulate()`] against a pseudo-gold-standard
#'   derived from the abstract's first sentence -- useful for demos
#'   and CI builds without API access.  Defaults to `"ollama"` with
#'   `gemma4:latest`.
#' @param model Optional model id.  Defaults to `"gemma4:latest"` for
#'   Ollama.
#' @param output_path Path to write the draft JSONL.
#' @param cache_dir Optional directory for per-record JSON caches.
#'   When set, re-running the function over the same corpus
#'   short-circuits to cached extractions, so interrupted jobs resume
#'   exactly where they left off.  Defaults to `NULL` (no cache).
#' @param max_abstracts Optional integer cap on how many abstracts to
#'   process (useful for staged runs).
#' @param verbose Logical; print per-abstract progress.
#' @param ... Forwarded to [`causal_llm_extract()`].
#' @return Invisibly, the list of records written.
#' @export
llm_preannotate <- function(corpus,
                              backend = c("ollama", "openai",
                                           "anthropic", "simulator"),
                              model = NULL,
                              output_path = "cerrado_draft_gold.jsonl",
                              cache_dir = NULL,
                              max_abstracts = NULL,
                              verbose = TRUE,
                              ...) {
  backend <- match.arg(backend)
  # Load corpus
  if (is.character(corpus) && length(corpus) == 1L) {
    records <- .jsonl_read(corpus)
  } else {
    stopifnot(is.list(corpus))
    records <- corpus
  }
  if (!is.null(max_abstracts)) {
    records <- records[seq_len(min(as.integer(max_abstracts),
                                     length(records)))]
  }

  if (!is.null(cache_dir) && !dir.exists(cache_dir))
    dir.create(cache_dir, recursive = TRUE)

  # Default model by backend
  if (is.null(model)) {
    model <- switch(
      backend,
      ollama    = "gemma4:latest",
      openai    = "gpt-4o-mini",
      anthropic = "claude-sonnet-4-5",
      simulator = "simulator"
    )
  }

  drafts <- vector("list", length(records))
  for (i in seq_along(records)) {
    r <- records[[i]]
    stopifnot(!is.null(r$abstract_id), !is.null(r$abstract_text))
    if (verbose) message(sprintf("  [%d/%d] %s", i, length(records),
                                   r$abstract_id))

    # Check cache
    cache_hit <- FALSE
    if (!is.null(cache_dir)) {
      h <- .record_hash(r)
      cache_path <- file.path(cache_dir, paste0(h, ".json"))
      if (file.exists(cache_path)) {
        claims <- jsonlite::fromJSON(cache_path, simplifyVector = TRUE)
        cache_hit <- TRUE
      }
    }

    if (!cache_hit) {
      # Extract claims
      extracted <- tryCatch({
        if (backend == "simulator") {
          .llm_simulator_on_abstract(r)
        } else {
          causal_llm_extract(
            text    = r$abstract_text,
            backend = backend,
            model   = model,
            ...
          )
        }
      }, error = function(e) {
        message(sprintf("    [warn] extraction failed: %s",
                         conditionMessage(e)))
        data.frame(cause = character(), effect = character(),
                    confidence = numeric(), stringsAsFactors = FALSE)
      })

      if (nrow(extracted) == 0L) {
        claims <- data.frame(
          cause      = character(),
          effect     = character(),
          polarity   = character(),
          confidence = numeric(),
          rationale  = character(),
          status     = character(),
          stringsAsFactors = FALSE
        )
      } else {
        # Normalise to schema
        ext <- extracted
        if (!"polarity"  %in% names(ext)) ext$polarity  <- "+"
        if (!"rationale" %in% names(ext)) ext$rationale <- NA_character_
        ext$status <- "draft"
        claims <- ext[, c("cause", "effect", "polarity",
                           "confidence", "rationale", "status"),
                       drop = FALSE]
      }
      # Cache
      if (!is.null(cache_dir)) {
        jsonlite::write_json(claims, cache_path, pretty = TRUE)
      }
    }

    r$claims  <- claims
    r$backend <- backend
    r$model   <- model
    r$pre_annotated_at <- Sys.time()
    drafts[[i]] <- r
  }

  .jsonl_write(drafts, output_path)
  if (verbose) message(sprintf(
    "=== Draft written to %s (%d abstracts, %d claims) ===",
    output_path, length(drafts),
    sum(vapply(drafts, function(x) nrow(x$claims), integer(1L)))
  ))
  invisible(drafts)
}

# Simulator that fabricates a plausible claim list from an abstract
# (used only when backend == "simulator" so the pipeline runs in CI
# without Ollama).  Does NOT understand the abstract; uses the first
# sentence to randomly pair vocabulary terms.
.llm_simulator_on_abstract <- function(record) {
  vocab <- llm_annotation_vocabulary()
  id_chr <- as.character(record$abstract_id %||% "X")
  set.seed(abs(sum(utf8ToInt(id_chr))))
  n_claims <- sample(2:5, 1L)
  causes  <- sample(vocab, n_claims, replace = TRUE)
  effects <- sample(vocab, n_claims, replace = TRUE)
  keep <- causes != effects
  causes  <- causes[keep]
  effects <- effects[keep]
  data.frame(
    cause      = causes,
    effect     = effects,
    polarity   = sample(c("+", "-"), length(causes), replace = TRUE),
    confidence = round(stats::runif(length(causes), 0.4, 0.95), 3),
    rationale  = rep(NA_character_, length(causes)),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

#' Validate a gold-standard JSONL file
#'
#' Checks every record for required fields, every claim for required
#' fields, that `cause` / `effect` belong to the canonical vocabulary
#' (unless `strict_vocab = FALSE`), that `polarity` is `"+"` or
#' `"-"`, and that `confidence` is in `[0, 1]`.
#'
#' @param path Path to the JSONL file.
#' @param strict_vocab Logical; if `TRUE` (default), flag any `cause`
#'   or `effect` outside [`llm_annotation_vocabulary()`].
#' @return Named list with `ok` (logical), `errors` (character vector)
#'   and `summary` (data frame with per-record counts).
#' @export
llm_annotation_validate <- function(path, strict_vocab = TRUE) {
  records <- .jsonl_read(path)
  vocab <- llm_annotation_vocabulary()
  errors <- character(0)
  summary_rows <- list()

  for (i in seq_along(records)) {
    r <- records[[i]]
    rid <- r$abstract_id %||% paste0("<record ", i, ">")

    req <- c("abstract_id", "abstract_text", "claims")
    missing_req <- setdiff(req, names(r))
    if (length(missing_req) > 0L) {
      errors <- c(errors, sprintf(
        "%s: missing required field(s) %s",
        rid, paste(missing_req, collapse = ", ")
      ))
      next
    }

    cl <- r$claims
    n_claims <- if (is.data.frame(cl)) nrow(cl) else
                 if (is.list(cl)) length(cl) else 0L

    if (n_claims > 0L) {
      cl_df <- if (is.data.frame(cl)) cl else do.call(rbind, lapply(cl,
                  as.data.frame, stringsAsFactors = FALSE))
      req_cl <- c("cause", "effect", "polarity", "confidence")
      miss_cl <- setdiff(req_cl, names(cl_df))
      if (length(miss_cl) > 0L) {
        errors <- c(errors, sprintf(
          "%s: claims missing field(s) %s", rid,
          paste(miss_cl, collapse = ", ")
        ))
      } else {
        # Polarity
        bad_pol <- !cl_df$polarity %in% c("+", "-")
        if (any(bad_pol)) errors <- c(errors, sprintf(
          "%s: %d claim(s) with invalid polarity", rid, sum(bad_pol)
        ))
        # Confidence range
        bad_conf <- is.na(cl_df$confidence) |
          cl_df$confidence < 0 | cl_df$confidence > 1
        if (any(bad_conf)) errors <- c(errors, sprintf(
          "%s: %d claim(s) with confidence outside [0,1]", rid,
          sum(bad_conf)
        ))
        # Vocabulary
        if (strict_vocab) {
          bad_vocab <- !(cl_df$cause %in% vocab & cl_df$effect %in% vocab)
          if (any(bad_vocab)) errors <- c(errors, sprintf(
            "%s: %d claim(s) with non-canonical vocabulary", rid,
            sum(bad_vocab)
          ))
        }
      }
    }
    summary_rows[[i]] <- data.frame(
      abstract_id = rid, n_claims = n_claims,
      stringsAsFactors = FALSE
    )
  }
  list(ok = length(errors) == 0L, errors = errors,
        summary = do.call(rbind, summary_rows))
}

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

#' Export a reviewed JSONL into the canonical gold-standard format
#'
#' Drops claims flagged as `rejected`, drops draft-only claims that
#' have not been reviewed, removes the internal `status` field, and
#' re-validates the result.
#'
#' @param reviewed_path Path to the reviewed JSONL (output of the
#'   Shiny reviewer).
#' @param output_path Path for the cleaned gold-standard JSONL.
#' @param include_rationale Logical; keep the `rationale` free-text
#'   field (default `TRUE`).
#' @return Invisibly, the list of records written.
#' @export
llm_annotation_export <- function(reviewed_path, output_path,
                                    include_rationale = TRUE) {
  records <- .jsonl_read(reviewed_path)
  out <- lapply(records, function(r) {
    cl <- r$claims
    if (is.data.frame(cl) && nrow(cl) > 0L) {
      keep <- !(cl$status %in% c("rejected", "draft"))
      # "draft" means the user left it untouched -- conservative:
      # exclude these from the final gold standard.
      cl <- cl[keep, , drop = FALSE]
      cl$status <- NULL
      if (!include_rationale && "rationale" %in% names(cl))
        cl$rationale <- NULL
    }
    r$claims <- cl
    r
  })
  .jsonl_write(out, output_path)
  n_claims <- sum(vapply(out,
                          function(x) if (is.data.frame(x$claims))
                                        nrow(x$claims) else 0L,
                          integer(1L)))
  message(sprintf(
    "=== Exported gold standard: %s (%d abstracts, %d claims) ===",
    output_path, length(out), n_claims
  ))
  invisible(out)
}

# ---------------------------------------------------------------------------
# Shiny launcher
# ---------------------------------------------------------------------------

#' Launch the interactive gold-standard review app
#'
#' Opens a Shiny application that presents every abstract in the draft
#' JSONL and lets the annotator accept / edit / reject each LLM-drafted
#' claim, plus add any claim the LLM missed.  Writes to `output_path`
#' after every abstract, so interrupted sessions resume exactly where
#' they left off.
#'
#' **Keyboard shortcuts** (when `keyboard_shortcuts = TRUE`):
#' `a` — accept all and next · `r` — reject all · `n` — next abstract
#' (save) · `p` — previous · `+` — add claim · `1..9` — toggle
#' accept on claim *n*.
#'
#' @param draft_path Path to the draft JSONL produced by
#'   [`llm_preannotate()`].
#' @param output_path Where to write the reviewed JSONL.  Defaults to
#'   `draft_path` (in-place review).
#' @param keyboard_shortcuts Logical; enable keyboard bindings.
#' @param port Optional integer port for the Shiny app.
#' @return Called for its side-effect (launches app); invisibly
#'   returns the path of the reviewed JSONL.
#' @export
llm_annotation_launch <- function(draft_path,
                                    output_path = NULL,
                                    keyboard_shortcuts = TRUE,
                                    port = NULL) {
  stopifnot(file.exists(draft_path))
  if (is.null(output_path)) output_path <- draft_path
  app_dir <- system.file("shiny-apps", "annotation", package = "edaphos")
  if (!nzchar(app_dir) || !dir.exists(app_dir)) {
    # dev mode -- running via devtools::load_all
    app_dir <- file.path("inst", "shiny-apps", "annotation")
    if (!dir.exists(app_dir)) stop(
      "annotation Shiny app directory not found",
      call. = FALSE
    )
  }
  for (p in c("shiny", "DT", "bslib", "shinyjs")) {
    if (!requireNamespace(p, quietly = TRUE))
      stop(sprintf("Install '%s' to launch the annotation app.", p),
            call. = FALSE)
  }
  # Pass paths via options consumed by app.R
  old_opts <- options(
    edaphos.annotation.draft  = normalizePath(draft_path),
    edaphos.annotation.output = normalizePath(output_path, mustWork = FALSE),
    edaphos.annotation.keyboard = isTRUE(keyboard_shortcuts)
  )
  on.exit(options(old_opts), add = TRUE)
  if (is.null(port)) {
    shiny::runApp(app_dir, launch.browser = interactive())
  } else {
    shiny::runApp(app_dir, port = port, launch.browser = interactive())
  }
  invisible(output_path)
}
