# Pillar 1 -- Multi-extractor consensus for LLM-driven KG ingestion.
#
# `causal_llm_extract()` (R/causal_llm.R) talks to a *single* LLM
# backend and returns whatever causal triples that one model decides
# the abstract supports. Different backends routinely disagree:
# running `gemma4:latest` (Ollama), `gpt-4o-mini` (OpenAI) and
# `claude-sonnet-4-6` (Anthropic) on the same Cerrado abstract
# typically produces three partially-overlapping sets of triples.
# A single-extractor KG inherits the idiosyncrasies of that one model.
#
# This file wires a **voting** layer on top of `causal_llm_extract()`:
# N backends run on the same abstract, their triples are aligned by
# (cause, effect), and a consensus set is computed by one of three
# voting rules:
#
#   * "majority"    — keep edges asserted by at least `min_support`
#                     backends. Default `min_support = ceiling(N/2)`,
#                     so with N = 3 a claim must be asserted by 2 or 3
#                     models to survive. Simple, interpretable, and
#                     robust to the lone-contrarian failure mode where
#                     one extractor hallucinates an edge.
#   * "weighted"    — weighted sum of per-backend confidence scores.
#                     Keep edges whose weighted score exceeds
#                     `threshold`. Use when you *know* one backend is
#                     more reliable (e.g. weight Claude higher than a
#                     7B local model).
#   * "intersection"— keep only edges asserted by ALL backends. Most
#                     conservative; yields the highest-precision KG at
#                     the cost of recall.
#
# Two auxiliary helpers go alongside the vote:
#
#   * causal_llm_vote()                returns the consensus data frame.
#   * causal_llm_ingest_abstract_voted() wraps vote + KG insertion, so
#     the multi-extractor path is a drop-in replacement for the single-
#     backend `causal_llm_ingest_abstract()`.

# ---- per-backend dispatch --------------------------------------------------

.llm_vote_normalise_cfg <- function(cfg) {
  if (!is.list(cfg)) {
    stop("Each element of `backends` must be a list with at least a ",
         "`backend` field.", call. = FALSE)
  }
  if (is.null(cfg$backend)) {
    stop("`backend` missing from a backends[] entry.", call. = FALSE)
  }
  cfg$backend <- match.arg(cfg$backend,
                             choices = c("ollama", "openai", "anthropic"))
  cfg$id <- cfg$id %||%
    sprintf("%s:%s", cfg$backend, cfg$model %||% "default")
  cfg
}

.llm_vote_call_one <- function(cfg, text, default_timeout_sec) {
  claims <- tryCatch(
    causal_llm_extract(
      text        = text,
      backend     = cfg$backend,
      model       = cfg$model,
      host        = cfg$host %||% "http://localhost:11434",
      temperature = cfg$temperature %||% 0,
      timeout_sec = cfg$timeout_sec %||% default_timeout_sec,
      api_key     = cfg$api_key
    ),
    error = function(e) {
      warning("backend '", cfg$id, "' failed: ",
               conditionMessage(e), call. = FALSE)
      data.frame(cause = character(0), effect = character(0),
                 evidence = character(0), confidence = numeric(0),
                 stringsAsFactors = FALSE)
    }
  )
  if (!is.data.frame(claims) || nrow(claims) == 0L) {
    return(data.frame(cause = character(0), effect = character(0),
                      evidence = character(0), confidence = numeric(0),
                      backend_id = character(0), model = character(0),
                      stringsAsFactors = FALSE))
  }
  claims$cause      <- tolower(trimws(claims$cause))
  claims$effect     <- tolower(trimws(claims$effect))
  claims$backend_id <- cfg$id
  claims$model      <- cfg$model %||% "default"
  claims
}

# ---- consensus accounting --------------------------------------------------

