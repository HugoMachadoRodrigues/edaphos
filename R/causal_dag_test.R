# ---------------------------------------------------------------------------
# Falsifying a pedogenetic DAG against the data it is applied to.
#
# A directed acyclic graph is not only an assumption to be declared. It implies
# a specific set of conditional independencies among the observed variables,
# and those implications are testable. Zhang & Wadoux (2026) list this
# compatibility -- faithfulness -- as the third of their three conditions for
# causal inference from observational soil data, alongside an explicit model
# and causal sufficiency.
#
# This test previously existed only as a chunk inside the manuscript, which
# meant users of the package could not run it on their own graph. It is a
# first-class function here.
#
# The spatial correction matters. Soil profiles are spatially autocorrelated,
# so treating n profiles as n independent observations overstates the effective
# sample size and rejects independencies that a spatially aware test would not.
# On the Cerrado graph shipped with this package the pooled test rejects 33 of
# 37 implied independencies; after residualising every variable on a thin-plate
# spline of position, 28. The graph fails either way -- but a paper that
# reports only the pooled number is reporting a count that an obvious objection
# moves.
# ---------------------------------------------------------------------------

#' Test a DAG against the conditional independencies it implies
#'
#' Restricts a graph to the nodes for which `data` has columns, enumerates the
#' conditional independencies the restricted graph implies, and tests each one.
#' Reports how many the data reject, which ones, and — optionally — the same
#' test after large-scale spatial structure has been removed.
#'
#' @param dag A `dagitty` graph, e.g. from [causal_cerrado_real_dag()].
#' @param data A data frame whose columns are named after the graph's nodes.
#'   Nodes without a column are dropped from the tested sub-graph and reported
#'   in `nodes_without_data`.
#' @param alpha Significance level for calling an implied independence
#'   rejected. Applied twice: per test (unadjusted counts) and as the
#'   family-wise level of a Holm adjustment over all implied independencies,
#'   which is what the printed verdict on the graph is based on.
#' @param coords Optional length-2 character vector naming the coordinate
#'   columns in `data`. When supplied (and `mgcv` is installed), a second test
#'   is run on variables residualised on a thin-plate spline of position, which
#'   removes the large-scale spatial structure that inflates the effective
#'   sample size of a pooled test.
#' @param k Basis dimension of that spline. The residual degrees of freedom are
#'   reduced by `k` before testing, so the spatial test is not credited with
#'   observations the smoother consumed.
#'
#' @return An `edaphos_dag_test` object: a list with `pooled` (the
#'   `dagitty::localTests` table), `spatial` (the same after residualising, or
#'   `NULL`), `n_tests`, `n_rejected` and `n_rejected_spatial` (unadjusted
#'   p-value below `alpha`), `n_rejected_holm` and `n_rejected_spatial_holm`
#'   (Holm-adjusted p-value below `alpha`, via [stats::p.adjust()]),
#'   `max_abs_r` (largest absolute partial correlation over all tests,
#'   rejected or not), `nodes_tested`, `nodes_without_data`, and `n`.
#'
#'   With `n_tests` implied independencies that all hold, about
#'   `alpha * n_tests` unadjusted rejections are expected by chance alone, so
#'   the unadjusted count is not by itself evidence against the graph. The
#'   print method reports it against that expectation and rests its verdict on
#'   the Holm count.
#'
#' @references
#' Zhang Y, Wadoux AMJ-C (2026). Can digital soil mapping be causal?
#' *Geoderma*.
#'
#' @export
#' @examples
#' if (requireNamespace("dagitty", quietly = TRUE)) {
#'   # Simulated profiles, already using the graph's own column names.
#'   d <- edaphos_example_profiles()
#'
#'   tst <- causal_dag_test(causal_cerrado_real_dag(), d)
#'   tst
#'
#'   # The spatial variant fits one thin-plate spline per variable, so it is
#'   # seconds rather than milliseconds.
#'   \donttest{
#'   tsp <- causal_dag_test(causal_cerrado_real_dag(), d,
#'                          coords = c("lon", "lat"))
#'   # The graph fails on both tests -- but the counts differ, which is why
#'   # reporting only the pooled one would overstate the result.
#'   c(pooled = tsp$n_rejected, spatial = tsp$n_rejected_spatial,
#'     of = tsp$n_tests)
#'   }
#' }
causal_dag_test <- function(dag, data, alpha = 0.05, coords = NULL, k = 100L) {
  if (!requireNamespace("dagitty", quietly = TRUE)) {
    stop("`dagitty` is required for causal_dag_test().", call. = FALSE)
  }
  stopifnot(is.data.frame(data), is.numeric(alpha), alpha > 0, alpha < 1)

  allnodes <- names(dagitty::coordinates(dag)$x)
  have <- intersect(allnodes, names(data))
  if (length(have) < 3L) {
    stop("only ", length(have), " of the graph's ", length(allnodes),
         " nodes have a column in `data`; at least 3 are needed to imply a ",
         "testable independence.", call. = FALSE)
  }
  E <- dagitty::edges(dag)
  keep <- vapply(seq_len(nrow(E)), function(i)
    as.character(E$v[i]) %in% have && as.character(E$w[i]) %in% have,
    logical(1))
  sub <- dagitty::dagitty(paste0(
    "dag{", paste(sprintf("%s -> %s", E$v[keep], E$w[keep]), collapse = " "),
    "}"))

  need <- if (is.null(coords)) have else c(have, coords)
  ok <- stats::complete.cases(data[, need, drop = FALSE])
  X  <- data[ok, have, drop = FALSE]

  pooled <- dagitty::localTests(sub, X, type = "cis")

  spatial <- NULL
  if (!is.null(coords)) {
    if (!requireNamespace("mgcv", quietly = TRUE)) {
      warning("`coords` was supplied but `mgcv` is not installed; ",
              "skipping the spatial test.", call. = FALSE)
    } else {
      LL <- data[ok, coords, drop = FALSE]
      names(LL) <- c(".lon", ".lat")
      # Residualise each variable on position. What survives is the variation
      # that is NOT explained by where the profile is, which is the variation
      # an independence claim about soil processes is really about.
      R <- vapply(have, function(v) {
        df <- cbind(LL, .y = X[[v]])
        m <- mgcv::bam(.y ~ s(.lon, .lat, bs = "tp", k = as.integer(k)),
                       data = df, method = "fREML")
        as.numeric(stats::residuals(m))
      }, numeric(nrow(X)))
      colnames(R) <- have
      spatial <- dagitty::localTests(
        sub, sample.cov = stats::cov(R),
        # charge the smoother its degrees of freedom rather than pretending
        # the residuals carry the full n
        sample.nobs = max(nrow(X) - as.integer(k), 10L), type = "cis")
    }
  }

  structure(list(
    pooled             = pooled,
    spatial            = spatial,
    n                  = nrow(X),
    n_tests            = nrow(pooled),
    n_rejected         = sum(pooled$p.value < alpha),
    n_rejected_spatial = if (is.null(spatial)) NA_integer_
                         else sum(spatial$p.value < alpha),
    n_rejected_holm    = .dag_n_holm(pooled$p.value, alpha),
    n_rejected_spatial_holm = if (is.null(spatial)) NA_integer_
                              else .dag_n_holm(spatial$p.value, alpha),
    max_abs_r          = max(abs(pooled$estimate)),
    alpha              = alpha,
    nodes_tested       = have,
    nodes_without_data = setdiff(allnodes, have)
  ), class = "edaphos_dag_test")
}

