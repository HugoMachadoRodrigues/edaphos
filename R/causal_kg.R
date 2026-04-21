# Pillar 1 — Knowledge Graph backbone.
#
# The Knowledge Graph (KG) is an S3 object `edaphos_causal_kg` that
# wraps an `igraph` directed graph whose edges carry provenance
# (source paper, evidence quote, confidence). It is the substrate
# that LLM-driven extraction (R/causal_llm.R) populates, and that
# the backdoor-adjustment estimator (R/causal_dag.R) consumes after
# projection onto a `dagitty` DAG.
#
# All `igraph` touchpoints are soft: if the package is not installed,
# `causal_kg_new()` errors loudly, but the rest of edaphos loads
# cleanly.

.causal_kg_require_igraph <- function() {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Install the `igraph` package to use causal_kg_*() helpers.",
         call. = FALSE)
  }
  invisible(TRUE)
}

.normalise_node <- function(x) {
  # Lower-case, trim, replace whitespace and hyphens with underscores,
  # strip any remaining non-[A-Za-z0-9_] characters so that the label
  # round-trips safely through `dagitty`'s DAG grammar.
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[-\\s]+", "_", x, perl = TRUE)
  x <- gsub("[^a-z0-9_]", "", x)
  # Collapse runs of underscores, trim underscores at the edges.
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  x
}

#' Create an empty pedogenetic Knowledge Graph
#'
#' Initialises an empty, directed `edaphos_causal_kg` object. Edges are
#' added with [causal_kg_add_edge()] — each edge carries four
#' metadata attributes: `source` (bibliographic or textual provenance),
#' `evidence` (a short quotation supporting the claim), `confidence`
#' (value in `[0, 1]`, typically returned by an LLM extractor), and
#' `timestamp` (ISO 8601, auto-recorded).
#'
#' @return An `edaphos_causal_kg` object (S3) containing an empty
#'   directed `igraph`.
#' @export
#' @examples
#' \donttest{
#'   kg <- causal_kg_new()
#'   kg <- causal_kg_add_edge(
#'     kg, "precipitation", "soc",
#'     source     = "Jenny 1941",
#'     evidence   = "Higher precipitation favours organic-matter accumulation.",
#'     confidence = 0.9
#'   )
#'   causal_kg_edges(kg)
#' }
causal_kg_new <- function() {
  .causal_kg_require_igraph()
  g <- igraph::make_empty_graph(n = 0L, directed = TRUE)
  structure(list(graph = g), class = "edaphos_causal_kg")
}

#' Add a causal edge to a pedogenetic Knowledge Graph
#'
#' @param kg An `edaphos_causal_kg` returned by [causal_kg_new()].
#' @param cause,effect Character scalar — the causal exposure and the
#'   outcome node. Node names are normalised to lower-snake-case.
#' @param source Character scalar with a bibliographic key or human
#'   description of the evidence source (e.g. `"Jenny 1941"`,
#'   `"Minasny et al. 2017"`).
#' @param evidence Character scalar with a short quotation supporting
#'   the claim (max ~200 characters recommended).
#' @param confidence Numeric in `[0, 1]` — the LLM's or annotator's
#'   confidence that the claim is supported by the evidence.
#' @param timestamp Character ISO 8601 timestamp. Defaults to
#'   `Sys.time()`.
#'
#' @return The updated `edaphos_causal_kg`.
#' @export
causal_kg_add_edge <- function(kg, cause, effect,
                               source     = NA_character_,
                               evidence   = NA_character_,
                               confidence = 1.0,
                               timestamp  = NULL) {
  .causal_kg_require_igraph()
  stopifnot(inherits(kg, "edaphos_causal_kg"),
            is.character(cause), length(cause) == 1L, !is.na(cause),
            is.character(effect), length(effect) == 1L, !is.na(effect),
            is.numeric(confidence), confidence >= 0, confidence <= 1)

  cause_n  <- .normalise_node(cause)
  effect_n <- .normalise_node(effect)
  if (identical(cause_n, effect_n)) {
    stop("Self-loops are not allowed (cause == effect).", call. = FALSE)
  }
  if (is.null(timestamp)) timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ",
                                              tz = "UTC")

  g <- kg$graph
  existing <- igraph::V(g)$name %||% character(0)
  to_add   <- setdiff(c(cause_n, effect_n), existing)
  if (length(to_add) > 0L) g <- igraph::add_vertices(g, length(to_add),
                                                      name = to_add)

  # Detect and merge duplicate edges (same cause -> effect): keep the
  # maximum confidence, concatenate evidence quotes.
  eid <- igraph::get_edge_ids(g, c(cause_n, effect_n), error = FALSE)
  if (length(eid) == 1L && eid > 0L) {
    old_conf <- igraph::edge_attr(g, "confidence", eid)
    old_ev   <- igraph::edge_attr(g, "evidence",   eid)
    old_src  <- igraph::edge_attr(g, "source",     eid)
    g <- igraph::set_edge_attr(g, "confidence", eid,
                                max(old_conf, confidence, na.rm = TRUE))
    g <- igraph::set_edge_attr(g, "evidence", eid,
                                paste(stats::na.omit(unique(c(old_ev, evidence))),
                                      collapse = " | "))
    g <- igraph::set_edge_attr(g, "source", eid,
                                paste(stats::na.omit(unique(c(old_src, source))),
                                      collapse = " | "))
    g <- igraph::set_edge_attr(g, "timestamp", eid, timestamp)
  } else {
    g <- igraph::add_edges(
      g,
      c(cause_n, effect_n),
      attr = list(
        source     = source,
        evidence   = evidence,
        confidence = confidence,
        timestamp  = timestamp
      )
    )
  }

  if (!igraph::is_dag(g)) {
    warning("Adding edge ", cause_n, " -> ", effect_n,
            " introduced a cycle; causal identification via backdoor ",
            "adjustment requires acyclicity.", call. = FALSE)
  }

  kg$graph <- g
  kg
}

