# Pillar 1 — Literature ingestion clients.
#
# Two zero-configuration clients that return a tidy data frame of
# scientific abstracts, ready to be fed straight into the LLM
# extraction pipeline of R/causal_llm.R. Both hit **public, keyless**
# APIs so the default workflow does not require any account.
#
#   causal_corpus_scielo()     -> SciELO ArticleMeta API
#   causal_corpus_openalex()   -> OpenAlex Works API
#
# Google Scholar is intentionally not wrapped: it has no official
# public API and scraping is a Terms-of-Service liability.

.corpus_normalise_frame <- function(rows) {
  if (length(rows) == 0L) {
    return(data.frame(
      source   = character(0), title   = character(0),
      abstract = character(0), year    = integer(0),
      doi      = character(0), url     = character(0),
      stringsAsFactors = FALSE
    ))
  }
  df <- do.call(rbind, lapply(rows, function(r) {
    data.frame(
      source   = r$source   %||% NA_character_,
      title    = r$title    %||% NA_character_,
      abstract = r$abstract %||% NA_character_,
      year     = r$year     %||% NA_integer_,
      doi      = r$doi      %||% NA_character_,
      url      = r$url      %||% NA_character_,
      stringsAsFactors = FALSE
    )
  }))
  # Drop rows with empty abstracts — they are useless for extraction.
  df <- df[!is.na(df$abstract) & nzchar(trimws(df$abstract)), , drop = FALSE]
  rownames(df) <- NULL
  df
}

# --- SciELO ArticleMeta ------------------------------------------------------
#
# https://articlemeta.scielo.org/api/v1/article/identifiers/?q=... returns a
# list of DOIs / PIDs matching the query; a second call to
# /article/?collection=...&code=... retrieves one article. The search
# endpoint exposed here is /article/?q=... which returns full records in
# one shot — simpler and sufficient for the vignette's use case.

.scielo_extract_abstract <- function(article) {
  # SciELO records embed abstracts by language in `v83` (SciELO SOM) or
  # under article_meta$abstract depending on the record version. Try both.
  ab <- NULL
  if (!is.null(article$abstract) && length(article$abstract) > 0L) {
    ab <- article$abstract
  } else if (!is.null(article$article_meta) &&
             !is.null(article$article_meta$abstract) &&
             length(article$article_meta$abstract) > 0L) {
    ab <- article$article_meta$abstract
  } else if (!is.null(article$v83) && length(article$v83) > 0L) {
    vs <- article$v83
    # Prefer English then any language
    en <- Filter(function(x) identical(x$l, "en"), vs)
    chosen <- if (length(en) > 0L) en[[1L]] else vs[[1L]]
    ab <- chosen$a %||% chosen$`_` %||% NA_character_
  }
  if (is.list(ab)) ab <- ab[[1L]]
  if (is.null(ab) || length(ab) == 0L) return(NA_character_)
  as.character(ab)
}

#' Query the SciELO literature corpus
#'
#' Calls the **SciELO ArticleMeta REST API** (no account needed) and
#' returns a tidy data frame of abstracts ready for LLM extraction via
#' [causal_llm_ingest_corpus()]. Results are deduplicated by DOI /
#' title and filtered to articles that expose an abstract.
#'
#' @param query Character search string passed to the ArticleMeta
#'   full-text search (`q=`).
#' @param max_results Integer cap on the number of articles fetched.
#' @param from_year,to_year Optional integer year filters
#'   (inclusive).
#' @param host Endpoint host (default `"articlemeta.scielo.org"`;
#'   override for mirror testing).
#' @param timeout_sec Request timeout (seconds).
#'
#' @return A data frame with columns `source`, `title`, `abstract`,
#'   `year`, `doi`, `url`.
#' @export
#' @examples
#' \dontrun{
#'   cerrado <- causal_corpus_scielo("Cerrado soil organic carbon",
#'                                    max_results = 20)
#'   head(cerrado[, c("source", "title", "year")])
#' }
causal_corpus_scielo <- function(query,
                                  max_results = 50L,
                                  from_year = NULL,
                                  to_year   = NULL,
                                  host      = "articlemeta.scielo.org",
                                  timeout_sec = 120) {
  stopifnot(is.character(query), length(query) == 1L, nzchar(query))
  base <- paste0("https://", host, "/api/v1/article/")
  req <- httr2::request(base)
  req <- httr2::req_timeout(req, timeout_sec)
  req <- httr2::req_url_query(req,
    q      = query,
    format = "json",
    limit  = as.integer(max_results)
  )
  if (!is.null(from_year)) req <- httr2::req_url_query(req,
                                                        from = from_year)
  if (!is.null(to_year))   req <- httr2::req_url_query(req,
                                                        to = to_year)
  resp  <- httr2::req_perform(req)
  body  <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  items <- body$objects %||% body$articles %||% body %||% list()

  rows <- lapply(items, function(it) {
    list(
      source   = it$code      %||% it$pid %||% it$doi %||%
                 NA_character_,
      title    = it$title     %||% it$article_title %||% NA_character_,
      abstract = .scielo_extract_abstract(it),
      year     = suppressWarnings(as.integer(it$publication_year %||%
                                              it$year %||% NA)),
      doi      = it$doi       %||% NA_character_,
      url      = it$url       %||% paste0("https://", host,
                                          "/api/v1/article/?code=",
                                          it$code %||% "")
    )
  })
  .corpus_normalise_frame(rows)
}

# --- OpenAlex ---------------------------------------------------------------
#
# OpenAlex's /works endpoint ships abstracts as an "inverted index":
# { "word": [positions, ...] }. We must reconstruct the linear abstract
# before the LLM can read it.