# Number of implied independencies rejected at family-wise level `alpha`
# after a Holm adjustment over all of them.
.dag_n_holm <- function(p, alpha) {
  as.integer(sum(stats::p.adjust(p, method = "holm") < alpha, na.rm = TRUE))
}

#' @export
print.edaphos_dag_test <- function(x, ...) {
  cat("<edaphos_dag_test>\n")
  cat(sprintf("  %d profiles, %d of the graph's %d nodes have data\n",
              x$n, length(x$nodes_tested),
              length(x$nodes_tested) + length(x$nodes_without_data)))
  if (length(x$nodes_without_data)) {
    cat("  no column for: ", paste(x$nodes_without_data, collapse = ", "),
        "\n", sep = "")
  }
  # Recomputed from the p-values, so objects built before the Holm fields
  # existed print the same verdict.
  holm    <- .dag_n_holm(x$pooled$p.value, x$alpha)
  holm_sp <- if (is.null(x$spatial)) NA_integer_
             else .dag_n_holm(x$spatial$p.value, x$alpha)
  pct <- 100 * x$alpha
  row <- function(label, value)
    cat(sprintf("  %-34s : %s\n", label, value))
  row("implied conditional independencies", x$n_tests)
  row(sprintf("rejected, pooled, p < %g", x$alpha),
      sprintf("%d (%.1f expected if all hold)", x$n_rejected,
              x$alpha * x$n_tests))
  row(sprintf("rejected, pooled, Holm FWER %g%%", pct), holm)
  if (!is.na(x$n_rejected_spatial)) {
    row(sprintf("rejected, residualised, p < %g", x$alpha),
        x$n_rejected_spatial)
    row(sprintf("rejected, residualised, Holm %g%%", pct), holm_sp)
  }
  row("largest |partial r|, all tests", sprintf("%.3f", x$max_abs_r))
  # The verdict rests on the multiplicity-adjusted count. One unadjusted
  # rejection among dozens of tests is what a TRUE graph produces at this
  # alpha, so "any p < alpha" called nearly every graph incompatible.
  if (holm > 0L) {
    cat(sprintf("\n  The pooled test rejects %d implied independenc%s after a Holm\n",
                holm, if (holm == 1L) "y" else "ies"),
        sprintf("  adjustment (family-wise %g%%): the graph is not compatible with\n", pct),
        "  the covariance structure of these data. Any adjustment set derived\n",
        "  from it is minimal and sufficient only relative to a graph the data\n",
        "  reject, so effects estimated with it should be reported as adjusted\n",
        "  associations with sensitivity bounds, not as identified causal effects.\n",
        sep = "")
  } else if (x$n_rejected > 0L) {
    cat(sprintf("\n  No implied independence is rejected after a Holm adjustment\n  (family-wise %g%%). The unadjusted rejections are within what chance\n  produces; this does not show the graph is correct.\n",
                pct))
  }
  invisible(x)
}
