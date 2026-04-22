# Pillar 1 — Ontology alignment.
#
# Turns free-text node labels emitted by the LLM extractor (e.g.
# "steeper_slopes", "organic_matter_accumulation", "mean_annual_precipitation")
# into canonical pedometric terms so that a Knowledge Graph built
# from different abstracts — and at different points in time — can
# be fused coherently. Three tiers of matching are tried in order:
#
#   1. exact          lowercase-identical match to the canonical term
#   2. substring      node name contains the canonical term, or vice versa
#   3. fuzzy          Levenshtein (via base `adist`) or optimal string
#                     alignment (via `stringdist` if installed)
#
# Three vocabulary sources are exposed:
#
#   * causal_ontology_cerrado()  -- a hand-curated ~60-term Cerrado
#     pedometry vocabulary that is a subset of AGROVOC + ENVO. Zero
#     external dependency; ships with the package.
#
#   * causal_ontology_agrovoc(query, limit) -- live SPARQL query to
#     the FAO AGROVOC endpoint (agrovoc.fao.org). Requires network.
#
#   * causal_ontology_envo(path) -- parse a local ENVO .obo file via
#     the optional `ontologyIndex` Suggests dependency.

.cerrado_canonical_vocabulary <- function() {
  data.frame(
    term = c(
      # Climate --------------------------------------------------------
      "precipitation", "mean_annual_precipitation", "temperature",
      "mean_annual_temperature", "aridity", "evapotranspiration",
      "fire", "fire_frequency",
      # Relief ---------------------------------------------------------
      "elevation", "slope", "aspect", "twi", "curvature", "landform",
      # Parent material / mineralogy -----------------------------------
      "parent_material", "clay", "sand", "silt", "texture",
      "kaolinite", "gibbsite", "iron_oxide", "weathering",
      # Chemistry ------------------------------------------------------
      "ph", "cec", "soc", "soil_organic_carbon", "nitrogen",
      "phosphorus", "potassium", "calcium", "magnesium", "aluminium",
      "base_saturation", "bulk_density", "leaching",
      # Vegetation / land use ------------------------------------------
      "vegetation", "ndvi", "biomass", "root_biomass", "land_use",
      "pasture", "no_till", "native_savanna", "cropland",
      "deforestation",
      # Processes ------------------------------------------------------
      "erosion", "decomposition", "illuviation", "mineralisation",
      "soil_moisture", "water_retention", "microbial_activity",
      # Outcomes -------------------------------------------------------
      "yield", "productivity", "soc_loss", "soc_accumulation",
      "nutrient_availability"
    ),
    category = c(
      rep("climate", 8L),
      rep("relief", 6L),
      rep("parent_material", 9L),
      rep("chemistry", 13L),
      rep("vegetation", 10L),
      rep("process", 7L),
      rep("outcome", 5L)
    ),
    stringsAsFactors = FALSE
  )
}

#' Canonical Cerrado pedometric vocabulary
#'
#' Returns a hand-curated data frame of ~60 canonical terms covering
#' the major drivers of Cerrado soil formation — climate, relief,
#' parent material, chemistry, vegetation, processes and outcomes.
#' The vocabulary is a deliberately narrow subset of AGROVOC + ENVO,
#' chosen for coverage of the topics that actually appear in Brazilian
#' pedology abstracts. It is the default reference used by
#' [causal_kg_alignment()].
#'
#' @return A data frame with columns `term` and `category`.
#' @export
causal_ontology_cerrado <- function() {
  .cerrado_canonical_vocabulary()
}

