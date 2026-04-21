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
#' @return A data frame with columns `uri` (AGROVOC concept URI) and
#'   `term` (canonical lower-snake-case label).
#' @export
#' @examples
#' \dontrun{
#'   causal_ontology_agrovoc("soil organic carbon", limit = 5)
#' }
causal_ontology_agrovoc <- function(query, limit = 10L,
                                     timeout_sec = 60L) {
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
  req  <- httr2::request("https://agrovoc.fao.org/sparql")
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
#' @param vocab Character vector (or data frame with column `term`)
#'   of canonical terms. Defaults to [causal_ontology_cerrado()].
#' @param method Which matcher tier(s) to enable. Any combination of
#'   `"exact"`, `"substring"`, `"fuzzy"`. They are tried in order.
#' @param max_distance Fuzzy-matcher Levenshtein cap.
#' @return A data frame with columns `original`, `canonical`,
#'   `method`, `distance` (NA for non-fuzzy tiers).
#' @export
causal_kg_alignment <- function(kg, vocab = NULL,
                                 method = c("exact", "substring", "fuzzy"),
                                 max_distance = 4L) {
  .causal_kg_require_igraph()
  stopifnot(inherits(kg, "edaphos_causal_kg"))
  if (is.null(vocab)) vocab <- causal_ontology_cerrado()$term
  if (is.data.frame(vocab)) vocab <- vocab$term
  vocab <- tolower(as.character(vocab))
  method <- match.arg(method, several.ok = TRUE)

  nodes <- igraph::V(kg$graph)$name %||% character(0)
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
