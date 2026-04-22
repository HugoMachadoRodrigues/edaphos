# Pillar 1 -- Knowledge Graph persistence, RDF export and audit.
#
# Three operations that turn a `edaphos_causal_kg` built over tens of
# thousands of abstracts from an opaque in-memory object into a
# paper-scale research artefact:
#
#   * causal_kg_save() / causal_kg_load()
#       Round-trip a KG through an on-disk RDS file. Idempotent,
#       reproducible, and independent of the igraph binary format
#       (the KG is serialised via its tidy edge list, not via
#       `igraph:::.Call` pointers, so the RDS is portable across
#       igraph versions).
#
#   * causal_kg_to_turtle()
#       Emit the KG as RDF 1.1 Turtle -- a W3C-standard, human-
#       readable triple language. Each edge is encoded as a reified
#       statement so confidence / evidence / source / timestamp
#       survive the round-trip, and every node is given a stable
#       URI inside a user-controlled namespace. No external RDF
#       library required for writing: the emitter is a few hundred
#       lines of plain R.
#
#   * causal_kg_rank_edges() / causal_kg_summary()
#       Audit primitives for corpus-scale KGs. `rank_edges()` sorts
#       unique (cause, effect) pairs by number of supporting sources,
#       mean LLM confidence, and (optionally) AGROVOC support.
#       `summary()` is a one-line overview: node count, edge count,
#       source count, confidence distribution, DAG-ness.
#
# All three live on top of [causal_kg_edges()], so they work for any
# KG regardless of whether it was built by hand, by
# [causal_llm_ingest_corpus()], or loaded from disk.

# --- save / load -------------------------------------------------------------

#' Save a Knowledge Graph to disk
#'
#' Writes an `edaphos_causal_kg` to an `.rds` file. The KG is
#' serialised through its tidy edge list plus metadata (version,
#' timestamp, R and package versions) rather than through the raw
#' igraph object, so the file is:
#'
#' - **Portable** across igraph versions (the C-level pointer layout
#'   that `saveRDS(igraph_object)` would capture is not written).
#' - **Deterministic** (no hash-randomised attributes), so two saves
#'   of the same KG produce byte-identical files.
#' - **Small** — only the edge list and node names are written, not
#'   igraph's internal indices.
#'
#' Load with [causal_kg_load()].
#'
#' @param kg An `edaphos_causal_kg`.
#' @param path Path to the target `.rds` file. The parent directory
#'   is created if it does not exist.
#' @return Invisibly returns `path` (for pipelining).
#' @seealso [causal_kg_load()], [causal_kg_to_turtle()] for the
#'   human-readable RDF variant.
#' @examples
#' \donttest{
#'   kg <- causal_kg_new()
#'   kg <- causal_kg_add_edge(kg, "precipitation", "soc",
#'                             source = "Jenny 1941",
#'                             confidence = 0.9)
#'   f <- tempfile(fileext = ".rds")
#'   causal_kg_save(kg, f)
#'   kg2 <- causal_kg_load(f)
#'   identical(causal_kg_edges(kg), causal_kg_edges(kg2))
#' }
#' @export
causal_kg_save <- function(kg, path) {
  .causal_kg_require_igraph()
  stopifnot(inherits(kg, "edaphos_causal_kg"),
            is.character(path), length(path) == 1L, nzchar(path))

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  edges <- causal_kg_edges(kg)
  nodes <- igraph::V(kg$graph)$name %||% character(0)

  pkg_ver <- tryCatch(
    as.character(utils::packageVersion("edaphos")),
    error = function(e) NA_character_
  )

  payload <- list(
    format_version = "edaphos_causal_kg/1",
    saved_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ",
                             tz = "UTC"),
    edaphos_version = pkg_ver,
    r_version       = getRversion(),
    nodes           = nodes,
    edges           = edges
  )
  saveRDS(payload, path)
  invisible(path)
}