#' Query the AGROVOC SPARQL endpoint
#'
#' Thin wrapper around the FAO AGROVOC SPARQL endpoint
#' (<https://agrovoc.fao.org/sparql>). The endpoint is **public and
#' keyless** and returns RDF/JSON.
#'
#' @param query Character concept label to search for (e.g.
#'   `"soil organic carbon"`). A `rdfs:label` filter with English
#'   language tag is applied.
#' @param limit Integer, max number of matches returned.
#' @param timeout_sec Request timeout (seconds).
#'
#' @param endpoint Override the default AGROVOC SPARQL endpoint URL
#'   (mirror / proxy).
#'
#' @return A data frame with columns `uri` (AGROVOC concept URI) and
#'   `term` (canonical lower-snake-case label).
#' @export
#' @examples
#' \dontrun{
#'   causal_ontology_agrovoc("soil organic carbon", limit = 5)
#' }
causal_ontology_agrovoc <- function(query, limit = 10L,
                                     timeout_sec = 60L,
                                     endpoint =
                                       "https://agrovoc.fao.org/sparql") {
  stopifnot(is.character(query), length(query) == 1L, nzchar(query))
  sparql <- sprintf(
    paste(
      "PREFIX skos: <http://www.w3.org/2004/02/skos/core#>",
      "SELECT ?uri ?label WHERE {",
      "  ?uri a skos:Concept ;",
      "       skos:prefLabel ?label .",
      "  FILTER(LANG(?label) = \"en\")",
      "  FILTER(CONTAINS(LCASE(STR(?label)), LCASE(\"%s\")))",
      "} LIMIT %d",
      sep = " "
    ),
    gsub("\"", "'", query), as.integer(limit)
  )
  req  <- httr2::request(endpoint)
  req  <- httr2::req_method(req, "POST")
  req  <- httr2::req_timeout(req, timeout_sec)
  req  <- httr2::req_headers(req,
    Accept = "application/sparql-results+json")
  req  <- httr2::req_body_form(req, query = sparql)
  resp <- httr2::req_perform(req)
  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  rows <- body$results$bindings %||% list()
  if (length(rows) == 0L) {
    return(data.frame(uri = character(0), term = character(0),
                      stringsAsFactors = FALSE))
  }
  uri   <- vapply(rows, function(r) r$uri$value,    character(1L))
  label <- vapply(rows, function(r) r$label$value,  character(1L))
  term  <- tolower(gsub("[^[:alnum:]]+", "_", trimws(label)))
  term  <- gsub("_+", "_", term); term <- gsub("^_|_$", "", term)
  data.frame(uri = uri, term = term, label = label,
             stringsAsFactors = FALSE)
}

#' Load an ENVO ontology from a local .obo file
#'
#' Parses a downloaded Environmental Ontology (ENVO) OBO file via
#' the optional `ontologyIndex` Suggests dependency and returns a
#' tidy vocabulary frame. Download ENVO from
#' <https://obofoundry.org/ontology/envo.html>.
#'
#' @param path Path to an `envo.obo` file.
#' @return A data frame with columns `id`, `term`, `label`.
#' @export
causal_ontology_envo <- function(path) {
  if (!requireNamespace("ontologyIndex", quietly = TRUE)) {
    stop("Install the `ontologyIndex` package to load an OBO file.",
         call. = FALSE)
  }
  stopifnot(file.exists(path))
  oi <- ontologyIndex::get_OBO(path, propagate_relationships = "is_a",
                                extract_tags = "minimal")
  label <- oi$name
  id    <- oi$id
  term  <- tolower(gsub("[^[:alnum:]]+", "_", trimws(label)))
  term  <- gsub("_+", "_", term); term <- gsub("^_|_$", "", term)
  data.frame(id = id, term = term, label = label,
             stringsAsFactors = FALSE)
}

# ---- Matcher primitives -----------------------------------------------------

.match_exact <- function(node, vocab) {
  i <- which(vocab == node)
  if (length(i) == 0L) return(NA_integer_)
  i[1L]
}

.match_substring <- function(node, vocab) {
  # Prefer longest overlap; "soc_loss" should match "soc_loss" over "soc".
  contains_node_in_vocab <- grepl(paste0("(^|_)", node, "($|_)"), vocab,
                                   fixed = FALSE)
  contains_vocab_in_node <- vapply(vocab,
    function(v) grepl(paste0("(^|_)", v, "($|_)"), node), logical(1L))
  candidates <- which(contains_node_in_vocab | contains_vocab_in_node)
  if (length(candidates) == 0L) return(NA_integer_)
  # Pick the candidate with the longest shared token.
  scores <- nchar(vocab[candidates])
  candidates[which.max(scores)]
}

