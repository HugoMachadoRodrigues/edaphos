# Pillar 1 — LLM-driven causal relation extraction.
#
# Pure-R bindings to three interchangeable backends via `httr2`:
#   * Ollama  — local, zero cost (default: gemma4:latest).
#   * OpenAI  — hosted; requires OPENAI_API_KEY.
#   * Anthropic — hosted; requires ANTHROPIC_API_KEY.
#
# Every backend returns the same tidy data.frame:
#   cause | effect | evidence | confidence
# so downstream code in R/causal_kg.R and R/causal_augment.R is
# backend-agnostic.

.causal_llm_prompt <- function() {
  paste0(
"You are a causal-inference expert annotating pedology and soil-science ",
"literature.\n",
"\n",
"Your task: extract the explicit causal claims made by the passage ",
"below. Return a JSON object with a single key \"claims\" whose value ",
"is an array. Each array element must be an object with four fields:\n",
"  - cause      : the causal variable (lower snake_case)\n",
"  - effect     : the effect variable (lower snake_case)\n",
"  - evidence   : a short (max 180 characters) quotation from the ",
"passage that supports the claim\n",
"  - confidence : a number in [0, 1] reflecting how definitive the ",
"evidence is (0.9 = unambiguous causal phrasing, 0.5 = suggestive, ",
"0.2 = speculative)\n",
"\n",
"Only extract claims that are EXPLICITLY SUPPORTED by the passage. ",
"Do not invent relationships. Return an empty array if none are ",
"present. Use canonical pedometric vocabulary when possible:\n",
"  precipitation, mean_annual_precipitation, temperature, elevation,\n",
"  slope, aspect, twi, clay, sand, silt, soc, ph, cec, bulk_density,\n",
"  parent_material, land_use, vegetation, ndvi, erosion, weathering.\n",
"\n",
"Output JSON object only, no prose, no markdown fences."
  )
}

# --- Backend: Ollama ---------------------------------------------------------

.causal_llm_call_ollama <- function(text, model, host,
                                    temperature, timeout_sec) {
  req <- httr2::request(host)
  req <- httr2::req_url_path(req, "/api/chat")
  req <- httr2::req_method(req, "POST")
  req <- httr2::req_timeout(req, timeout_sec)
  req <- httr2::req_body_json(req, list(
    model    = model,
    messages = list(
      list(role = "system", content = .causal_llm_prompt()),
      list(role = "user",   content = text)
    ),
    format  = "json",
    stream  = FALSE,
    options = list(temperature = temperature)
  ))
  resp <- httr2::req_perform(req)
  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  message_content <- body$message$content %||% ""
  list(text = message_content, raw = body)
}

# --- Backend: OpenAI ---------------------------------------------------------

.causal_llm_call_openai <- function(text, model, temperature,
                                    timeout_sec, api_key) {
  req <- httr2::request("https://api.openai.com/v1/chat/completions")
  req <- httr2::req_method(req, "POST")
  req <- httr2::req_timeout(req, timeout_sec)
  req <- httr2::req_headers(req,
    Authorization = paste("Bearer", api_key),
    `Content-Type` = "application/json"
  )
  req <- httr2::req_body_json(req, list(
    model           = model,
    messages        = list(
      list(role = "system", content = .causal_llm_prompt()),
      list(role = "user",   content = text)
    ),
    temperature     = temperature,
    response_format = list(type = "json_object")
  ))
  resp <- httr2::req_perform(req)
  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  message_content <- body$choices[[1L]]$message$content %||% ""
  list(text = message_content, raw = body)
}

# --- Backend: Anthropic ------------------------------------------------------

.causal_llm_call_anthropic <- function(text, model, temperature,
                                        timeout_sec, api_key) {
  req <- httr2::request("https://api.anthropic.com/v1/messages")
  req <- httr2::req_method(req, "POST")
  req <- httr2::req_timeout(req, timeout_sec)
  req <- httr2::req_headers(req,
    `x-api-key`       = api_key,
    `anthropic-version` = "2023-06-01",
    `Content-Type`    = "application/json"
  )
  req <- httr2::req_body_json(req, list(
    model       = model,
    max_tokens  = 2048L,
    temperature = temperature,
    system      = .causal_llm_prompt(),
    messages    = list(list(role = "user", content = text))
  ))
  resp <- httr2::req_perform(req)
  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  # Anthropic returns a list of content blocks; take the first text block.
  blocks <- body$content
  text_blocks <- Filter(function(b) identical(b$type, "text"), blocks)
  msg <- if (length(text_blocks) > 0L) text_blocks[[1L]]$text else ""
  list(text = msg, raw = body)
}

# --- Parse LLM JSON response into a tidy claim data frame --------------------

