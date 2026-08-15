# Pillar 1 -- Gold-standard annotation tooling (v1.8.1).
#
# Two-phase workflow for scaling the Cerrado gold-standard beyond the
# 72-claim seed shipped in v1.8.0:
#
#   Phase 1 (pre-annotation)  -- the LLM (Gemma 4 by default) reads each
#     abstract and produces a draft set of (cause, effect, polarity,
#     confidence) claims.  A deterministic simulator fallback keeps
#     the pipeline usable without Ollama.
#
#   Phase 2 (human review)    -- a Shiny app presents one abstract at a
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
#'   `"simulator"`.  When `"simulator"` the function does not call an
#'   LLM at all: it seeds the RNG from `abstract_id` and pairs
#'   [`llm_annotation_vocabulary()`] terms at random, ignoring
#'   `abstract_text` entirely.  That keeps demos and CI builds
#'   runnable without API access, but the claims it produces carry no
#'   information about the abstract.  Defaults to `"ollama"` with
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
#' @examples
#' # Two abstracts in memory.  `abstract_id` and `abstract_text` are
#' # the only required fields; anything else the record carries (year,
#' # doi, topic) is passed straight through into the draft.
#' corpus <- list(
#'   list(abstract_id   = "CER_A",
#'        abstract_text = "Rainfall raised topsoil SOC on 520 Oxisols.",
#'        year = 2021),
#'   list(abstract_id   = "CER_B",
#'        abstract_text = "Fire frequency cut vegetation cover on sands.",
#'        year = 2019)
#' )
#' draft <- file.path(tempdir(), "cerrado_draft.jsonl")
#' d <- llm_preannotate(corpus, backend = "simulator",
#'                      output_path = draft, verbose = FALSE)
#' vapply(d, function(r) nrow(r$claims), integer(1))
#'
#' # Every drafted claim is stamped status = "draft".  That stamp is
#' # what makes llm_annotation_export() throw it away: nothing reaches
#' # the gold standard until a human changes it in the reviewer.
#' d[[1]]$claims[1:2, c("cause", "effect", "polarity", "status")]
#'
#' # The simulator is a placeholder, not a weak extractor.  Draft the
#' # first 5 abstracts of the bundled gold standard and score its
#' # (cause, effect) pairs against the human annotation: 17 drafted,
#' # 17 true, exactly 1 pair in common.  A simulator run is never a
#' # measurement of pre-annotation quality.
#' gs <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
#'                   package = "edaphos")
#' sim <- llm_preannotate(gs, backend = "simulator", max_abstracts = 5,
#'                        output_path = tempfile(fileext = ".jsonl"),
#'                        verbose = FALSE)
#' edges <- function(recs) unlist(lapply(recs,
#'   function(r) paste(r$claims$cause, r$claims$effect)))
#' truth <- edges(lapply(readLines(gs, warn = FALSE)[1:5], jsonlite::fromJSON))
#' c(true = length(truth), drafted = length(edges(sim)),
#'   hits = length(intersect(truth, edges(sim))))
#'
#' # Note what that run also did: it overwrote the human `claims` of
#' # CER_01..CER_05 with machine drafts.  Pre-annotate a corpus file,
#' # never a gold standard you want to keep.
#'
#' # The simulator keys on `abstract_id` alone, so its draft is stable
#' # across sessions -- but it does that with a bare set.seed(), which
#' # silently resets the CALLER's stream.  Draw what you need before
#' # the call, or re-seed after it.
#' set.seed(42); before <- runif(1)
#' set.seed(42)
#' invisible(llm_preannotate(corpus, backend = "simulator", verbose = FALSE,
#'                           output_path = tempfile(fileext = ".jsonl")))
#' c(before = before, after = runif(1))
#'
#' # `cache_dir` keys on abstract_id plus the FIRST 200 CHARACTERS of
#' # the text, so fixing a typo past character 200 is a cache hit and
#' # silently reuses the stale extraction.  Two texts, one cache entry;
#' # edit the opening instead and a second entry appears.
#' if (requireNamespace("digest", quietly = TRUE)) {
#'   head200 <- paste(rep("Cerrado Oxisol rainfall carbon", 12), collapse = " ")
#'   cache <- file.path(tempdir(), "preann_cache")
#'   run1 <- function(txt) llm_preannotate(
#'     list(list(abstract_id = "CER_A", abstract_text = txt)),
#'     backend = "simulator", cache_dir = cache, verbose = FALSE,
#'     output_path = tempfile(fileext = ".jsonl"))
#'   invisible(run1(paste(head200, "original tail")))
#'   invisible(run1(paste(head200, "a completely different tail")))
#'   n_tail <- length(list.files(cache))
#'   invisible(run1(paste("DIFFERENT OPENING", head200)))
#'   print(c(after_tail_edit = n_tail,
#'           after_opening_edit = length(list.files(cache))))
#' }
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
#' @examples
#' gs <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
#'                   package = "edaphos")
#' v <- llm_annotation_validate(gs)
#' v$ok
#'
#' # The v1 seed: 30 abstracts, 72 claims, 1 to 5 claims each, clean
#' # under the strict vocabulary.
#' c(records = nrow(v$summary), claims = sum(v$summary$n_claims))
#' range(v$summary$n_claims)
#'
#' # A file with one of each failure mode.  The second record has no
#' # `claims` key at all.
#' bad <- file.path(tempdir(), "bad.jsonl")
#' writeLines(c(
#'   paste0('{"abstract_id":"BAD_01","abstract_text":"Tree cover raised SOC.",',
#'          '"claims":[{"cause":"tree_cover","effect":"soc",',
#'          '"polarity":"positive","confidence":0.8},',
#'          '{"cause":"clay","effect":"soc","polarity":"+",',
#'          '"confidence":1.4}]}'),
#'   '{"abstract_id":"BAD_02","abstract_text":"No claims field at all."}'
#' ), bad)
#' llm_annotation_validate(bad)$errors
#'
#' # `strict_vocab = FALSE` retires the vocabulary error only -- the
#' # polarity and confidence checks always run.  Use it while a new
#' # term like "tree_cover" is still being argued about, not to make a
#' # file pass.
#' llm_annotation_validate(bad, strict_vocab = FALSE)$errors
#'
#' # Read `summary` next to `errors`, never alone: a record that fails
#' # the required-field check is skipped before it is counted, so
#' # BAD_02 has no row and nrow(summary) is not the file's length.
#' c(rows_in_summary = nrow(llm_annotation_validate(bad)$summary),
#'   lines_in_file   = length(readLines(bad, warn = FALSE)))
#'
#' # And `ok` is a schema verdict, not a coverage one.  An export that
#' # dropped every claim validates perfectly, so gate a deposit on the
#' # claim count as well.
#' empty <- file.path(tempdir(), "empty.jsonl")
#' writeLines('{"abstract_id":"E_01","abstract_text":"x","claims":[]}', empty)
#' e <- llm_annotation_validate(empty)
#' e$ok
#' sum(e$summary$n_claims)
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
#' @examples
#' n_claims <- function(recs) sum(vapply(recs, function(r)
#'   if (is.data.frame(r$claims)) nrow(r$claims) else 0L, integer(1)))
#'
#' draft <- system.file("extdata", "cerrado_gold_standard_v1_draft.jsonl",
#'                      package = "edaphos")
#'
#' # The bundled draft holds 93 machine claims, every one still at
#' # status = "draft".  Export keeps NONE of them, and says so: 30
#' # abstracts, 0 claims.  "draft" means no human ever looked, and an
#' # unreviewed claim is not gold-standard evidence.
#' kept <- llm_annotation_export(draft, file.path(tempdir(), "hollow.jsonl"))
#' n_claims(kept)
#'
#' # Accept the first claim of each abstract and re-export.  Only the
#' # `status` string decides -- nothing else in the record matters.
#' reviewed <- file.path(tempdir(), "reviewed.jsonl")
#' writeLines(sub('"status":"draft"', '"status":"accepted"',
#'                readLines(draft, warn = FALSE), fixed = TRUE), reviewed)
#' n_claims(llm_annotation_export(reviewed, file.path(tempdir(), "g2.jsonl")))
#'
#' # Back-compat trap in the other direction: the hand-annotated v1
#' # seed has no `status` column at all, and those claims are treated
#' # as already accepted, so all 72 survive.  A file with no statuses
#' # keeps everything; a file with only draft statuses keeps nothing.
#' gs <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
#'                   package = "edaphos")
#' once <- file.path(tempdir(), "once.jsonl")
#' c(once  = n_claims(llm_annotation_export(gs, once)),
#'   twice = n_claims(llm_annotation_export(
#'             once, file.path(tempdir(), "twice.jsonl"))))
#'
#' # Idempotent because `status` is stripped on the way out -- which
#' # also means you cannot re-review an exported file.  Keep the
#' # reviewed JSONL; the export is a derived artefact.
#'
#' # `include_rationale = FALSE` drops the free-text justification,
#' # leaving the four fields llm_annotation_validate() requires.
#' names(llm_annotation_export(gs, file.path(tempdir(), "no_rat.jsonl"),
#'                             include_rationale = FALSE)[[1]]$claims)
llm_annotation_export <- function(reviewed_path, output_path,
                                    include_rationale = TRUE) {
  records <- .jsonl_read(reviewed_path)
  out <- lapply(records, function(r) {
    cl <- r$claims
    if (is.data.frame(cl) && nrow(cl) > 0L) {
      # Back-compat: claims with no `status` column (e.g. v1 hand-
      # annotated gold-standard) are treated as already-accepted.
      if (!"status" %in% names(cl)) {
        cl$status <- "accepted"
      }
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
# Zenodo packaging
# ---------------------------------------------------------------------------

#' Package a reviewed gold-standard into a Zenodo-ready deposit bundle
#'
#' Generates a self-contained directory (and optionally a zip archive)
#' that can be uploaded to Zenodo to mint a permanent DOI for the
#' gold-standard.  Bundle contents:
#'
#' - `gold_standard.jsonl`   -- cleaned gold-standard (drafts / rejected
#'                              removed, identical to
#'                              [`llm_annotation_export()`] output).
#' - `kg.ttl`                -- RDF 1.1 Turtle representation of the
#'                              aggregated KG built by treating each
#'                              accepted claim as a directed edge.
#' - `metadata.json`         -- DataCite-compatible metadata ready for
#'                              the Zenodo REST API.  Also usable as
#'                              a source for a manual upload via the
#'                              Zenodo web UI.
#' - `README.md`             -- Human-readable description with schema,
#'                              annotator, extractor, date, counts,
#'                              citation.
#'
#' The function does NOT upload to Zenodo automatically (Zenodo requires
#' a personal access token which should never be hard-coded).  After the
#' bundle is built the user uploads the zip / files manually at
#' <https://zenodo.org/deposit/new> and records the minted DOI back
#' into the package's CITATION.cff / .zenodo.json.
#'
#' @param reviewed_path Path to the reviewed JSONL.
#' @param output_dir Directory to create.  Will be made if it doesn't
#'   exist.  Existing contents are overwritten.
#' @param title Deposit title (will appear on Zenodo).
#' @param authors Data frame with one row per creator and all four of
#'   `family_name`, `given_name`, `orcid`, `affiliation` as columns.
#'   The `orcid` and `affiliation` *values* may be `NA` (the field is
#'   then omitted from that creator) but the *columns* must be
#'   present, or creator assembly fails.  Defaults to a single
#'   hard-coded entry for the package maintainer.
#' @param description Free-text description (HTML allowed).  Defaults
#'   to a short summary including abstract / claim counts.
#' @param keywords Character vector of keyword tags.
#' @param license Licence identifier (default `"CC-BY-4.0"`).
#' @param version Optional version string to embed in metadata.json.
#' @param zip Logical; when `TRUE` (default), also produce a
#'   `<output_dir>.zip` alongside the directory.
#' @return Invisibly, the path to the created directory.
#' @export
#' @examples
#' gs <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
#'                   package = "edaphos")
#' bundle <- file.path(tempdir(), "cerrado_kg_deposit")
#'
#' # `zip = FALSE` because utils::zip() shells out to an external
#' # `zip` executable that is not present everywhere.  Pass `version`
#' # explicitly too: it defaults to Sys.Date(), so metadata.json and
#' # README.md otherwise differ on every run and the bundle is not
#' # reproducible.
#' llm_annotation_to_zenodo(gs, bundle,
#'                          title = "Cerrado gold-standard KG (v1)",
#'                          version = "1.0.0", zip = FALSE)
#' sort(list.files(bundle))
#'
#' # The 72 accepted claims become 72 reified rdf:Statement blocks,
#' # plus 30 eda:Abstract provenance nodes carrying title and year.
#' ttl <- readLines(file.path(bundle, "kg.ttl"), warn = FALSE)
#' c(statements = sum(grepl("a rdf:Statement", ttl, fixed = TRUE)),
#'   abstracts  = sum(grepl("a eda:Abstract", ttl, fixed = TRUE)))
#'
#' # The licence is lower-cased into metadata.json on purpose: that is
#' # the identifier the Zenodo REST API expects, not the SPDX spelling
#' # you passed in.
#' md <- jsonlite::fromJSON(file.path(bundle, "metadata.json"))
#' c(license = md$metadata$license, version = md$metadata$version)
#'
#' # Trap: this runs llm_annotation_export() internally, so a reviewed
#' # file whose claims are all still "draft" produces a bundle that
#' # SUCCEEDS, prints its usual banner, and contains zero statements.
#' # Check the count before you mint a DOI, not the exit status.
#' draft <- system.file("extdata", "cerrado_gold_standard_v1_draft.jsonl",
#'                      package = "edaphos")
#' hollow <- file.path(tempdir(), "hollow_deposit")
#' llm_annotation_to_zenodo(draft, hollow, version = "1.0.0", zip = FALSE)
#' sum(grepl("a rdf:Statement",
#'           readLines(file.path(hollow, "kg.ttl"), warn = FALSE), fixed = TRUE))
#'
#' # `authors` must carry all four columns.  NA values are fine and
#' # omit that field from the creator, but a missing COLUMN aborts
#' # part-way through, leaving a half-written directory behind.
#' who <- data.frame(family_name = c("Silva", "Costa"),
#'                   given_name  = c("Ana", "Bruno"),
#'                   orcid       = c("0000-0001-2345-6789", NA),
#'                   affiliation = c("Embrapa Cerrados", NA),
#'                   stringsAsFactors = FALSE)
#' authored <- file.path(tempdir(), "authored_deposit")
#' llm_annotation_to_zenodo(gs, authored, authors = who,
#'                          version = "1.0.0", zip = FALSE)
#' jsonlite::fromJSON(file.path(authored, "metadata.json"),
#'                    simplifyVector = FALSE)$metadata$creators
llm_annotation_to_zenodo <- function(reviewed_path,
                                       output_dir,
                                       title = "Cerrado gold-standard KG (edaphos)",
                                       authors = NULL,
                                       description = NULL,
                                       keywords = c("soil science",
                                                     "pedometrics",
                                                     "causal inference",
                                                     "knowledge graph",
                                                     "Cerrado"),
                                       license = "CC-BY-4.0",
                                       version = NULL,
                                       zip = TRUE) {
  stopifnot(file.exists(reviewed_path))
  if (dir.exists(output_dir)) unlink(output_dir, recursive = TRUE)
  dir.create(output_dir, recursive = TRUE)

  # -- 1. Cleaned gold-standard ----------------------------------------
  gs_path <- file.path(output_dir, "gold_standard.jsonl")
  llm_annotation_export(reviewed_path, gs_path)
  records <- .jsonl_read(gs_path)

  # -- 2. Aggregate KG -> Turtle ----------------------------------------
  ttl_path <- file.path(output_dir, "kg.ttl")
  .write_kg_ttl(records, ttl_path, title)

  # -- 3. DataCite metadata --------------------------------------------
  if (is.null(authors)) {
    authors <- data.frame(
      family_name = "Rodrigues", given_name = "Hugo",
      orcid       = "0000-0002-8070-8126",
      affiliation = NA_character_,
      stringsAsFactors = FALSE
    )
  }
  n_abs <- length(records)
  n_cl  <- sum(vapply(records, function(r) nrow(r$claims) %||% 0L,
                       integer(1L)))
  if (is.null(description)) {
    description <- sprintf(
      paste0("Causal-claim knowledge graph extracted from %d pedology ",
              "abstracts covering the Brazilian Cerrado biome. ",
              "%d expert-annotated claims in canonical pedometric ",
              "vocabulary (precipitation, temperature, clay, soc, ...). ",
              "Produced with the edaphos R package (Pillar 1) combining ",
              "LLM pre-annotation and human review. Schema: each claim ",
              "is a tuple (cause, effect, polarity, confidence, ",
              "rationale) grounded in a quoted fragment of the source ",
              "abstract."),
      n_abs, n_cl
    )
  }
  metadata <- list(
    metadata = list(
      title              = title,
      upload_type        = "dataset",
      description        = description,
      creators           = lapply(seq_len(nrow(authors)), function(i) {
        cr <- list(name = sprintf("%s, %s",
                                    authors$family_name[i],
                                    authors$given_name[i]))
        if (!is.na(authors$orcid[i]))        cr$orcid       <- authors$orcid[i]
        if (!is.na(authors$affiliation[i])) cr$affiliation <- authors$affiliation[i]
        cr
      }),
      keywords           = as.list(keywords),
      access_right       = "open",
      license            = tolower(license),
      related_identifiers = list(
        list(relation = "isSupplementTo",
             identifier = "10.5281/zenodo.19683708",
             resource_type = "software",
             scheme = "doi")
      ),
      version            = version %||% as.character(Sys.Date())
    )
  )
  jsonlite::write_json(metadata,
                        file.path(output_dir, "metadata.json"),
                        pretty = TRUE, auto_unbox = TRUE)

  # -- 4. README.md ----------------------------------------------------
  readme_lines <- c(
    sprintf("# %s", title),
    "",
    sprintf("**Abstracts:** %d  |  **Claims:** %d  |  **Date:** %s",
            n_abs, n_cl, as.character(Sys.Date())),
    "",
    "## Files",
    "- `gold_standard.jsonl` -- one JSON object per abstract with annotated",
    "  causal claims.",
    "- `kg.ttl` -- RDF 1.1 Turtle representation of the aggregated KG",
    "  (each claim is a reified `rdf:Statement` with confidence and",
    "  polarity predicates).",
    "- `metadata.json` -- DataCite-compatible metadata for the Zenodo API.",
    "",
    "## How to cite",
    "",
    "> Rodrigues, H. (2026). *Cerrado gold-standard KG (edaphos)*.",
    "> Zenodo.  [DOI to be assigned on deposit]",
    "",
    "## Provenance",
    "",
    sprintf("Generated on %s via the edaphos R package (Pillar 1,",
            format(Sys.time(), "%Y-%m-%d %H:%M UTC")),
    "`llm_preannotate` + `llm_annotation_launch` + `llm_annotation_to_zenodo`).",
    "Schema, vocabulary and export logic are reproducible from the",
    "edaphos source at https://github.com/HugoMachadoRodrigues/edaphos.",
    "",
    "## Licence",
    sprintf("This dataset is released under **%s**.", license)
  )
  writeLines(readme_lines, file.path(output_dir, "README.md"))

  # -- 5. Zip (optional) -----------------------------------------------
  if (isTRUE(zip)) {
    zip_path <- paste0(output_dir, ".zip")
    if (file.exists(zip_path)) file.remove(zip_path)
    # Use utils::zip via the parent dir so paths inside zip are relative
    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)
    setwd(dirname(output_dir))
    utils::zip(basename(zip_path), basename(output_dir),
                flags = "-r9Xq")
  }

  message(sprintf("=== Zenodo bundle ready: %s ===", output_dir))
  invisible(output_dir)
}

# Helper: write Turtle RDF from a list of annotated records
.write_kg_ttl <- function(records, path, title) {
  prefixes <- c(
    "@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .",
    "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .",
    "@prefix dct:  <http://purl.org/dc/terms/> .",
    "@prefix xsd:  <http://www.w3.org/2001/XMLSchema#> .",
    "@prefix eda:  <https://edaphos.org/ns/> .",
    "@prefix ped:  <https://edaphos.org/ns/pedometry/> .",
    ""
  )
  doc <- c(prefixes, sprintf('<> dct:title "%s" .', title), "")
  stmt_id <- 0L
  for (r in records) {
    cl <- r$claims
    if (is.null(cl) || !is.data.frame(cl) || nrow(cl) == 0L) next
    for (i in seq_len(nrow(cl))) {
      stmt_id <- stmt_id + 1L
      s <- sprintf("eda:stmt_%06d", stmt_id)
      abs <- sprintf("eda:abs_%s", r$abstract_id)
      cause  <- sprintf("ped:%s", cl$cause[i])
      effect <- sprintf("ped:%s", cl$effect[i])
      rationale <- gsub('"', '\\\\"', cl$rationale[i] %||% "", fixed = TRUE)
      doc <- c(doc,
        sprintf("%s a rdf:Statement ;", s),
        sprintf("  rdf:subject %s ;", cause),
        sprintf("  rdf:predicate eda:causes ;"),
        sprintf("  rdf:object %s ;", effect),
        sprintf("  eda:polarity \"%s\" ;", cl$polarity[i] %||% "+"),
        sprintf("  eda:confidence \"%.3f\"^^xsd:decimal ;",
                as.numeric(cl$confidence[i] %||% 0.5)),
        sprintf("  dct:source %s ;", abs),
        sprintf("  rdfs:comment \"%s\" .", rationale),
        ""
      )
    }
    if (!is.null(r$abstract_id)) {
      safe_title <- gsub('"', '\\\\"', r$title %||% "", fixed = TRUE)
      doc <- c(doc,
        sprintf("eda:abs_%s a eda:Abstract ;", r$abstract_id),
        sprintf("  dct:title \"%s\" ;", safe_title),
        if (!is.null(r$year))
          sprintf("  dct:issued \"%d\"^^xsd:gYear ;", as.integer(r$year))
          else NULL,
        if (!is.null(r$doi))
          sprintf("  dct:identifier \"%s\" .", r$doi)
          else "  .",
        ""
      )
    }
  }
  writeLines(doc, path)
  invisible(path)
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
#' `a` -- accept all and next | `r` -- reject all | `n` -- next abstract
#' (save) | `p` -- previous | `+` -- add claim | `1..9` -- toggle
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
#' @examples
#' \dontrun{
#' # Phase 2.  This blocks until the browser tab is closed, so it only
#' # makes sense from an interactive session, and it needs shiny, DT,
#' # bslib and shinyjs installed.
#' corpus <- list(
#'   list(abstract_id   = "CER_A",
#'        abstract_text = "Rainfall raised topsoil SOC on 520 Oxisols.")
#' )
#' draft <- file.path(tempdir(), "cerrado_draft.jsonl")
#' llm_preannotate(corpus, backend = "simulator", output_path = draft)
#'
#' # In-place review: `output_path` defaults to `draft_path`, and the
#' # app rewrites the file after every abstract, so an interrupted
#' # session loses at most the abstract you were on.
#' llm_annotation_launch(draft)
#'
#' # Better for anything you will publish: keep the machine draft
#' # pristine and write the human verdicts elsewhere.  In-place review
#' # destroys the LLM-vs-human comparison you need to report the
#' # extractor's precision and recall.
#' reviewed <- file.path(tempdir(), "cerrado_reviewed.jsonl")
#' llm_annotation_launch(draft, output_path = reviewed)
#'
#' # `port` only matters when the app must be reachable from outside
#' # the R process (container, remote annotator); leave it NULL and
#' # shiny picks a free port.
#' llm_annotation_launch(draft, output_path = reviewed, port = 8080)
#'
#' # Claims the reviewer never touched are still status = "draft" and
#' # are discarded here -- check the claim count in the message before
#' # treating the result as a finished gold standard.
#' llm_annotation_export(reviewed, file.path(tempdir(), "cerrado_gold.jsonl"))
#' llm_annotation_validate(file.path(tempdir(), "cerrado_gold.jsonl"))
#' }
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