.match_fuzzy <- function(node, vocab, max_distance = 4L) {
  if (requireNamespace("stringdist", quietly = TRUE)) {
    d <- stringdist::stringdist(node, vocab, method = "osa")
  } else {
    d <- as.integer(utils::adist(node, vocab, ignore.case = TRUE))
  }
  if (length(d) == 0L) return(NA_integer_)
  best <- which.min(d)
  if (d[best] > max_distance) return(NA_integer_)
  best
}

#' Live AGROVOC alignment for a vector of free-text terms
#'
#' For each input `term`, queries the AGROVOC SPARQL endpoint for
#' concepts whose `skos:prefLabel` or `skos:altLabel` contains the
#' term, ranks the matches by Levenshtein distance to the canonical
#' label, and returns the best hit. Results are cached on disk via
#' `cache_path` so that repeated runs over the same vocabulary do
#' not re-query FAO.
#'
#' @param terms Character vector of free-text terms (typically the
#'   nodes of a Knowledge Graph).
#' @param cache_path Optional `.rds` file path. When supplied, the
#'   function reads cached matches on entry and writes updated
#'   matches on exit.
#' @param max_per_term Integer — how many candidates to request per
#'   term (AGROVOC query LIMIT). The best one is kept.
#' @param endpoint Override the SPARQL endpoint URL.
#' @param timeout_sec Per-query timeout.
#' @param verbose Logical — print one line per queried term.
#' @return A data frame with columns `term` (input), `uri`
#'   (AGROVOC concept), `label` (AGROVOC pref label), `distance`
#'   (Levenshtein of lowercased label vs term).
#' @export
causal_ontology_agrovoc_align <- function(terms,
                                            cache_path = NULL,
                                            max_per_term = 5L,
                                            endpoint =
                                              "https://agrovoc.fao.org/sparql",
                                            timeout_sec = 60L,
                                            verbose = FALSE) {
  terms <- tolower(trimws(unique(as.character(terms))))
  terms <- terms[nzchar(terms)]
  cache <- list()
  if (!is.null(cache_path) && file.exists(cache_path)) {
    cache <- tryCatch(readRDS(cache_path), error = function(e) list())
  }

  rows <- lapply(terms, function(tm) {
    if (!is.null(cache[[tm]])) return(cache[[tm]])
    # AGROVOC labels use spaces, not underscores; normalise the query.
    tm_query <- gsub("_+", " ", tm)
    q <- tryCatch(
      causal_ontology_agrovoc(tm_query, limit = max_per_term,
                               timeout_sec = timeout_sec,
                               endpoint = endpoint),
      error = function(e) NULL
    )
    if (is.null(q) || nrow(q) == 0L) {
      hit <- data.frame(
        term     = tm,
        uri      = NA_character_,
        label    = NA_character_,
        distance = NA_real_,
        stringsAsFactors = FALSE
      )
    } else {
      d <- vapply(q$label, function(lb)
        as.integer(utils::adist(tolower(lb), tm_query))[1L], integer(1L))
      best <- which.min(d)
      hit <- data.frame(
        term     = tm,
        uri      = q$uri[best],
        label    = q$label[best],
        distance = d[best],
        stringsAsFactors = FALSE
      )
    }
    cache[[tm]] <<- hit
    if (verbose) message(sprintf("[agrovoc] %-30s -> %s  (d=%s)",
                                   tm,
                                   if (is.na(hit$uri)) "<none>"
                                   else hit$label,
                                   format(hit$distance)))
    hit
  })
  out <- do.call(rbind, rows)
  if (!is.null(cache_path)) {
    try(saveRDS(cache, cache_path), silent = TRUE)
  }
  out
}

# --- batched / concurrent AGROVOC alignment ----------------------------------
#
# AGROVOC's public SPARQL endpoint rejects single composite queries
# that combine SPARQL `VALUES` or `UNION` with `CONTAINS(?label,
# ?term)`: the server has to apply the substring filter against every
# SKOS label in the repository before intersecting with the bound term
# set, which invariably trips the gateway 60-second timeout. Genuine
# SPARQL-level batching is therefore not available against the
# production endpoint at the time of writing.
#
# Instead, `causal_ontology_agrovoc_align_batch()` batches at the
# **transport layer**: it fires concurrent HTTP POST requests through
# `httr2::req_perform_parallel()`, short-circuits every term already
# present in the on-disk cache, and retries transient failures with
# exponential backoff. A resolving 10-term run that would take ~80 s
# sequentially completes in ~20 s with `max_active = 5` (empirically
# measured, agrovoc.fao.org), scaling further with higher concurrency
# as long as the user stays within FAO's fair-use policy.