.causal_llm_parse_claims <- function(raw_text) {
  # Strip accidental ``` fences / leading prose.
  s <- trimws(raw_text)
  # Grab from first "{" to the last "}" to survive minor framing noise.
  first <- regexpr("\\{", s)[[1L]]
  last  <- max(gregexpr("\\}", s)[[1L]])
  if (first < 1L || last < first) {
    return(data.frame(
      cause = character(0), effect = character(0),
      evidence = character(0), confidence = numeric(0),
      stringsAsFactors = FALSE
    ))
  }
  json_str <- substr(s, first, last)
  obj <- tryCatch(
    jsonlite::fromJSON(json_str, simplifyDataFrame = TRUE),
    error = function(e) NULL
  )
  claims <- obj$claims
  if (is.null(claims) || (is.data.frame(claims) && nrow(claims) == 0L) ||
      length(claims) == 0L) {
    return(data.frame(
      cause = character(0), effect = character(0),
      evidence = character(0), confidence = numeric(0),
      stringsAsFactors = FALSE
    ))
  }
  # Already a data frame (simplifyDataFrame = TRUE)?
  if (is.data.frame(claims)) {
    df <- claims
  } else {
    df <- do.call(rbind, lapply(claims, function(r) {
      data.frame(
        cause      = r$cause      %||% NA_character_,
        effect     = r$effect     %||% NA_character_,
        evidence   = r$evidence   %||% NA_character_,
        confidence = r$confidence %||% NA_real_,
        stringsAsFactors = FALSE
      )
    }))
  }
  # Normalise column presence & types.
  for (col in c("cause", "effect", "evidence", "confidence")) {
    if (is.null(df[[col]])) df[[col]] <- if (col == "confidence") NA_real_
                                         else NA_character_
  }
  df$confidence <- suppressWarnings(as.numeric(df$confidence))
  df$cause    <- tolower(trimws(df$cause))
  df$effect   <- tolower(trimws(df$effect))
  # Drop empty / self-loops.
  ok <- !is.na(df$cause) & !is.na(df$effect) &
        nzchar(df$cause) & nzchar(df$effect) &
        df$cause != df$effect
  df[ok, c("cause", "effect", "evidence", "confidence"), drop = FALSE]
}

.causal_llm_default_model <- function(backend) {
  switch(
    backend,
    ollama    = "gemma4:latest",
    openai    = "gpt-4o-mini",
    anthropic = "claude-sonnet-4-5",
    stop("Unknown backend: ", backend, call. = FALSE)
  )
}

#' Extract causal claims from text via an LLM backend
#'
#' Calls a Large Language Model and returns a tidy table of causal
#' claims — one row per extracted `(cause, effect)` pair — with the
#' quoted evidence and the confidence reported by the model.
#'
#' Three backends are supported via a uniform prompt:
#' * `"ollama"`  — local, zero-cost Ollama server (default
#'   `host = "http://localhost:11434"`, default model
#'   `"gemma4:latest"`). For higher extraction quality switch to
#'   `model = "gemma4:26b"`.
#' * `"openai"` — OpenAI Chat Completions API with JSON mode; needs
#'   the `OPENAI_API_KEY` environment variable (default model
#'   `"gpt-4o-mini"`).
#' * `"anthropic"` — Claude Messages API; needs `ANTHROPIC_API_KEY`
#'   (default model `"claude-sonnet-4-5"`).
#'
#' The return value is backend-independent, so downstream
#' [causal_llm_ingest_abstract()] and [causal_kg_add_edge()] work the
#' same regardless of which model produced the claims.
#'
#' @param text Character scalar — the passage to annotate.
#' @param backend One of `"ollama"`, `"openai"`, `"anthropic"`.
#' @param model Optional model name; defaults vary by backend.
#' @param host Ollama server URL (ignored by the hosted backends).
#' @param temperature Sampling temperature. Defaults to `0` for
#'   reproducibility.
#' @param timeout_sec Request timeout in seconds.
#' @param api_key Optional API key overriding the environment variable.
#'
#' @return A data frame with columns `cause`, `effect`, `evidence`,
#'   `confidence`. Empty (zero rows) when the model returns no claims
#'   or the response cannot be parsed.
#' @export
#' @examples
#' \dontrun{
#'   abstract <- "In Cerrado soils, higher mean annual precipitation is
#'     associated with significantly increased topsoil organic carbon."
#'   causal_llm_extract(abstract, backend = "ollama",
#'                      model = "gemma4:latest")
#' }
causal_llm_extract <- function(text,
                                backend = c("ollama", "openai", "anthropic"),
                                model   = NULL,
                                host    = "http://localhost:11434",
                                temperature = 0,
                                timeout_sec = 120,
                                api_key = NULL) {
  backend <- match.arg(backend)
  stopifnot(is.character(text), length(text) == 1L, !is.na(text),
            nchar(text) > 0L)
  if (is.null(model)) model <- .causal_llm_default_model(backend)

  result <- switch(
    backend,
    ollama    = .causal_llm_call_ollama(
      text, model = model, host = host,
      temperature = temperature, timeout_sec = timeout_sec
    ),
    openai    = {
      key <- api_key %||% Sys.getenv("OPENAI_API_KEY", "")
      if (!nzchar(key))
        stop("Set OPENAI_API_KEY or pass `api_key`.", call. = FALSE)
      .causal_llm_call_openai(text, model = model,
                              temperature = temperature,
                              timeout_sec = timeout_sec,
                              api_key = key)
    },
    anthropic = {
      key <- api_key %||% Sys.getenv("ANTHROPIC_API_KEY", "")
      if (!nzchar(key))
        stop("Set ANTHROPIC_API_KEY or pass `api_key`.", call. = FALSE)
      .causal_llm_call_anthropic(text, model = model,
                                  temperature = temperature,
                                  timeout_sec = timeout_sec,
                                  api_key = key)
    }
  )
  claims <- .causal_llm_parse_claims(result$text)
  attr(claims, "backend")      <- backend
  attr(claims, "model")        <- model
  attr(claims, "raw_response") <- result$text
  claims
}