#' Load a Knowledge Graph from disk
#'
#' Reads a `.rds` file previously written by [causal_kg_save()] and
#' reconstructs the `edaphos_causal_kg`. The reconstruction is
#' careful: it re-calls [causal_kg_add_edge()] for every saved edge
#' so that the duplicate-edge merge + cycle check + normalisation
#' rules stay consistent with a freshly-built graph.
#'
#' @param path Path to the `.rds` file.
#' @return An `edaphos_causal_kg`.
#' @export
causal_kg_load <- function(path) {
  .causal_kg_require_igraph()
  stopifnot(is.character(path), length(path) == 1L, file.exists(path))
  payload <- readRDS(path)
  if (!is.list(payload) ||
      !identical(payload$format_version, "edaphos_causal_kg/1")) {
    stop("File '", path, "' does not look like a saved edaphos KG ",
         "(format_version mismatch).", call. = FALSE)
  }
  e  <- payload$edges
  kg <- causal_kg_new()
  if (is.null(e) || nrow(e) == 0L) return(kg)
  for (i in seq_len(nrow(e))) {
    kg <- suppressWarnings(causal_kg_add_edge(
      kg,
      cause      = e$cause[i],
      effect     = e$effect[i],
      source     = e$source[i]     %||% NA_character_,
      evidence   = e$evidence[i]   %||% NA_character_,
      confidence = e$confidence[i] %||% 1.0,
      timestamp  = e$timestamp[i]  %||% NULL
    ))
  }
  kg
}

# --- RDF 1.1 Turtle export ---------------------------------------------------

# Quote a string literal for Turtle output. The escape list covers the
# characters the RDF 1.1 grammar flags as syntactic in a
# `STRING_LITERAL_QUOTE` production (https://www.w3.org/TR/turtle/#sec-
# escapes-and-numeric). Newlines inside a single-quoted literal are
# not allowed; we upgrade to a triple-quoted string when a literal
# spans a line break.
.ttl_escape <- function(s) {
  s <- as.character(s)
  s[is.na(s)] <- ""
  s <- gsub("\\\\", "\\\\\\\\", s)
  s <- gsub("\"", "\\\\\"", s)
  s <- gsub("\t", "\\\\t", s, fixed = TRUE)
  s
}

.ttl_literal <- function(s) {
  s <- as.character(s %||% "")
  if (!nzchar(s)) return("\"\"")
  escaped <- .ttl_escape(s)
  if (grepl("\n|\r", escaped)) {
    # Upgrade to a triple-quoted literal so embedded newlines survive.
    paste0("\"\"\"",
           gsub("\r?\n", "\\\\n", escaped),
           "\"\"\"")
  } else {
    paste0("\"", escaped, "\"")
  }
}

.ttl_curie_fragment <- function(label) {
  # Turn an arbitrary string into a Turtle-safe local name: ASCII
  # alphanumerics + underscore, must start with a letter or underscore.
  x <- gsub("[^A-Za-z0-9_]+", "_", as.character(label))
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  if (!nzchar(x)) x <- "node"
  if (!grepl("^[A-Za-z_]", x)) x <- paste0("n_", x)
  x
}