#' Tidy edge list of a pedogenetic Knowledge Graph
#'
#' Returns a `data.frame` with one row per edge and columns
#' `cause`, `effect`, `source`, `evidence`, `confidence`, `timestamp`.
#'
#' @param kg An `edaphos_causal_kg`.
#' @return A data frame; empty (zero rows) for an empty graph.
#' @export
causal_kg_edges <- function(kg) {
  .causal_kg_require_igraph()
  stopifnot(inherits(kg, "edaphos_causal_kg"))
  g <- kg$graph
  if (igraph::ecount(g) == 0L) {
    return(data.frame(
      cause      = character(0), effect = character(0),
      source     = character(0), evidence = character(0),
      confidence = numeric(0),   timestamp = character(0),
      stringsAsFactors = FALSE
    ))
  }
  el <- igraph::as_edgelist(g)
  data.frame(
    cause      = el[, 1L],
    effect     = el[, 2L],
    source     = igraph::edge_attr(g, "source")     %||% NA_character_,
    evidence   = igraph::edge_attr(g, "evidence")   %||% NA_character_,
    confidence = igraph::edge_attr(g, "confidence") %||% NA_real_,
    timestamp  = igraph::edge_attr(g, "timestamp")  %||% NA_character_,
    stringsAsFactors = FALSE
  )
}

#' Export a Knowledge Graph to a `dagitty` DAG
#'
#' Projects the Knowledge Graph onto a `dagitty` DAG by keeping only
#' the edges whose confidence is at least `min_confidence`. The
#' resulting DAG is ready to be consumed by
#' [causal_adjustment_set()] and [causal_estimate_effect()].
#'
#' @param kg An `edaphos_causal_kg`.
#' @param min_confidence Numeric in `[0, 1]`. Edges with
#'   `confidence < min_confidence` are dropped.
#' @return A `dagitty` object.
#' @export
causal_kg_to_dagitty <- function(kg, min_confidence = 0.7) {
  .causal_kg_require_igraph()
  if (!requireNamespace("dagitty", quietly = TRUE)) {
    stop("Install the `dagitty` package to export to a DAG.",
         call. = FALSE)
  }
  stopifnot(inherits(kg, "edaphos_causal_kg"),
            is.numeric(min_confidence),
            min_confidence >= 0, min_confidence <= 1)
  edges <- causal_kg_edges(kg)
  edges <- edges[!is.na(edges$confidence) &
                 edges$confidence >= min_confidence, , drop = FALSE]
  if (nrow(edges) == 0L) {
    return(dagitty::dagitty("dag { }"))
  }
  lines <- sprintf("  %s -> %s", edges$cause, edges$effect)
  dag_txt <- paste0("dag {\n", paste(lines, collapse = "\n"), "\n}")
  dagitty::dagitty(dag_txt)
}

#' @export
print.edaphos_causal_kg <- function(x, ...) {
  .causal_kg_require_igraph()
  g <- x$graph
  cat("<edaphos_causal_kg>\n")
  cat("  nodes : ", igraph::vcount(g), "\n", sep = "")
  cat("  edges : ", igraph::ecount(g), "\n", sep = "")
  if (igraph::ecount(g) > 0L) {
    conf <- igraph::edge_attr(g, "confidence")
    if (!is.null(conf)) {
      cat(sprintf("  confidence: min = %.2f, median = %.2f, max = %.2f\n",
                  min(conf, na.rm = TRUE),
                  stats::median(conf, na.rm = TRUE),
                  max(conf, na.rm = TRUE)))
    }
    cat("  DAG        : ",
        if (igraph::is_dag(g)) "yes" else "cyclic (warn)", "\n",
        sep = "")
  }
  invisible(x)
}