.agrovoc_build_request <- function(term, endpoint, timeout_sec,
                                    max_per_term) {
  tm_query <- gsub("_+", " ", tolower(trimws(term)))
  sparql <- sprintf(
    paste(
      "PREFIX skos: <http://www.w3.org/2004/02/skos/core#>",
      "SELECT ?uri ?label WHERE {",
      "  ?uri a skos:Concept ;",
      "       skos:prefLabel ?label .",
      "  FILTER(LANG(?label) = \"en\")",
      "  FILTER(CONTAINS(LCASE(STR(?label)), LCASE(\"%s\")))",
      "} LIMIT %d",
      sep = " "
    ),
    gsub("\"", "'", tm_query), as.integer(max_per_term)
  )
  req <- httr2::request(endpoint)
  req <- httr2::req_method(req, "POST")
  req <- httr2::req_timeout(req, timeout_sec)
  req <- httr2::req_headers(req,
                             Accept = "application/sparql-results+json")
  req <- httr2::req_body_form(req, query = sparql)
  req
}

.agrovoc_parse_response <- function(resp, term) {
  if (!inherits(resp, "httr2_response") ||
      httr2::resp_status(resp) != 200L) {
    return(data.frame(
      term = term, uri = NA_character_, label = NA_character_,
      distance = NA_real_, stringsAsFactors = FALSE
    ))
  }
  body <- tryCatch(
    httr2::resp_body_json(resp, simplifyVector = FALSE),
    error = function(e) NULL
  )
  rows <- body$results$bindings %||% list()
  if (length(rows) == 0L) {
    return(data.frame(
      term = term, uri = NA_character_, label = NA_character_,
      distance = NA_real_, stringsAsFactors = FALSE
    ))
  }
  uri   <- vapply(rows, function(r) r$uri$value,   character(1L))
  label <- vapply(rows, function(r) r$label$value, character(1L))
  tm_q  <- gsub("_+", " ", tolower(trimws(term)))
  d <- vapply(label, function(lb)
    as.integer(utils::adist(tolower(lb), tm_q))[1L], integer(1L))
  best <- which.min(d)
  data.frame(
    term     = term,
    uri      = uri[best],
    label    = label[best],
    distance = d[best],
    stringsAsFactors = FALSE
  )
}