.openalex_abstract_from_inverted_index <- function(inv) {
  if (is.null(inv) || length(inv) == 0L) return(NA_character_)
  words <- names(inv)
  positions <- lapply(inv, unlist)
  n <- max(unlist(positions)) + 1L
  out <- rep(NA_character_, n)
  for (w in seq_along(words)) {
    for (pos in positions[[w]]) out[pos + 1L] <- words[w]
  }
  paste(out[!is.na(out)], collapse = " ")
}

#' Query the OpenAlex corpus
#'
#' Thin wrapper around the **OpenAlex Works API** (no account needed;
#' a courtesy `mailto=` parameter raises the user's rate-limit tier).
#' OpenAlex stores abstracts as an inverted index; they are
#' reconstructed to plain text here so the result is
#' LLM-extractor-ready.
#'
#' @param query Character search string.
#' @param max_results Integer cap on the total number of works
#'   fetched. The function transparently pages through the API
#'   (cursor-based, 200 results per page) until either `max_results`
#'   or the result set is exhausted.
#' @param from_year,to_year Optional integer year filters
#'   (inclusive).
#' @param mailto Optional email string sent as `mailto=` to identify
#'   the client and unlock the "polite" rate-limit pool.
#' @param timeout_sec Request timeout (seconds).
#'
#' @return A data frame with columns `source`, `title`, `abstract`,
#'   `year`, `doi`, `url`.
#' @export
#' @examples
#' \dontrun{
#'   oa <- causal_corpus_openalex("Cerrado soil organic carbon",
#'                                 max_results = 2500L,
#'                                 mailto = "you@example.org")
#'   head(oa[, c("source", "title", "year")])
#' }
causal_corpus_openalex <- function(query,
                                    max_results = 50L,
                                    from_year = NULL,
                                    to_year   = NULL,
                                    mailto    = NULL,
                                    timeout_sec = 120) {
  stopifnot(is.character(query), length(query) == 1L, nzchar(query))
  max_results <- as.integer(max_results)
  per_page <- 200L
  # Filter string shared across pages.
  filters <- character(0)
  if (!is.null(from_year)) filters <- c(filters,
                                        paste0("from_publication_date:",
                                               from_year, "-01-01"))
  if (!is.null(to_year))   filters <- c(filters,
                                        paste0("to_publication_date:",
                                               to_year, "-12-31"))
  filter_str <- if (length(filters) > 0L)
    paste(filters, collapse = ",") else NULL

  collected <- list()
  cursor    <- "*"
  while (length(collected) < max_results && !is.null(cursor)) {
    req <- httr2::request("https://api.openalex.org/works")
    req <- httr2::req_timeout(req, timeout_sec)
    req <- httr2::req_url_query(req,
                                 search   = query,
                                 per_page = per_page,
                                 cursor   = cursor)
    if (!is.null(mailto))     req <- httr2::req_url_query(req,
                                                            mailto = mailto)
    if (!is.null(filter_str)) req <- httr2::req_url_query(req,
                                                            filter = filter_str)
    resp <- tryCatch(httr2::req_perform(req),
                     error = function(e) NULL)
    if (is.null(resp)) break
    body  <- httr2::resp_body_json(resp, simplifyVector = FALSE)
    items <- body$results %||% list()
    if (length(items) == 0L) break
    collected <- c(collected, items)
    cursor_next <- body$meta$next_cursor %||% NULL
    if (is.null(cursor_next)) break
    cursor <- as.character(unlist(cursor_next))[1L]
    if (is.na(cursor) || !nzchar(cursor)) break
  }
  collected <- utils::head(collected, max_results)

  rows <- lapply(collected, function(it) {
    doi <- it$doi %||% NA_character_
    doi_norm <- sub("^https?://doi.org/", "", doi %||% "")
    list(
      source   = it$id %||% doi %||% it$title %||% NA_character_,
      title    = it$title %||% NA_character_,
      abstract = .openalex_abstract_from_inverted_index(
        it$abstract_inverted_index
      ),
      year     = suppressWarnings(as.integer(it$publication_year %||% NA)),
      doi      = if (nzchar(doi_norm)) doi_norm else NA_character_,
      url      = it$id %||% NA_character_
    )
  })
  .corpus_normalise_frame(rows)
}

#' Deduplicate a corpus by DOI or title
#'
#' Collapses rows that refer to the same publication when combining
#' results from multiple sources (SciELO + OpenAlex frequently share
#' Brazilian pedology papers). DOI is the primary key when available;
#' a normalised lower-case title is the fallback.
#'
#' @param corpus Data frame with at minimum a `doi` and / or `title`
#'   column.
#' @param by Character vector of columns to deduplicate on. Default
#'   `c("doi","title")` — try DOI first, fall back to title.
#' @return A de-duplicated data frame.
#' @export
causal_corpus_deduplicate <- function(corpus, by = c("doi", "title")) {
  stopifnot(is.data.frame(corpus))
  df <- corpus
  key_doi   <- if ("doi" %in% by && "doi" %in% names(df))
    tolower(trimws(df$doi)) else rep(NA_character_, nrow(df))
  key_title <- if ("title" %in% by && "title" %in% names(df))
    tolower(gsub("\\s+", " ", trimws(df$title))) else rep(NA_character_,
                                                           nrow(df))
  key <- ifelse(!is.na(key_doi) & nzchar(key_doi), key_doi, key_title)
  keep <- !duplicated(key) | is.na(key)
  out  <- df[keep, , drop = FALSE]
  rownames(out) <- NULL
  out
}