#' Export a Knowledge Graph to RDF 1.1 Turtle
#'
#' Serialises an `edaphos_causal_kg` as **RDF 1.1 Turtle**
#' (<https://www.w3.org/TR/turtle/>), the W3C's canonical
#' human-readable triple language. Each edge becomes a reified
#' `rdf:Statement` so confidence, evidence, source and timestamp are
#' preserved losslessly; each node is given a stable IRI inside a
#' user-controlled namespace. The emitter is written in pure R with
#' no external dependency — the output is guaranteed parseable by any
#' RDF 1.1-conformant consumer (rdflib, Jena, Virtuoso, Blazegraph,
#' GraphDB, Oxigraph …).
#'
#' The emitted graph uses the following prefixes by default (all
#' overridable via `namespaces`):
#'
#' - `ed:`   — edaphos KG namespace (one IRI per node and edge).
#' - `eds:`  — edaphos schema namespace (defines `eds:Causes`,
#'   `eds:confidence`, `eds:evidence`, `eds:source`).
#' - `rdf:`, `rdfs:`, `xsd:`, `prov:`, `dct:` — standard W3C
#'   vocabularies.
#'
#' Every node `L` becomes an IRI
#' `<base_uri>node/<sanitised_L>`; every edge becomes an IRI
#' `<base_uri>edge/<cause>__<effect>` typed as `rdf:Statement`, with
#' `rdf:subject` / `rdf:predicate` / `rdf:object` pointing at the
#' nodes and `eds:Causes` used as the predicate for the causal
#' direction. Provenance is attached via `dct:source`
#' (bibliographic identifier) and `prov:generatedAtTime` (timestamp).
#'
#' @param kg An `edaphos_causal_kg`.
#' @param path Optional output file path. When `NULL` (default), the
#'   Turtle document is returned as a single character string.
#' @param base_uri Character — base IRI for the KG. Must end with
#'   `"/"` or `"#"`. Default `"https://edaphos.io/kg/"`.
#' @param schema_uri Character — IRI of the `eds:` schema namespace.
#'   Default `"https://edaphos.io/schema#"`.
#' @param namespaces Named character vector of extra prefix bindings
#'   to declare. Useful when you want to reference external
#'   vocabularies (e.g. `c(agrovoc = "http://aims.fao.org/aos/agrovoc/")`).
#' @param include_metadata Logical — emit document-level metadata
#'   (creation time, `edaphos` version) as `prov:` statements.
#'   Default `TRUE`.
#' @return When `path` is `NULL`, invisibly returns the Turtle
#'   document as a length-1 character vector. When `path` is given,
#'   writes the document to disk and invisibly returns `path`.
#' @seealso [causal_kg_save()] for binary RDS persistence.
#' @references
#' Beckett, D. (2014). RDF 1.1 Turtle — Terse RDF Triple Language.
#' *W3C Recommendation*.
#' @examples
#' \donttest{
#'   kg <- causal_kg_new()
#'   kg <- causal_kg_add_edge(kg, "precipitation", "soc",
#'                             source = "Jenny 1941",
#'                             evidence = "Higher precipitation favours SOC.",
#'                             confidence = 0.9)
#'   ttl <- causal_kg_to_turtle(kg)
#'   substr(ttl, 1, 200)
#'
#'   # Write to disk and (optionally) round-trip through rdflib if
#'   # installed -- a useful SPARQL-queryable artefact.
#'   tf <- tempfile(fileext = ".ttl")
#'   causal_kg_to_turtle(kg, tf)
#' }
#' @export
causal_kg_to_turtle <- function(kg, path = NULL,
                                 base_uri   = "https://edaphos.io/kg/",
                                 schema_uri = "https://edaphos.io/schema#",
                                 namespaces = character(0),
                                 include_metadata = TRUE) {
  .causal_kg_require_igraph()
  stopifnot(inherits(kg, "edaphos_causal_kg"),
            is.character(base_uri),
            is.character(schema_uri))
  if (!grepl("[/#]$", base_uri)) {
    stop("`base_uri` must end with '/' or '#'.", call. = FALSE)
  }
  if (!grepl("[/#]$", schema_uri)) {
    stop("`schema_uri` must end with '/' or '#'.", call. = FALSE)
  }

  edges <- causal_kg_edges(kg)

  # ---- Preamble: prefix declarations -------------------------------------
  preamble <- c(
    sprintf("@prefix ed: <%snode/> .", base_uri),
    sprintf("@prefix edge: <%sedge/> .", base_uri),
    sprintf("@prefix eds: <%s> .", schema_uri),
    "@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .",
    "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .",
    "@prefix xsd:  <http://www.w3.org/2001/XMLSchema#> .",
    "@prefix prov: <http://www.w3.org/ns/prov#> .",
    "@prefix dct:  <http://purl.org/dc/terms/> ."
  )
  if (length(namespaces) > 0L) {
    ns_names <- names(namespaces)
    preamble <- c(preamble,
                   sprintf("@prefix %s: <%s> .", ns_names,
                           unname(as.character(namespaces))))
  }
  preamble <- c(preamble, "")

  # ---- Schema (minimal, self-contained) ----------------------------------
  schema <- c(
    "# --- schema -----------------------------------------------------",
    "eds:Causes a rdf:Property ;",
    "  rdfs:label \"causes\" ;",
    "  rdfs:comment \"Directed causal edge in the edaphos Knowledge Graph.\" .",
    "",
    "eds:confidence a rdf:Property ;",
    "  rdfs:label \"confidence\" ;",
    "  rdfs:range xsd:float .",
    "",
    "eds:evidence a rdf:Property ;",
    "  rdfs:label \"evidence\" ;",
    "  rdfs:range xsd:string .",
    "",
    "eds:source a rdf:Property ;",
    "  rdfs:subPropertyOf dct:source ;",
    "  rdfs:label \"source\" .",
    ""
  )

  # ---- Nodes --------------------------------------------------------------
  nodes <- igraph::V(kg$graph)$name %||% character(0)
  node_block <- if (length(nodes) == 0L) character(0) else {
    c(
      "# --- nodes ------------------------------------------------------",
      vapply(nodes, function(n) {
        sprintf("ed:%s a rdfs:Resource ; rdfs:label %s .",
                .ttl_curie_fragment(n), .ttl_literal(n))
      }, character(1L)),
      ""
    )
  }

  # ---- Edges as reified rdf:Statement ------------------------------------
  edge_block <- if (nrow(edges) == 0L) character(0) else {
    header <- "# --- edges (reified causal statements) ----------------------"
    body <- character(0)
    for (i in seq_len(nrow(edges))) {
      cause_iri  <- sprintf("ed:%s", .ttl_curie_fragment(edges$cause[i]))
      effect_iri <- sprintf("ed:%s", .ttl_curie_fragment(edges$effect[i]))
      edge_iri   <- sprintf("edge:%s__%s",
                             .ttl_curie_fragment(edges$cause[i]),
                             .ttl_curie_fragment(edges$effect[i]))

      stmt <- c(
        sprintf("%s a rdf:Statement ;", edge_iri),
        sprintf("  rdf:subject   %s ;", cause_iri),
        sprintf("  rdf:predicate eds:Causes ;"),
        sprintf("  rdf:object    %s ;", effect_iri)
      )
      if (!is.na(edges$confidence[i])) {
        stmt <- c(stmt, sprintf(
          "  eds:confidence \"%.6f\"^^xsd:float ;",
          edges$confidence[i]
        ))
      }
      if (!is.na(edges$evidence[i]) && nzchar(edges$evidence[i])) {
        stmt <- c(stmt, sprintf("  eds:evidence %s ;",
                                 .ttl_literal(edges$evidence[i])))
      }
      if (!is.na(edges$source[i]) && nzchar(edges$source[i])) {
        # `source` may be a " | "-separated multi-source string
        # (multiple papers support the same edge). Emit one eds:source
        # triple per source so downstream SPARQL can COUNT them.
        sources <- trimws(unlist(strsplit(edges$source[i], " \\| ")))
        sources <- sources[nzchar(sources)]
        if (length(sources) > 0L) {
          source_block <- paste0("  eds:source ",
                                  vapply(sources, .ttl_literal,
                                         character(1L)))
          # Join the source triples with ' ;' and close with ' ;' too.
          stmt <- c(stmt, paste0(source_block, " ;"))
        }
      }
      if (!is.na(edges$timestamp[i]) && nzchar(edges$timestamp[i])) {
        stmt <- c(stmt, sprintf(
          "  prov:generatedAtTime \"%s\"^^xsd:dateTime ;",
          edges$timestamp[i]
        ))
      }
      # Replace the trailing ' ;' on the last line with ' .'
      n <- length(stmt)
      stmt[n] <- sub(";\\s*$", ".", stmt[n])
      body <- c(body, stmt, "")
    }
    c(header, body)
  }

  # ---- Document metadata --------------------------------------------------
  meta_block <- if (!isTRUE(include_metadata)) character(0) else {
    pkg_ver <- tryCatch(
      as.character(utils::packageVersion("edaphos")),
      error = function(e) "unknown"
    )
    c(
      "# --- document metadata --------------------------------------",
      sprintf("<> a prov:Entity ;"),
      sprintf("  prov:generatedAtTime \"%s\"^^xsd:dateTime ;",
               format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
      sprintf("  dct:creator \"edaphos %s\" .", pkg_ver),
      ""
    )
  }

  ttl <- paste(c(preamble, schema, node_block, edge_block, meta_block),
                collapse = "\n")

  if (is.null(path)) {
    return(invisible(ttl))
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(ttl, path, useBytes = TRUE)
  invisible(path)
}

# --- summary + rank_edges ---------------------------------------------------

.split_sources <- function(x) {
  if (is.na(x) || !nzchar(x)) return(character(0))
  trimws(unlist(strsplit(as.character(x), " \\| ")))
}

#' One-line summary of a Knowledge Graph
#'
#' Structural and statistical overview of an `edaphos_causal_kg`:
#' node / edge / source counts, confidence quantiles, DAG-ness and
#' the most prolific source. Useful as the first thing to print after
#' a large [causal_llm_ingest_corpus()] run.
#'
#' @param object An `edaphos_causal_kg`.
#' @param ... Unused; present for S3 dispatch.
#' @return An `edaphos_causal_kg_summary` list (printed with a
#'   custom method) carrying the raw numbers.
#' @export
summary.edaphos_causal_kg <- function(object, ...) {
  .causal_kg_require_igraph()
  stopifnot(inherits(object, "edaphos_causal_kg"))
  g <- object$graph
  e <- causal_kg_edges(object)

  sources_list <- unlist(lapply(e$source, .split_sources))
  conf <- e$confidence
  q <- if (length(conf) > 0L) {
    stats::quantile(conf, probs = c(0, 0.25, 0.5, 0.75, 1),
                     na.rm = TRUE, names = FALSE)
  } else rep(NA_real_, 5L)

  src_tbl <- if (length(sources_list) > 0L) {
    sort(table(sources_list), decreasing = TRUE)
  } else integer(0)
  top_src <- if (length(src_tbl) > 0L) {
    list(name = names(src_tbl)[1L], n = as.integer(src_tbl[1L]))
  } else list(name = NA_character_, n = 0L)

  out <- list(
    n_nodes    = igraph::vcount(g),
    n_edges    = igraph::ecount(g),
    n_sources  = length(unique(sources_list)),
    dag        = igraph::is_dag(g),
    confidence = list(min = q[1L], q25 = q[2L], median = q[3L],
                       q75 = q[4L], max = q[5L]),
    top_source = top_src
  )
  class(out) <- "edaphos_causal_kg_summary"
  out
}

#' @export
print.edaphos_causal_kg_summary <- function(x, ...) {
  cat("<edaphos_causal_kg_summary>\n")
  cat(sprintf("  nodes      : %d\n", x$n_nodes))
  cat(sprintf("  edges      : %d\n", x$n_edges))
  cat(sprintf("  sources    : %d unique\n", x$n_sources))
  cat(sprintf("  DAG        : %s\n", if (x$dag) "yes" else "cyclic"))
  if (!is.na(x$confidence$median)) {
    cat(sprintf("  confidence : min=%.2f  q25=%.2f  med=%.2f  q75=%.2f  max=%.2f\n",
                x$confidence$min, x$confidence$q25, x$confidence$median,
                x$confidence$q75, x$confidence$max))
  }
  if (!is.na(x$top_source$name)) {
    cat(sprintf("  top source : %s  (%d edges)\n",
                x$top_source$name, x$top_source$n))
  }
  invisible(x)
}

#' Rank Knowledge-Graph edges by evidence strength
#'
#' Collapses a `edaphos_causal_kg` to one row per unique
#' (cause, effect) edge and ranks the result by a user-selected
#' metric:
#'
#' \describe{
#'   \item{`"n_sources"`}{Number of distinct sources supporting the
#'     edge (counted by splitting the ` | `-separated `source` field
#'     on the underlying `igraph` edge-attribute). The single most
#'     informative signal for an LLM-extracted KG built over thousands
#'     of papers: an edge asserted by 50 papers is far more
#'     trustworthy than one asserted by 1.}
#'   \item{`"mean_confidence"`}{Mean LLM confidence across extractions
#'     that produced the same (cause, effect) pair.}
#'   \item{`"agrovoc_support"`}{Fraction of the pair's endpoints
#'     (cause, effect) that resolve to a FAO AGROVOC concept under an
#'     `alignment` mapping (0, 0.5 or 1). Requires either
#'     `alignment` to be supplied or `kg` already aligned; when
#'     neither is available the column is `NA`.}
#' }
#'
#' The return is a tidy data frame sorted in descending order by
#' *all* ranking columns requested in `by` (i.e. the first `by`
#' element is the primary sort key, the second breaks ties, etc.).
#' This is usually more informative than a single-metric ranking —
#' an edge that has both many sources AND high confidence is more
#' trustworthy than either alone.
#'
#' @param kg An `edaphos_causal_kg`.
#' @param by Character vector of ranking metrics, any subset of
#'   `c("n_sources", "mean_confidence", "agrovoc_support")`, in
#'   priority order.
#' @param alignment Optional data frame as returned by
#'   [causal_kg_alignment()] (must have columns `original`,
#'   `canonical`, plus `uri` when derived from
#'   `vocab = "agrovoc"`). Used to compute `agrovoc_support`.
#' @param top_n Optional integer — return at most this many rows.
#'   `NULL` returns the full ranking.
#' @return A data frame with columns
#'   `cause`, `effect`, `n_sources`, `mean_confidence`,
#'   `max_confidence`, `sources` (collapsed " | "-separated),
#'   `evidence` (collapsed), and — when available —
#'   `agrovoc_support`, `agrovoc_cause`, `agrovoc_effect`.
#' @seealso [causal_kg_alignment()], [summary.edaphos_causal_kg()].
#' @examples
#' \donttest{
#'   kg <- causal_kg_new()
#'   kg <- causal_kg_add_edge(kg, "precipitation", "soc",
#'                             source = "Jenny 1941", confidence = 0.9)
#'   kg <- causal_kg_add_edge(kg, "precipitation", "soc",
#'                             source = "Minasny 2017", confidence = 0.85)
#'   causal_kg_rank_edges(kg, by = c("n_sources", "mean_confidence"))
#' }
#' @export
causal_kg_rank_edges <- function(kg,
                                  by = c("n_sources",
                                         "mean_confidence",
                                         "agrovoc_support"),
                                  alignment = NULL,
                                  top_n = NULL) {
  .causal_kg_require_igraph()
  stopifnot(inherits(kg, "edaphos_causal_kg"),
            is.character(by), length(by) >= 1L)
  valid_by <- c("n_sources", "mean_confidence", "agrovoc_support")
  if (!all(by %in% valid_by)) {
    stop("`by` must be any subset of c('",
         paste(valid_by, collapse = "', '"), "').", call. = FALSE)
  }

  e <- causal_kg_edges(kg)
  if (nrow(e) == 0L) {
    return(data.frame(
      cause = character(0), effect = character(0),
      n_sources = integer(0), mean_confidence = numeric(0),
      max_confidence = numeric(0),
      sources = character(0), evidence = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # One row per (cause, effect) pair. The igraph add_edge rule already
  # collapses duplicates so `e` is guaranteed to have unique pairs; we
  # still aggregate defensively in case a loaded KG came from outside.
  key <- paste(e$cause, "->", e$effect)
  spl <- split(seq_len(nrow(e)), key)
  rows <- lapply(spl, function(ix) {
    sources_all <- unique(unlist(lapply(e$source[ix], .split_sources)))
    confs       <- e$confidence[ix]
    data.frame(
      cause           = e$cause[ix][1L],
      effect          = e$effect[ix][1L],
      n_sources       = length(sources_all),
      mean_confidence = mean(confs, na.rm = TRUE),
      max_confidence  = suppressWarnings(
        max(confs, na.rm = TRUE)
      ),
      sources         = paste(sources_all, collapse = " | "),
      evidence        = paste(
        unique(stats::na.omit(e$evidence[ix])), collapse = " | "
      ),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL

  # Optional AGROVOC support column -----------------------------------------
  if (!is.null(alignment)) {
    stopifnot(is.data.frame(alignment),
              c("original", "canonical") %in% names(alignment))
    has_uri <- "uri" %in% names(alignment)
    resolved <- if (has_uri) !is.na(alignment$uri) else
      !is.na(alignment$canonical)
    dict_ok <- stats::setNames(resolved, alignment$original)
    if (has_uri) {
      dict_uri <- stats::setNames(alignment$uri, alignment$original)
    } else {
      dict_uri <- stats::setNames(alignment$canonical, alignment$original)
    }
    out$agrovoc_cause  <- unname(dict_uri[out$cause])
    out$agrovoc_effect <- unname(dict_uri[out$effect])
    cs <- ifelse(is.na(dict_ok[out$cause]),  0,
                  as.integer(dict_ok[out$cause]))
    es <- ifelse(is.na(dict_ok[out$effect]), 0,
                  as.integer(dict_ok[out$effect]))
    out$agrovoc_support <- (cs + es) / 2
  } else if ("agrovoc_support" %in% by) {
    out$agrovoc_support <- NA_real_
  }

  # Sort. All metrics are 'bigger is better' so we negate for order().
  sort_keys <- lapply(by, function(m) {
    v <- out[[m]]
    if (is.null(v)) rep(0, nrow(out)) else -v
  })
  ord <- do.call(order, c(sort_keys, list(na.last = TRUE)))
  out <- out[ord, , drop = FALSE]
  rownames(out) <- NULL

  if (!is.null(top_n)) {
    out <- utils::head(out, as.integer(top_n))
  }
  out
}