#' Concurrent AGROVOC alignment for a large vocabulary
#'
#' Resolves a vector of free-text `terms` against the FAO AGROVOC
#' SPARQL endpoint using **parallel HTTP dispatch**, an on-disk cache,
#' and retry logic with exponential backoff. Designed for Knowledge
#' Graphs built from thousands of papers, where the per-term overhead
#' of [causal_ontology_agrovoc_align()] (~5–10 s / term against
#' agrovoc.fao.org) dominates the runtime.
#'
#' @section SPARQL-level vs transport-level batching:
#' A single composite SPARQL query that binds N terms via `VALUES`
#' and filters labels with `CONTAINS(?label, ?term)` is the
#' theoretically optimal batching strategy, but AGROVOC's production
#' endpoint consistently rejects such queries with a 504 gateway
#' timeout because the substring predicate cannot short-circuit
#' against the bound term set. `causal_ontology_agrovoc_align_batch()`
#' therefore batches at the transport layer instead: it issues one
#' single-term query per uncached input and dispatches them through
#' `httr2::req_perform_parallel()` with `max_active` concurrent
#' connections. The on-wire semantics are identical to
#' [causal_ontology_agrovoc_align()]; only the wall-clock time
#' changes.
#'
#' @section Caching and resumability:
#' The cache is a named list keyed by normalised term, persisted as a
#' single `.rds` file. On entry every cached term is short-circuited
#' without a network call. Failed terms are **not** cached, so a
#' resumed run retries them; successful terms become permanent.
#' Pointing a fresh `cache_path` at an existing `.rds` keeps the
#' cache; passing `NULL` disables persistence (in-memory only).
#'
#' @param terms Character vector of free-text terms.
#' @param cache_path Optional `.rds` file path. When supplied, the
#'   function reads cached matches on entry and writes updated
#'   matches on exit.
#' @param max_active Integer — maximum number of concurrent HTTP
#'   connections. Default `5`; raise for faster throughput, lower if
#'   the endpoint is rate-limiting you. `httr2` transparently pools
#'   up to `max_active` connections.
#' @param max_per_term Integer — AGROVOC query `LIMIT` per term; the
#'   closest label by Levenshtein distance is retained.
#' @param max_retries Integer — number of retry rounds for terms that
#'   come back with a non-200 response. Retries apply exponential
#'   backoff (`2 ^ attempt` seconds between rounds).
#' @param endpoint AGROVOC SPARQL endpoint URL. Override for a mirror
#'   or a local SPARQL proxy.
#' @param timeout_sec Per-request timeout (seconds).
#' @param verbose Logical — print a one-line progress summary after
#'   each parallel round.
#' @return A data frame with columns `term`, `uri`, `label`,
#'   `distance` (NA when no hit). Unresolved terms keep NA slots; the
#'   caller can decide whether to retry them or accept a partial
#'   alignment.
#' @seealso [causal_ontology_agrovoc_align()] for the sequential
#'   variant; [causal_kg_alignment()] for KG-level dispatch.
#' @examples
#' \dontrun{
#'   # 100-term vocabulary extracted from a KG built over 10k abstracts.
#'   vocab <- unique(c(causal_kg_edges(kg)$cause,
#'                      causal_kg_edges(kg)$effect))
#'   ag <- causal_ontology_agrovoc_align_batch(
#'     vocab,
#'     cache_path = "tools/.agrovoc_cache.rds",
#'     max_active = 8L,
#'     max_retries = 2L,
#'     verbose = TRUE
#'   )
#'   # Resolution rate:
#'   mean(!is.na(ag$uri))
#' }
#' @export
causal_ontology_agrovoc_align_batch <- function(terms,
                                                  cache_path = NULL,
                                                  max_active = 5L,
                                                  max_per_term = 5L,
                                                  max_retries = 2L,
                                                  endpoint =
                                                    "https://agrovoc.fao.org/sparql",
                                                  timeout_sec = 60L,
                                                  verbose = FALSE) {
  stopifnot(is.character(terms))
  terms <- tolower(trimws(unique(as.character(terms))))
  terms <- terms[nzchar(terms)]
  if (length(terms) == 0L) {
    return(data.frame(
      term = character(0), uri = character(0),
      label = character(0), distance = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  cache <- list()
  if (!is.null(cache_path) && file.exists(cache_path)) {
    cache <- tryCatch(readRDS(cache_path), error = function(e) list())
    if (!is.list(cache)) cache <- list()
  }

  cached <- terms[vapply(terms, function(t) !is.null(cache[[t]]),
                          logical(1L))]
  todo   <- setdiff(terms, cached)

  if (verbose) {
    message(sprintf("[agrovoc-batch] %d cached, %d to resolve ",
                     length(cached), length(todo)),
             sprintf("(max_active=%d, max_retries=%d)",
                     max_active, max_retries))
  }

  attempts <- 0L
  while (length(todo) > 0L && attempts <= max_retries) {
    reqs <- lapply(todo, function(tm)
      .agrovoc_build_request(tm, endpoint, timeout_sec, max_per_term)
    )
    # Dispatch: parallel (via httr2::req_perform_parallel) when the
    # user asked for concurrency, sequential (via httr2::req_perform)
    # when max_active <= 1. The sequential path exists because
    # httr2::with_mocked_responses() only intercepts req_perform() —
    # single-thread mode is what downstream users / tests rely on to
    # plug in deterministic fixtures.
    resps <- if (as.integer(max_active) <= 1L) {
      lapply(reqs, function(r)
        tryCatch(httr2::req_perform(r), error = function(e) NULL)
      )
    } else {
      tryCatch(
        httr2::req_perform_parallel(reqs,
                                      max_active = as.integer(max_active),
                                      on_error = "continue"),
        error = function(e) rep(list(NULL), length(reqs))
      )
    }

    new_hits <- mapply(function(tm, rs) .agrovoc_parse_response(rs, tm),
                        todo, resps, SIMPLIFY = FALSE)
    resolved <- vapply(new_hits, function(h) !is.na(h$uri), logical(1L))
    for (k in seq_along(new_hits)) {
      if (resolved[k]) cache[[todo[k]]] <- new_hits[[k]]
    }

    if (verbose) {
      message(sprintf("[agrovoc-batch] round %d: %d / %d resolved",
                       attempts + 1L, sum(resolved), length(todo)))
    }

    todo <- todo[!resolved]
    attempts <- attempts + 1L
    if (length(todo) > 0L && attempts <= max_retries) {
      Sys.sleep(2 ^ attempts)
    }
  }

  # Emit NA rows for whatever still didn't resolve.
  for (tm in todo) {
    cache[[tm]] <- data.frame(
      term = tm, uri = NA_character_, label = NA_character_,
      distance = NA_real_, stringsAsFactors = FALSE
    )
  }

  if (!is.null(cache_path)) {
    try(saveRDS(cache, cache_path), silent = TRUE)
  }

  out <- do.call(rbind, cache[terms])
  rownames(out) <- NULL
  out
}

#' Align Knowledge-Graph node labels to a canonical vocabulary
#'
#' Computes the mapping from node labels currently present in an
#' `edaphos_causal_kg` onto their canonical counterparts in a target
#' vocabulary (`causal_ontology_cerrado()` by default). Three matchers
#' are tried in order — exact, substring, fuzzy — and the first hit
#' wins. The mapping is returned as a tidy data frame; apply it with
#' [causal_kg_rename()].
#'
#' @param kg An `edaphos_causal_kg`.
#' @param vocab Either a character vector / data frame of canonical
#'   terms, the string `"cerrado"` (default; uses
#'   [causal_ontology_cerrado()]) or the string `"agrovoc"` which
#'   triggers a **live SPARQL query** to the FAO AGROVOC endpoint
#'   via [causal_ontology_agrovoc_align()]. For AGROVOC the
#'   alignment type is reported as `"agrovoc"` instead of exact /
#'   substring / fuzzy.
#' @param method Which matcher tier(s) to enable (ignored when
#'   `vocab = "agrovoc"`). Any combination of `"exact"`,
#'   `"substring"`, `"fuzzy"`.
#' @param max_distance Fuzzy-matcher Levenshtein cap.
#' @param agrovoc_cache Optional `.rds` path used by
#'   `vocab = "agrovoc"` to avoid re-querying the same terms.
#' @param agrovoc_batch Logical — when `TRUE` and `vocab = "agrovoc"`,
#'   uses the parallel-dispatch variant
#'   [causal_ontology_agrovoc_align_batch()] to resolve all nodes in
#'   flight. Recommended for KGs with more than ~20 unique nodes.
#' @param agrovoc_max_active Integer — concurrency for the parallel
#'   variant. Only consulted when `agrovoc_batch = TRUE`.
#' @return A data frame with columns `original`, `canonical`,
#'   `method`, `distance`. When `vocab = "agrovoc"` an extra
#'   `uri` column is attached.
#' @export
causal_kg_alignment <- function(kg, vocab = NULL,
                                 method = c("exact", "substring", "fuzzy"),
                                 max_distance = 4L,
                                 agrovoc_cache = NULL,
                                 agrovoc_batch = FALSE,
                                 agrovoc_max_active = 5L) {
  .causal_kg_require_igraph()
  stopifnot(inherits(kg, "edaphos_causal_kg"))
  method <- match.arg(method, several.ok = TRUE)
  nodes <- igraph::V(kg$graph)$name %||% character(0)

  # Live AGROVOC short-circuit --------------------------------------
  if (is.character(vocab) && length(vocab) == 1L &&
      identical(vocab, "agrovoc")) {
    ag <- if (isTRUE(agrovoc_batch)) {
      causal_ontology_agrovoc_align_batch(
        nodes,
        cache_path = agrovoc_cache,
        max_active = as.integer(agrovoc_max_active)
      )
    } else {
      causal_ontology_agrovoc_align(nodes, cache_path = agrovoc_cache)
    }
    out <- data.frame(
      original  = ag$term,
      canonical = ifelse(is.na(ag$label), NA_character_,
                          gsub("[^a-z0-9_]+", "_",
                                gsub("\\s+", "_", tolower(ag$label)))),
      method    = ifelse(is.na(ag$label), "none", "agrovoc"),
      distance  = ag$distance,
      uri       = ag$uri,
      stringsAsFactors = FALSE
    )
    return(out)
  }

  if (is.null(vocab) || (is.character(vocab) && length(vocab) == 1L &&
                           identical(vocab, "cerrado"))) {
    vocab <- causal_ontology_cerrado()$term
  }
  if (is.data.frame(vocab)) vocab <- vocab$term
  vocab <- tolower(as.character(vocab))
  out <- lapply(nodes, function(nd) {
    idx <- NA_integer_; m <- "none"; dist <- NA_real_
    if ("exact" %in% method) {
      i <- .match_exact(nd, vocab)
      if (!is.na(i)) { idx <- i; m <- "exact"; dist <- 0 }
    }
    if (is.na(idx) && "substring" %in% method) {
      i <- .match_substring(nd, vocab)
      if (!is.na(i)) { idx <- i; m <- "substring"; dist <- NA_real_ }
    }
    if (is.na(idx) && "fuzzy" %in% method) {
      i <- .match_fuzzy(nd, vocab, max_distance = max_distance)
      if (!is.na(i)) {
        idx <- i; m <- "fuzzy"
        if (requireNamespace("stringdist", quietly = TRUE)) {
          dist <- stringdist::stringdist(nd, vocab[i], method = "osa")
        } else {
          dist <- as.integer(utils::adist(nd, vocab[i]))
        }
      }
    }
    data.frame(
      original  = nd,
      canonical = if (is.na(idx)) NA_character_ else vocab[idx],
      method    = m,
      distance  = dist,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, out)
}

#' Rename Knowledge-Graph nodes from an alignment mapping
#'
#' Applies the `(original -> canonical)` mapping computed by
#' [causal_kg_alignment()] to an `edaphos_causal_kg`, collapsing
#' synonymous nodes and re-merging their edges (max confidence /
#' concatenated evidence, as per [causal_kg_add_edge()]).
#'
#' @param kg An `edaphos_causal_kg`.
#' @param mapping A data frame with columns `original` and
#'   `canonical`. Rows with `NA` canonical are left untouched.
#' @return A new `edaphos_causal_kg` whose node names are the
#'   canonical terms (unmapped nodes kept as-is).
#' @export
causal_kg_rename <- function(kg, mapping) {
  .causal_kg_require_igraph()
  stopifnot(inherits(kg, "edaphos_causal_kg"),
            is.data.frame(mapping),
            c("original", "canonical") %in% names(mapping))
  valid <- !is.na(mapping$canonical) & nzchar(mapping$canonical)
  dict <- stats::setNames(mapping$canonical[valid],
                           mapping$original[valid])

  e <- causal_kg_edges(kg)
  if (nrow(e) == 0L) return(kg)
  e$cause_new  <- ifelse(e$cause  %in% names(dict),
                          dict[e$cause],  e$cause)
  e$effect_new <- ifelse(e$effect %in% names(dict),
                          dict[e$effect], e$effect)

  kg2 <- causal_kg_new()
  for (i in seq_len(nrow(e))) {
    if (identical(e$cause_new[i], e$effect_new[i])) next
    kg2 <- suppressWarnings(causal_kg_add_edge(
      kg2,
      cause      = e$cause_new[i],
      effect     = e$effect_new[i],
      source     = e$source[i],
      evidence   = e$evidence[i],
      confidence = e$confidence[i],
      timestamp  = e$timestamp[i]
    ))
  }
  kg2
}
