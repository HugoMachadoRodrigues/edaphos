# Pillar 1 — DAG augmentation.
#
# Fuses a literature-derived Knowledge Graph (R/causal_kg.R) with a
# hand-specified pedogenetic DAG (e.g. causal_cerrado_dag()) so that
# the backdoor-adjustment estimator (R/causal_dag.R) can consume the
# union. This is the core bridge between LLM-driven extraction and
# the classical do-calculus machinery.

.augment_require_dagitty <- function() {
  if (!requireNamespace("dagitty", quietly = TRUE)) {
    stop("Install the `dagitty` package to augment a DAG.",
         call. = FALSE)
  }
  invisible(TRUE)
}

.dagitty_edges <- function(dag) {
  # Returns the edge list as a data frame with columns cause, effect.
  e <- dagitty::edges(dag)
  if (nrow(e) == 0L) {
    return(data.frame(cause = character(0), effect = character(0),
                      stringsAsFactors = FALSE))
  }
  arrow_rows <- e$e == "->"
  e <- e[arrow_rows, , drop = FALSE]
  data.frame(cause = as.character(e$v),
             effect = as.character(e$w),
             stringsAsFactors = FALSE)
}

#' Augment a base DAG with edges from a Knowledge Graph
#'
#' Takes a `dagitty` DAG expressing prior / expert structural
#' knowledge (e.g. the CLORPT or Cerrado DAGs shipped with `edaphos`)
#' and unions it with the subset of Knowledge-Graph edges whose
#' confidence is at least `min_confidence`. Duplicate edges are
#' dropped silently, and any edge whose insertion would introduce a
#' directed cycle is rejected (warned but not inserted), so the
#' returned DAG is guaranteed to be acyclic and usable for
#' [causal_adjustment_set()].
#'
#' @param base_dag A `dagitty` DAG (e.g. [causal_cerrado_dag()]).
#' @param kg An `edaphos_causal_kg` (from [causal_kg_new()] / LLM
#'   ingestion).
#' @param min_confidence Numeric in `[0, 1]`; KG edges strictly
#'   below this threshold are ignored.
#' @param allow_new_nodes Logical. When `TRUE` (default) nodes
#'   appearing only in the KG are added to the augmented DAG. When
#'   `FALSE` KG edges touching unseen nodes are dropped — useful
#'   when the analyst wants to lock the structural vocabulary.
#'
#' @return An object of class `dagitty`, augmented.
#' @export
causal_augment_dag <- function(base_dag, kg,
                                min_confidence = 0.7,
                                allow_new_nodes = TRUE) {
  .augment_require_dagitty()
  stopifnot(inherits(base_dag, "dagitty"),
            inherits(kg, "edaphos_causal_kg"),
            is.numeric(min_confidence),
            min_confidence >= 0, min_confidence <= 1)

  base_edges <- .dagitty_edges(base_dag)
  base_nodes <- tryCatch(
    as.character(names(base_dag)),
    error = function(e) unique(c(base_edges$cause, base_edges$effect))
  )
  if (is.null(base_nodes)) {
    base_nodes <- unique(c(base_edges$cause, base_edges$effect))
  }

  kg_edges <- causal_kg_edges(kg)
  kg_edges <- kg_edges[!is.na(kg_edges$confidence) &
                        kg_edges$confidence >= min_confidence, ,
                       drop = FALSE]

  if (!allow_new_nodes && length(base_nodes) > 0L) {
    keep <- kg_edges$cause %in% base_nodes & kg_edges$effect %in% base_nodes
    kg_edges <- kg_edges[keep, , drop = FALSE]
  }

  # Union of edges, deduplicated, cycle-safe.
  all_edges <- unique(rbind(
    base_edges[, c("cause", "effect"), drop = FALSE],
    kg_edges[, c("cause", "effect"), drop = FALSE]
  ))
  all_edges <- all_edges[!duplicated(all_edges[, c("cause", "effect")]), ,
                         drop = FALSE]

  # Assemble incrementally, guarding cyclicity.
  acc_nodes <- unique(c(base_nodes,
                        all_edges$cause, all_edges$effect))
  acc_edges <- list()
  rejected  <- character(0)
  for (i in seq_len(nrow(all_edges))) {
    edge_line <- sprintf("  %s -> %s", all_edges$cause[i],
                          all_edges$effect[i])
    candidate_txt <- paste0("dag {\n",
      paste(c(sprintf("  %s", acc_nodes), unlist(acc_edges), edge_line),
            collapse = "\n"),
      "\n}")
    cand_dag <- try(dagitty::dagitty(candidate_txt), silent = TRUE)
    if (!inherits(cand_dag, "try-error") &&
        dagitty::isAcyclic(cand_dag)) {
      acc_edges[[length(acc_edges) + 1L]] <- edge_line
    } else {
      rejected <- c(rejected,
                    sprintf("%s -> %s", all_edges$cause[i],
                             all_edges$effect[i]))
    }
  }

  if (length(rejected) > 0L) {
    warning("Rejected ", length(rejected),
            " edge(s) that would have introduced a directed cycle: ",
            paste(rejected, collapse = "; "), call. = FALSE)
  }

  final_txt <- paste0(
    "dag {\n",
    paste(c(sprintf("  %s", acc_nodes), unlist(acc_edges)),
          collapse = "\n"),
    "\n}"
  )
  augmented <- dagitty::dagitty(final_txt)
  attr(augmented, "n_base_edges") <- nrow(base_edges)
  attr(augmented, "n_added_edges") <- length(acc_edges) - nrow(base_edges)
  attr(augmented, "n_rejected")   <- length(rejected)
  augmented
}

#' Diff between a base DAG and an augmented DAG
#'
#' Convenience helper that shows which edges are inherited from the
#' `base_dag`, which are new from the Knowledge Graph, and (if any)
#' which were rejected as cycle-forming. Handy for vignettes and
#' auditing.
#'
#' @param base_dag,augmented_dag Two `dagitty` DAG objects — typically
#'   the second is the return value of [causal_augment_dag()].
#' @return A data frame with columns `cause`, `effect`, `origin`
#'   (`"base"` or `"kg"`).
#' @export
causal_augment_diff <- function(base_dag, augmented_dag) {
  .augment_require_dagitty()
  stopifnot(inherits(base_dag, "dagitty"),
            inherits(augmented_dag, "dagitty"))
  base <- .dagitty_edges(base_dag)
  aug  <- .dagitty_edges(augmented_dag)
  key_base <- paste(base$cause, base$effect, sep = "->")
  key_aug  <- paste(aug$cause, aug$effect, sep = "->")
  origin   <- ifelse(key_aug %in% key_base, "base", "kg")
  data.frame(cause = aug$cause, effect = aug$effect,
             origin = origin, stringsAsFactors = FALSE)
}
