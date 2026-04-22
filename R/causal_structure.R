# Pillar 1 -- Structure learning from horizon data (bnlearn bridge).
#
# The LLM-driven pipeline in R/causal_llm.R populates a Knowledge
# Graph *top-down* from scientific abstracts: the LLM reads a text
# and asserts a causal triple (cause, effect, confidence). This is
# powerful for literature-scale prior knowledge but insensitive to the
# data that the package has in hand: a new pedon dataset with columns
# like (elev, slope, map_mm, soc, clay, cec) contains statistical
# information about the actual conditional-independence structure of
# those variables that ought to be taken seriously when we build a
# DAG for backdoor adjustment.
#
# Structure learning -- in the sense of classical causal discovery
# (Spirtes, Glymour and Scheines 2000; Chickering 2002) -- is the
# bottom-up counterpart: given a data matrix, recover the DAG whose
# conditional-independence structure best matches the data under an
# assumed faithfulness.
#
# This file wires four of the best-tested structure-learning
# algorithms from `bnlearn` (Scutari 2010) through a uniform interface
# that returns an `edaphos_causal_kg`, so the learned DAG is a
# first-class citizen of the rest of Pillar 1 (rename, union with an
# LLM KG, backdoor adjustment, Turtle export).
#
# Algorithms wrapped:
#
#   * "hc"          Hill-climbing search over BIC/BGe scores.
#                   Fast, deterministic, the most common choice.
#   * "tabu"        Tabu-search variant of hc; escapes local minima.
#   * "pc-stable"   PC-stable constraint-based algorithm (Colombo &
#                   Maathuis 2014) — the modern reference PC.
#   * "mmhc"        Max-Min Hill-Climbing (Tsamardinos, Brown and
#                   Aliferis 2006) — hybrid constraint + score.
#
# Whitelisting / blacklisting edges (e.g. "climate must causally
# precede soil properties") is forwarded to bnlearn directly. Bootstrap
# confidence for learned edges is available via `bnlearn::boot.strength`
# and exposed as per-edge `confidence`.

.causal_structure_require_bnlearn <- function() {
  if (!requireNamespace("bnlearn", quietly = TRUE)) {
    stop("Install the `bnlearn` package to use ",
         "causal_structure_learn():\n",
         "   install.packages('bnlearn')",
         call. = FALSE)
  }
  invisible(TRUE)
}