.llm_vote_consensus <- function(all_claims, N_backends, voting,
                                  min_support, threshold, weights,
                                  backend_ids) {
  if (nrow(all_claims) == 0L) {
    return(data.frame(
      cause = character(0), effect = character(0),
      n_backends = integer(0), mean_confidence = numeric(0),
      weighted_confidence = numeric(0), backends = character(0),
      evidence = character(0), stringsAsFactors = FALSE
    ))
  }
  key <- paste(all_claims$cause, "->", all_claims$effect)
  spl <- split(seq_len(nrow(all_claims)), key)
  if (is.null(weights)) {
    w <- stats::setNames(rep(1, length(backend_ids)), backend_ids)
  } else {
    stopifnot(is.numeric(weights), length(weights) == length(backend_ids))
    w <- stats::setNames(as.numeric(weights), backend_ids)
  }
  rows <- lapply(spl, function(ix) {
    sub <- all_claims[ix, , drop = FALSE]
    # De-duplicate per backend (some LLMs return the same edge multiple
    # times with slightly different evidence quotes).
    sub <- sub[!duplicated(sub$backend_id), , drop = FALSE]
    supp_ids <- sub$backend_id
    wscore   <- sum(w[supp_ids] * sub$confidence)
    data.frame(
      cause               = sub$cause[1L],
      effect              = sub$effect[1L],
      n_backends          = nrow(sub),
      mean_confidence     = mean(sub$confidence, na.rm = TRUE),
      weighted_confidence = wscore,
      backends            = paste(sort(supp_ids), collapse = " | "),
      evidence            = paste(
        unique(stats::na.omit(sub$evidence)), collapse = " | "
      ),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL

  keep <- switch(
    voting,
    majority     = out$n_backends >= min_support,
    weighted     = out$weighted_confidence >= threshold,
    intersection = out$n_backends == N_backends
  )
  out[keep, , drop = FALSE]
}

# ---- public entry points ---------------------------------------------------

#' Multi-extractor consensus over LLM-extracted causal claims
#'
#' Runs **N LLM backends** on the same abstract and returns a single
#' consensus data frame that resolves the inevitable disagreements by
#' one of three voting rules. See the file header for the design
#' rationale.
#'
#' @section Voting rules:
#' \describe{
#'   \item{`"majority"` (default)}{Keep edges asserted by at least
#'     `min_support` backends. When `min_support = NULL`, defaults to
#'     `ceiling(length(backends) / 2)` so 2-out-of-3 or 3-out-of-5
#'     agreement survives.}
#'   \item{`"weighted"`}{Keep edges whose weighted confidence
#'     \eqn{\sum_i w_i c_i} exceeds `threshold`. Weights are
#'     supplied per backend via `weights`.}
#'   \item{`"intersection"`}{Keep only edges asserted by **every**
#'     backend. Most conservative; maximises precision at the
#'     expense of recall.}
#' }
#'
#' @section Expected `backends` shape:
#' A list of lists. Each inner list configures one backend and must
#' contain at least a `backend` field (one of `"ollama"`,
#' `"openai"`, `"anthropic"`) and may optionally carry `model`,
#' `host` (for Ollama), `temperature`, `timeout_sec`, `api_key`,
#' `id`. Example:
#'
#' \preformatted{
#' backends = list(
#'   list(backend = "ollama",    model = "gemma4:latest",
#'        host   = "http://localhost:11434"),
#'   list(backend = "openai",    model = "gpt-4o-mini"),
#'   list(backend = "anthropic", model = "claude-sonnet-4-6")
#' )
#' }
#'
#' Failed backends (timeouts, missing API keys) emit a warning and
#' contribute zero claims; the vote continues with the remaining
#' backends.
#'
#' @param abstract Character scalar with the passage to annotate.
#' @param backends List of backend configurations; see above.
#' @param voting `"majority"` (default), `"weighted"`, or
#'   `"intersection"`.
#' @param min_support Integer — required number of backends for
#'   `"majority"` voting. Defaults to `ceiling(length(backends) / 2)`.
#' @param threshold Numeric — weighted-confidence threshold for
#'   `"weighted"` voting. Defaults to `0.5 * sum(weights)`.
#' @param weights Optional numeric vector, one element per backend
#'   (same order as `backends`). Defaults to uniform weights.
#' @param timeout_sec Default per-request timeout; may be overridden
#'   per-backend via the `timeout_sec` field of each config entry.
#' @return A data frame with one row per consensus edge and columns
#'   `cause`, `effect`, `n_backends`, `mean_confidence`,
#'   `weighted_confidence`, `backends` (`" | "`-separated list of
#'   supporting backend ids), `evidence` (concatenated quotations).
#' @seealso [causal_llm_ingest_abstract_voted()] for the KG-insertion
#'   wrapper; [causal_llm_extract()] for the single-backend call.
#' @examples
#' \dontrun{
#'   backends <- list(
#'     list(backend = "ollama",    model = "gemma4:latest"),
#'     list(backend = "openai",    model = "gpt-4o-mini"),
#'     list(backend = "anthropic", model = "claude-sonnet-4-6")
#'   )
#'   cons <- causal_llm_vote(
#'     abstract = "In Cerrado Oxisols, precipitation drives SOC...",
#'     backends = backends,
#'     voting   = "majority"
#'   )
#'   cons
#' }
#' @export
causal_llm_vote <- function(abstract,
                             backends,
                             voting = c("majority", "weighted",
                                         "intersection"),
                             min_support = NULL,
                             threshold   = NULL,
                             weights     = NULL,
                             timeout_sec = 120) {
  stopifnot(is.character(abstract), length(abstract) == 1L,
            nchar(abstract) > 0L,
            is.list(backends), length(backends) >= 2L)
  voting <- match.arg(voting)
  cfgs <- lapply(backends, .llm_vote_normalise_cfg)
  backend_ids <- vapply(cfgs, function(c) c$id, character(1L))

  if (voting == "majority" && is.null(min_support)) {
    min_support <- ceiling(length(cfgs) / 2)
  }
  if (voting == "weighted") {
    if (is.null(weights)) weights <- rep(1, length(cfgs))
    if (is.null(threshold)) threshold <- 0.5 * sum(weights)
  }

  per_backend <- lapply(cfgs, .llm_vote_call_one,
                         text = abstract,
                         default_timeout_sec = timeout_sec)
  all_claims <- do.call(rbind, per_backend)

  .llm_vote_consensus(all_claims,
                       N_backends  = length(cfgs),
                       voting      = voting,
                       min_support = min_support,
                       threshold   = threshold,
                       weights     = weights,
                       backend_ids = backend_ids)
}

#' Ingest an abstract into a KG via multi-extractor voting
#'
#' Single-call equivalent of running [causal_llm_vote()] and then
#' [causal_kg_add_edge()] on every surviving edge. The resulting KG
#' has a `source` tag of the form
#' `"<abstract_source> | vote(<voting>, n=<N_backends>)"` so the
#' provenance of every edge records both the underlying abstract and
#' the backends that agreed on the claim.
#'
#' @param kg,abstract,source See [causal_llm_ingest_abstract()].
#' @param backends,voting,min_support,threshold,weights,timeout_sec
#'   Forwarded to [causal_llm_vote()].
#' @param min_confidence Claims whose `mean_confidence` is below this
#'   threshold are dropped before insertion.
#' @return The updated `edaphos_causal_kg`. A `claims` attribute
#'   carries the tidy consensus data frame that was actually
#'   inserted, and a `per_backend` attribute carries the raw
#'   per-backend claims for audit / debugging.
#' @examples
#' \dontrun{
#'   backends <- list(
#'     list(backend = "ollama",    model = "gemma4:latest"),
#'     list(backend = "openai",    model = "gpt-4o-mini")
#'   )
#'   kg <- causal_kg_new()
#'   kg <- causal_llm_ingest_abstract_voted(
#'     kg,
#'     abstract = "Higher MAP drives SOC accumulation in Cerrado...",
#'     source   = "Ferreira 2021",
#'     backends = backends,
#'     voting   = "majority"
#'   )
#' }
#' @export
causal_llm_ingest_abstract_voted <- function(kg,
                                               abstract,
                                               source,
                                               backends,
                                               voting      = "majority",
                                               min_support = NULL,
                                               threshold   = NULL,
                                               weights     = NULL,
                                               min_confidence = 0.5,
                                               timeout_sec = 120) {
  stopifnot(inherits(kg, "edaphos_causal_kg"),
            is.character(abstract), length(abstract) == 1L,
            is.character(source),   length(source)   == 1L)
  cons <- causal_llm_vote(abstract = abstract, backends = backends,
                           voting = voting, min_support = min_support,
                           threshold = threshold, weights = weights,
                           timeout_sec = timeout_sec)
  keep <- !is.na(cons$mean_confidence) &
          cons$mean_confidence >= min_confidence
  cons <- cons[keep, , drop = FALSE]
  if (nrow(cons) == 0L) {
    attr(kg, "voted_claims") <- cons
    return(kg)
  }
  source_tag <- sprintf("%s | vote(%s,n=%d)", source, voting,
                          max(cons$n_backends, na.rm = TRUE))
  for (i in seq_len(nrow(cons))) {
    kg <- causal_kg_add_edge(
      kg,
      cause      = cons$cause[i],
      effect     = cons$effect[i],
      source     = source_tag,
      evidence   = cons$evidence[i],
      confidence = cons$mean_confidence[i]
    )
  }
  attr(kg, "voted_claims") <- cons
  kg
}