#' Ingest an abstract into a pedogenetic Knowledge Graph
#'
#' Wrapper that calls [causal_llm_extract()] on a single passage and
#' then adds every returned claim as an edge of the supplied
#' `edaphos_causal_kg`. Claims whose `confidence` is below
#' `min_confidence` are discarded.
#'
#' @param kg An `edaphos_causal_kg` to update in place.
#' @param abstract Character scalar with the passage to annotate.
#' @param source Character scalar used as the `source` attribute of
#'   every added edge (a bibliographic key, a DOI, etc.).
#' @param min_confidence Numeric in `[0, 1]`. Claims with
#'   `confidence < min_confidence` are dropped before insertion.
#' @param ... Forwarded to [causal_llm_extract()] (`backend`,
#'   `model`, `host`, ...).
#' @return The updated `edaphos_causal_kg`. An attribute
#'   `"claims"` carries the tidy data frame that was actually
#'   inserted.
#' @export
causal_llm_ingest_abstract <- function(kg, abstract, source,
                                        min_confidence = 0.5, ...) {
  stopifnot(inherits(kg, "edaphos_causal_kg"),
            is.character(abstract), length(abstract) == 1L,
            is.character(source),   length(source)   == 1L)
  claims <- causal_llm_extract(abstract, ...)
  keep   <- !is.na(claims$confidence) & claims$confidence >= min_confidence
  claims <- claims[keep, , drop = FALSE]
  for (i in seq_len(nrow(claims))) {
    kg <- causal_kg_add_edge(
      kg,
      cause      = claims$cause[i],
      effect     = claims$effect[i],
      source     = source,
      evidence   = claims$evidence[i],
      confidence = claims$confidence[i]
    )
  }
  attr(kg, "claims") <- claims
  kg
}

#' Ingest a corpus of abstracts into a Knowledge Graph
#'
#' Batched version of [causal_llm_ingest_abstract()] — iterates over a
#' data frame of abstracts and returns the accumulated Knowledge
#' Graph. A `progress` callback is invoked after each abstract for
#' long-running runs.
#'
#' @param kg An `edaphos_causal_kg`.
#' @param abstracts Data frame with one row per abstract.
#' @param abstract_col,source_col Column names in `abstracts`
#'   holding the text and the provenance key respectively.
#' @param min_confidence Forwarded to [causal_llm_ingest_abstract()].
#' @param progress Optional `function(i, n, source)` called at each
#'   step for logging / progress bars.
#' @param ... Forwarded to [causal_llm_extract()] (`backend`,
#'   `model`, `host`, ...).
#' @return Updated `edaphos_causal_kg`.
#' @export
causal_llm_ingest_corpus <- function(kg, abstracts,
                                     abstract_col = "abstract",
                                     source_col   = "source",
                                     min_confidence = 0.5,
                                     progress = NULL, ...) {
  stopifnot(inherits(kg, "edaphos_causal_kg"),
            is.data.frame(abstracts),
            abstract_col %in% names(abstracts),
            source_col %in% names(abstracts))
  n <- nrow(abstracts)
  for (i in seq_len(n)) {
    kg <- causal_llm_ingest_abstract(
      kg,
      abstract       = abstracts[[abstract_col]][i],
      source         = abstracts[[source_col]][i],
      min_confidence = min_confidence,
      ...
    )
    if (!is.null(progress)) {
      progress(i, n, abstracts[[source_col]][i])
    }
  }
  kg
}