#' Structure learning from horizon data -> Knowledge Graph
#'
#' Learns a Directed Acyclic Graph (DAG) over a set of soil covariate
#' / response variables directly from a horizon-level data frame,
#' using one of four canonical structure-learning algorithms from the
#' `bnlearn` package (Scutari 2010). The returned object is an
#' `edaphos_causal_kg` so the learned DAG can be (i) unioned with the
#' LLM-extracted Knowledge Graph via [causal_augment_dag()], (ii)
#' exported to RDF via [causal_kg_to_turtle()], and (iii) consumed by
#' the backdoor-adjustment estimator via [causal_kg_to_dagitty()].
#'
#' @section Algorithms:
#' \describe{
#'   \item{`"hc"` (default)}{Hill-climbing greedy search over DAG
#'     space maximising a Bayesian Information Criterion (BIC) score
#'     (Gaussian BIC for continuous variables).
#'     Deterministic, fast, and widely used.}
#'   \item{`"tabu"`}{Tabu-search variant that escapes local optima by
#'     keeping a short memory of recently visited DAGs.}
#'   \item{`"pc-stable"`}{PC-stable constraint-based algorithm
#'     (Colombo and Maathuis 2014). Starts from a complete skeleton
#'     and removes edges based on partial correlation tests; returns
#'     a CPDAG which we extend to a DAG via a topological order
#'     consistent with the whitelist.}
#'   \item{`"mmhc"`}{Max-Min Hill-Climbing (Tsamardinos, Brown and
#'     Aliferis 2006). Hybrid: learns a skeleton by constraint tests,
#'     then orients edges by hill-climbing over a BIC score.}
#' }
#'
#' @section Bootstrap edge confidence:
#' When `bootstrap = TRUE`, a non-parametric bootstrap over rows of
#' `data` is performed. Each bootstrap replicate runs the same
#' `method`, whitelist and blacklist; the fraction of replicates in
#' which each edge appears is recorded as that edge's `confidence` in
#' the returned KG. This gives an honest uncertainty estimate on the
#' learned structure, useful when the sample size is modest relative
#' to the number of variables (a common situation for soil surveys).
#'
#' @param data A data frame with one row per observation (typically a
#'   pedon or horizon).
#' @param variables Optional character vector of columns to include
#'   in the analysis. When `NULL`, uses every numeric column of
#'   `data`.
#' @param method One of `"hc"` (default), `"tabu"`, `"pc-stable"`,
#'   `"mmhc"`.
#' @param whitelist Optional data frame with columns `from` and `to`
#'   listing edges that *must* be present in the learned DAG. Useful
#'   for pedological priors, e.g. "parent material must precede soil
#'   chemistry".
#' @param blacklist Optional data frame with columns `from` and `to`
#'   listing edges that *must not* appear — typically the reverse of
#'   the whitelist plus any physically impossible arrows (e.g.
#'   `soc -> elevation`).
#' @param score Scoring function for score-based algorithms
#'   (`"hc"`, `"tabu"`, `"mmhc"`). Defaults to `"bic-g"` (Gaussian
#'   BIC) for continuous data; `"bge"` (Bayesian Gaussian
#'   equivalent) is the alternative. For discrete data use `"bic"`
#'   or `"bde"`.
#' @param alpha Significance level for conditional-independence
#'   tests in `"pc-stable"` / `"mmhc"`. Default `0.05`.
#' @param bootstrap Logical — run a bootstrap to estimate edge
#'   confidence. Default `FALSE`.
#' @param R_boot Integer — number of bootstrap replicates. Default
#'   `200`.
#' @param seed Optional integer — used by the bootstrap resampler.
#' @param verbose Logical — forwarded to `bnlearn`.
#' @return An `edaphos_causal_kg` whose `source` field on every edge
#'   reads `"structure_learn(method=...)"` and whose `confidence` is
#'   either `1.0` (point learned DAG, no bootstrap) or the bootstrap
#'   edge-frequency.
#' @references
#' Spirtes, P., Glymour, C. and Scheines, R. (2000). *Causation,
#' Prediction, and Search* (2nd ed.). MIT Press.
#'
#' Scutari, M. (2010). Learning Bayesian networks with the `bnlearn`
#' R package. *Journal of Statistical Software* **35**, 1–22.
#'
#' Colombo, D. and Maathuis, M. H. (2014). Order-independent
#' constraint-based causal structure learning. *Journal of Machine
#' Learning Research* **15**, 3741–3782.
#'
#' Tsamardinos, I., Brown, L. E. and Aliferis, C. F. (2006). The
#' max-min hill-climbing Bayesian network structure learning
#' algorithm. *Machine Learning* **65**, 31–78.
#' @seealso [causal_kg_new()], [causal_augment_dag()],
#'   [causal_kg_to_dagitty()], [causal_kg_to_turtle()].
#' @examples
#' \dontrun{
#'   data(br_cerrado)
#'   kg_learned <- causal_structure_learn(
#'     br_cerrado,
#'     variables = c("elev", "slope", "twi", "map_mm", "ndvi", "soc"),
#'     method    = "hc",
#'     whitelist = data.frame(from = c("elev", "map_mm"),
#'                             to   = c("twi",  "soc")),
#'     bootstrap = TRUE, R_boot = 200L, seed = 1L
#'   )
#'   print(kg_learned)
#' }
#' @export
causal_structure_learn <- function(data,
                                     variables = NULL,
                                     method = c("hc", "tabu", "pc-stable",
                                                "mmhc"),
                                     whitelist = NULL,
                                     blacklist = NULL,
                                     score = "bic-g",
                                     alpha = 0.05,
                                     bootstrap = FALSE,
                                     R_boot = 200L,
                                     seed = NULL,
                                     verbose = FALSE) {
  .causal_structure_require_bnlearn()
  .causal_kg_require_igraph()
  stopifnot(is.data.frame(data), nrow(data) >= 5L)
  method <- match.arg(method)

  # Variable selection ----------------------------------------------------
  if (is.null(variables)) {
    variables <- names(data)[vapply(data, is.numeric, logical(1L))]
  }
  if (length(variables) < 2L) {
    stop("At least two variables required for structure learning.",
         call. = FALSE)
  }
  missing <- setdiff(variables, names(data))
  if (length(missing) > 0L) {
    stop("Requested variables not present in `data`: ",
         paste(missing, collapse = ", "), ".", call. = FALSE)
  }
  df <- data[, variables, drop = FALSE]
  df <- df[stats::complete.cases(df), , drop = FALSE]
  if (nrow(df) < 5L) {
    stop("Too few complete cases (", nrow(df),
         ") after dropping NA rows.", call. = FALSE)
  }

  # Normalise (white|black)list to bnlearn's expected from/to data frame.
  wl <- NULL
  if (!is.null(whitelist)) {
    stopifnot(is.data.frame(whitelist),
              all(c("from", "to") %in% names(whitelist)))
    wl <- whitelist[, c("from", "to")]
  }
  bl <- NULL
  if (!is.null(blacklist)) {
    stopifnot(is.data.frame(blacklist),
              all(c("from", "to") %in% names(blacklist)))
    bl <- blacklist[, c("from", "to")]
  }

  # --- single-fit path -------------------------------------------------
  if (!isTRUE(bootstrap)) {
    bn <- .causal_structure_run(df, method, wl, bl, score, alpha, verbose)
    # Promote CPDAG to DAG if needed (pc-stable returns a partially
    # directed graph; hc/tabu/mmhc already return a DAG).
    if (bnlearn::directed(bn)) {
      arcs <- bnlearn::arcs(bn)
    } else {
      bn <- bnlearn::cextend(bn)
      arcs <- bnlearn::arcs(bn)
    }
    edges <- data.frame(
      from       = arcs[, "from"],
      to         = arcs[, "to"],
      strength   = 1,
      direction  = 1,
      stringsAsFactors = FALSE
    )
  } else {
    # --- bootstrap edge strength -----------------------------------------
    if (!is.null(seed)) set.seed(seed)
    boot <- bnlearn::boot.strength(
      data      = df,
      R         = as.integer(R_boot),
      algorithm = switch(method,
                          hc          = "hc",
                          tabu        = "tabu",
                          `pc-stable` = "pc.stable",
                          mmhc        = "mmhc"),
      algorithm.args = .causal_structure_args(method, wl, bl, score,
                                                 alpha, verbose)
    )
    # Keep arcs whose frequency exceeds 0.5 and whose directional
    # probability is also majority.
    keep <- boot$strength >= 0.5 & boot$direction >= 0.5
    edges <- boot[keep, , drop = FALSE]
    edges$strength  <- edges$strength
    edges$direction <- edges$direction
    edges <- edges[, c("from", "to", "strength", "direction")]
  }

  # Assemble the KG ------------------------------------------------------
  kg <- causal_kg_new()
  if (nrow(edges) == 0L) return(kg)
  src <- sprintf("structure_learn(method=%s%s)",
                  method,
                  if (isTRUE(bootstrap))
                    paste0(",boot=", as.integer(R_boot)) else "")
  for (i in seq_len(nrow(edges))) {
    kg <- suppressWarnings(causal_kg_add_edge(
      kg,
      cause      = as.character(edges$from[i]),
      effect     = as.character(edges$to[i]),
      source     = src,
      evidence   = sprintf("strength=%.3f direction=%.3f",
                            edges$strength[i], edges$direction[i]),
      confidence = as.numeric(edges$strength[i])
    ))
  }
  kg
}

# Internal: build the bnlearn call that runs the requested algorithm.
.causal_structure_run <- function(df, method, wl, bl, score,
                                    alpha, verbose) {
  args <- .causal_structure_args(method, wl, bl, score, alpha, verbose)
  args$x <- df
  switch(
    method,
    hc          = do.call(bnlearn::hc, args),
    tabu        = do.call(bnlearn::tabu, args),
    `pc-stable` = do.call(bnlearn::pc.stable, args),
    mmhc        = do.call(bnlearn::mmhc, args)
  )
}

# Internal: assemble algorithm-specific arguments. Separated so the
# bootstrap path can forward the same argument set.
.causal_structure_args <- function(method, wl, bl, score, alpha,
                                     verbose) {
  args <- list(debug = FALSE)
  if (!is.null(wl)) args$whitelist <- wl
  if (!is.null(bl)) args$blacklist <- bl
  if (method %in% c("hc", "tabu", "mmhc")) {
    args$score <- score
  }
  if (method %in% c("pc-stable", "mmhc")) {
    args$alpha <- alpha
  }
  if (method == "tabu") {
    args$tabu <- 10L
  }
  args
}
