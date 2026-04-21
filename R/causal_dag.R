# Pillar 1 — Causal AI (first sketch).
#
# Structural Causal Models (SCMs) encoded as DAGs via `dagitty`, plus a
# backdoor-adjustment estimator that uses the DAG to pick a valid
# confounder set before fitting a linear causal effect.
#
# This is the *minimum viable* integration of causal inference into
# pedometric workflows: it demonstrates that DAG-guided adjustment
# changes effect estimates in a direction interpretable by a
# pedologist. The roadmap for 0.1.0+ is to plug in `bnlearn` for
# structure learning from horizon data and to use knowledge graphs +
# LLMs to ingest the pedology literature as DAG priors.

.causal_require_dagitty <- function() {
  if (!requireNamespace("dagitty", quietly = TRUE)) {
    stop("Install the `dagitty` package to use causal_*().",
         call. = FALSE)
  }
  invisible(TRUE)
}

#' Canonical CLORPT pedogenetic DAG
#'
#' Encodes Jenny (1941)'s Climate / Organisms / Relief / Parent material
#' / Time factors as a directed acyclic graph on common soil variables.
#' Useful as a textbook baseline DAG in causal analyses and as a
#' template to extend for a specific region.
#'
#' @return A `dagitty` graph object.
#' @export
causal_clorpt_dag <- function() {
  .causal_require_dagitty()
  dagitty::dagitty('dag {
    Climate         -> Organisms
    Climate         -> Weathering
    Climate         -> SOC
    Relief          -> TWI
    Relief          -> Erosion
    ParentMaterial  -> Weathering
    ParentMaterial  -> Clay
    Organisms       -> SOC
    Weathering      -> Clay
    Weathering      -> pH
    Clay            -> CEC
    SOC             -> CEC
    TWI             -> SOC
    Erosion         -> SOC
    Time            -> Weathering
    Time            -> SOC
  }')
}

#' DAG tailored to the bundled Cerrado dataset (`br_cerrado`)
#'
#' Concrete directed acyclic graph matching the (synthetic) generating
#' process of `br_cerrado`, suitable for demonstrating backdoor
#' adjustment without relying on the high-level abstractions in
#' [causal_clorpt_dag()].
#'
#' @return A `dagitty` graph object with nodes `elev`, `slope`, `twi`,
#'   `map_mm`, `ndvi`, `soc`.
#' @export
causal_cerrado_dag <- function() {
  .causal_require_dagitty()
  dagitty::dagitty('dag {
    elev   -> slope
    elev   -> map_mm
    slope  -> twi
    map_mm -> twi
    elev   -> twi
    twi    -> ndvi
    slope  -> ndvi
    map_mm -> ndvi
    elev   -> soc
    slope  -> soc
    twi    -> soc
    map_mm -> soc
    ndvi   -> soc
  }')
}

#' Suggest a backdoor-adjustment set from a DAG
#'
#' Wraps `dagitty::adjustmentSets()` and returns the adjustment set as a
#' plain character vector — or `NULL` if the effect is not identifiable.
#'
#' @param dag A `dagitty` DAG object.
#' @param exposure Character, name of the exposure variable.
#' @param outcome Character, name of the outcome variable.
#' @param type One of `"minimal"`, `"canonical"`, `"all"`; forwarded to
#'   `dagitty::adjustmentSets()`.
#' @param effect One of `"direct"` or `"total"`; forwarded to
#'   `dagitty::adjustmentSets()`.
#'
#' @return A character vector of variable names to condition on, or
#'   `NULL` if no valid set exists.
#' @export
causal_adjustment_set <- function(dag, exposure, outcome,
                                   type = c("minimal", "canonical", "all"),
                                   effect = c("direct", "total")) {
  .causal_require_dagitty()
  type   <- match.arg(type)
  effect <- match.arg(effect)
  sets <- dagitty::adjustmentSets(
    dag, exposure = exposure, outcome = outcome,
    type = type, effect = effect
  )
  if (length(sets) == 0L) return(NULL)
  as.character(sets[[1L]])
}

#' Estimate a causal effect using DAG-guided backdoor adjustment
#'
#' Fits a linear model
#' \code{outcome ~ exposure + adjustment_set} where the adjustment set
#' is chosen automatically by [causal_adjustment_set()] from the supplied
#' DAG (unless explicitly provided). The regression coefficient on
#' `exposure` is then a valid estimate of the direct causal effect,
#' provided the DAG is correct.
#'
#' @param data Data frame with columns covering at least `exposure`,
#'   `outcome`, and the chosen adjustment set.
#' @param dag A `dagitty` DAG.
#' @param exposure,outcome Character column names.
#' @param adjustment Optional character vector overriding the automatic
#'   adjustment set.
#' @param effect,type Forwarded to [causal_adjustment_set()].
#'
#' @return A `edaphos_causal_effect` object with:
#' \describe{
#'   \item{model}{The fitted `lm`.}
#'   \item{adjustment}{The adjustment set used.}
#'   \item{effect}{Numeric coefficient on `exposure`.}
#'   \item{effect_ci}{95% confidence interval on `exposure`.}
#'   \item{effect_naive}{Coefficient from the *unadjusted* `lm(outcome ~ exposure)` for comparison.}
#' }
#' @export
causal_estimate_effect <- function(data, dag, exposure, outcome,
                                    adjustment = NULL,
                                    effect = c("direct", "total"),
                                    type = c("minimal", "canonical", "all")) {
  .causal_require_dagitty()
  .assert_covariates(data, c(exposure, outcome))
  effect <- match.arg(effect)
  type   <- match.arg(type)

  if (is.null(adjustment)) {
    adjustment <- causal_adjustment_set(dag, exposure, outcome,
                                         type = type, effect = effect)
    if (is.null(adjustment)) {
      stop("Effect of `", exposure, "` on `", outcome,
           "` is not identifiable from this DAG (no adjustment set).",
           call. = FALSE)
    }
  }

  # Naive (unadjusted)
  naive_form <- stats::reformulate(exposure, response = outcome)
  naive_fit  <- stats::lm(naive_form, data = data)
  naive_coef <- stats::coef(naive_fit)[exposure]

  # Adjusted
  terms <- unique(c(exposure, adjustment))
  .assert_covariates(data, terms)
  adj_form   <- stats::reformulate(terms, response = outcome)
  adj_fit    <- stats::lm(adj_form, data = data)
  adj_coef   <- stats::coef(adj_fit)[exposure]
  adj_ci     <- stats::confint(adj_fit)[exposure, ]

  structure(
    list(
      model         = adj_fit,
      adjustment    = adjustment,
      effect        = unname(adj_coef),
      effect_ci     = unname(adj_ci),
      effect_naive  = unname(naive_coef),
      exposure      = exposure,
      outcome       = outcome
    ),
    class = "edaphos_causal_effect"
  )
}

#' @export
print.edaphos_causal_effect <- function(x, ...) {
  cat("<edaphos_causal_effect>\n")
  cat(sprintf("  %s -> %s\n", x$exposure, x$outcome))
  cat("  adjustment set : {",
      if (length(x$adjustment) == 0) "(empty)" else
        paste(x$adjustment, collapse = ", "),
      "}\n", sep = "")
  cat(sprintf("  direct effect  : %.4g   (95%% CI: %.4g, %.4g)\n",
              x$effect, x$effect_ci[1], x$effect_ci[2]))
  cat(sprintf("  naive effect   : %.4g   (un-adjusted, likely confounded)\n",
              x$effect_naive))
  invisible(x)
}
