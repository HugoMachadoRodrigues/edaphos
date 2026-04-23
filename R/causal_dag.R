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

#' Real-data Cerrado pedogenetic DAG
#'
#' Structural causal model over the exact covariate column names that
#' appear in the v1.3.1 case-study bundle (WoSIS 0-10 cm topsoil SOC +
#' SoilGrids + WorldClim + SRTM + WorldCover). Unlike
#' [causal_cerrado_dag()], which uses short schematic labels
#' (`elev`, `slope`, `twi`, `map_mm`, `ndvi`, `soc`), this DAG is
#' wired against `bio1`, `bio12`, `soilgrids_clay`,
#' `wc_landcover_trees` etc. so that `causal_estimate_effect()` can
#' consume the real profiles data frame without renaming.
#'
#' The edges encode six classes of Cerrado pedogenetic relations:
#'
#' \describe{
#'   \item{Relief -> climate}{Elevation modulates temperature
#'     (adiabatic lapse) and precipitation (orographic forcing) via
#'     `elev -> bio1`, `elev -> bio12`, `elev -> slope`.}
#'   \item{Climate -> vegetation / land cover}{Bio1 (mean annual
#'     temperature) and bio12 (mean annual precipitation) drive the
#'     fraction of land covered by trees, grassland and cropland.}
#'   \item{Relief -> texture}{Steep slopes export fine fractions
#'     (`slope -> soilgrids_clay`) and accumulate coarse fractions
#'     downslope (`slope -> soilgrids_sand`).}
#'   \item{Texture -> bulk density}{Fine-textured soils compact
#'     differently (`soilgrids_clay -> soilgrids_bdod`).}
#'   \item{Climate + texture -> SOC (direct)}{Both sides drive
#'     decomposition vs mineral protection.}
#'   \item{Land cover -> SOC}{Native savanna vs. pasture vs. cropland
#'     produce 3-4x SOC differences in Cerrado topsoil; the
#'     land-cover fractions are the dominant single factor.}
#' }
#'
#' @return A `dagitty` DAG whose nodes match the column names of the
#'   `profiles` data frame in
#'   `inst/extdata/case_cerrado_results.rds`.
#' @seealso [causal_cerrado_dag()] for the short-label schematic
#'   version; [causal_adjustment_set()] and
#'   [causal_estimate_effect()] for identification + estimation.
#' @export
causal_cerrado_real_dag <- function() {
  .causal_require_dagitty()
  # Node names match the column names in the v1.3.1 case-study
  # bundle (profiles data frame). Note wc_bio_01 = mean annual
  # temperature; wc_bio_12 = mean annual precipitation (the Hijmans
  # bioclim numbering).
  dagitty::dagitty('dag {
    elev  -> wc_bio_01
    elev  -> wc_bio_12
    elev  -> slope
    wc_bio_01 -> wc_landcover_trees
    wc_bio_12 -> wc_landcover_trees
    wc_bio_01 -> wc_landcover_grassland
    wc_bio_12 -> wc_landcover_grassland
    wc_bio_01 -> wc_landcover_cropland
    wc_bio_12 -> wc_landcover_cropland
    slope -> soilgrids_clay
    slope -> soilgrids_sand
    soilgrids_clay -> soilgrids_bdod
    soilgrids_sand -> soilgrids_bdod
    wc_bio_01 -> soc_topsoil_gkg
    wc_bio_12 -> soc_topsoil_gkg
    soilgrids_clay -> soc_topsoil_gkg
    soilgrids_sand -> soc_topsoil_gkg
    soilgrids_bdod -> soc_topsoil_gkg
    slope -> soc_topsoil_gkg
    wc_landcover_trees     -> soc_topsoil_gkg
    wc_landcover_grassland -> soc_topsoil_gkg
    wc_landcover_cropland  -> soc_topsoil_gkg
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
#' Identifies a valid backdoor-adjustment set from the supplied DAG
#' (unless one is provided manually) and then fits an **adjusted
#' outcome model** conditional on that set. Two estimators are
#' available:
#'
#' * `estimator = "lm"` — closed-form linear regression
#'   \eqn{Y = \beta_0 + \beta_{\text{exposure}}\,X +
#'             \sum_{z\in Z}\gamma_z z + \varepsilon}.
#'   The regression coefficient on `exposure` is the direct causal
#'   effect. Confidence intervals follow from OLS asymptotics.
#'
#' * `estimator = "bart"` — non-linear Bayesian Additive Regression
#'   Trees (Chipman, George & McCulloch 2010), via the `dbarts`
#'   Suggests dependency. The effect of `exposure` is computed as
#'   the **average partial derivative**
#'   \eqn{\bar{\partial} = \frac{1}{n}\sum_i
#'        \bigl[\widehat{E}[Y\mid X=x_i+\delta, Z=z_i]
#'             - \widehat{E}[Y\mid X=x_i, Z=z_i]\bigr] / \delta}
#'   averaged over the training data. A 95 % credible interval is
#'   recovered from the BART posterior draws.
#'
#' @param data Data frame with columns covering at least `exposure`,
#'   `outcome`, and the chosen adjustment set.
#' @param dag A `dagitty` DAG.
#' @param exposure,outcome Character column names.
#' @param adjustment Optional character vector overriding the automatic
#'   adjustment set.
#' @param effect,type Forwarded to [causal_adjustment_set()].
#' @param estimator One of `"lm"` (default) or `"bart"` (requires
#'   `dbarts`).
#' @param delta Numeric finite-difference step used by the BART
#'   estimator. Defaults to the interquartile range of `exposure`
#'   divided by two.
#' @param bart_kwargs Optional named list of extra arguments forwarded
#'   to `dbarts::bart()` (e.g. `ndpost`, `nskip`, `seed`).
#'
#' @return A `edaphos_causal_effect` object with:
#' \describe{
#'   \item{model}{The fitted estimator (either an `lm` or a
#'     `dbarts::bart` object).}
#'   \item{estimator}{Character; `"lm"` or `"bart"`.}
#'   \item{adjustment}{The adjustment set used.}
#'   \item{effect}{Numeric direct effect.}
#'   \item{effect_ci}{95 % CI (asymptotic for `"lm"`, posterior
#'     quantile for `"bart"`).}
#'   \item{effect_naive}{Coefficient from the unadjusted
#'     `lm(outcome ~ exposure)` for contrast.}
#' }
#' @references
#' Chipman, H. A., George, E. I., & McCulloch, R. E. (2010). BART:
#' Bayesian Additive Regression Trees. *Annals of Applied Statistics*
#' **4**, 266-298.
#'
#' @export
causal_estimate_effect <- function(data, dag, exposure, outcome,
                                    adjustment = NULL,
                                    effect    = c("direct", "total"),
                                    type      = c("minimal", "canonical",
                                                  "all"),
                                    estimator = c("lm", "bart"),
                                    delta     = NULL,
                                    bart_kwargs = list()) {
  .causal_require_dagitty()
  .assert_covariates(data, c(exposure, outcome))
  effect    <- match.arg(effect)
  type      <- match.arg(type)
  estimator <- match.arg(estimator)

  if (is.null(adjustment)) {
    adjustment <- causal_adjustment_set(dag, exposure, outcome,
                                         type = type, effect = effect)
    if (is.null(adjustment)) {
      stop("Effect of `", exposure, "` on `", outcome,
           "` is not identifiable from this DAG (no adjustment set).",
           call. = FALSE)
    }
  }

  # Naive (unadjusted) baseline for both estimators.
  naive_form <- stats::reformulate(exposure, response = outcome)
  naive_fit  <- stats::lm(naive_form, data = data)
  naive_coef <- stats::coef(naive_fit)[exposure]

  terms <- unique(c(exposure, adjustment))
  .assert_covariates(data, terms)

  if (estimator == "lm") {
    adj_form <- stats::reformulate(terms, response = outcome)
    adj_fit  <- stats::lm(adj_form, data = data)
    adj_coef <- stats::coef(adj_fit)[exposure]
    adj_ci   <- stats::confint(adj_fit)[exposure, ]
    return(structure(
      list(
        model        = adj_fit,
        estimator    = "lm",
        adjustment   = adjustment,
        effect       = unname(adj_coef),
        effect_ci    = unname(adj_ci),
        effect_naive = unname(naive_coef),
        exposure     = exposure,
        outcome      = outcome
      ),
      class = "edaphos_causal_effect"
    ))
  }

  if (!requireNamespace("dbarts", quietly = TRUE)) {
    stop("Install the `dbarts` package to use estimator = \"bart\".",
         call. = FALSE)
  }
  if (is.null(delta)) {
    iqr <- stats::IQR(data[[exposure]], na.rm = TRUE)
    if (!is.finite(iqr) || iqr <= 0) iqr <- stats::sd(data[[exposure]],
                                                      na.rm = TRUE)
    delta <- iqr / 2
  }
  X   <- data[, terms, drop = FALSE]
  y   <- data[[outcome]]
  keep <- stats::complete.cases(X, y)
  X    <- X[keep, , drop = FALSE]
  y    <- y[keep]

  # dbarts::bart() predicts via a test matrix supplied at fit time,
  # so we stack the factual and counterfactual rows up front.
  X_hi <- X; X_hi[[exposure]] <- X_hi[[exposure]] + delta
  X_test <- rbind(X, X_hi)
  bart_defaults <- list(
    x.train = as.matrix(X), y.train = y,
    x.test  = as.matrix(X_test),
    keeptrees = TRUE, verbose = FALSE
  )
  bart_args <- utils::modifyList(bart_defaults, bart_kwargs)
  bart_fit  <- do.call(dbarts::bart, bart_args)

  # Posterior samples at test rows: matrix (n.samples x n_test).
  post_test <- bart_fit$yhat.test
  n_obs     <- nrow(X)
  pred_lo   <- post_test[, seq_len(n_obs),                        drop = FALSE]
  pred_hi   <- post_test[, (n_obs + 1L):(2L * n_obs),             drop = FALSE]
  per_sample <- rowMeans((pred_hi - pred_lo) / delta)
  eff_point <- mean(per_sample)
  eff_ci    <- stats::quantile(per_sample, c(0.025, 0.975),
                                names = FALSE, na.rm = TRUE)

  structure(
    list(
      model        = bart_fit,
      estimator    = "bart",
      adjustment   = adjustment,
      effect       = eff_point,
      effect_ci    = eff_ci,
      effect_naive = unname(naive_coef),
      exposure     = exposure,
      outcome      = outcome,
      delta        = delta,
      posterior    = per_sample
    ),
    class = "edaphos_causal_effect"
  )
}

#' @export
print.edaphos_causal_effect <- function(x, ...) {
  est <- x$estimator %||% "lm"
  cat("<edaphos_causal_effect>\n")
  cat(sprintf("  %s -> %s   (estimator: %s)\n",
              x$exposure, x$outcome, est))
  cat("  adjustment set : {",
      if (length(x$adjustment) == 0) "(empty)" else
        paste(x$adjustment, collapse = ", "),
      "}\n", sep = "")
  ci_label <- if (est == "bart") "95% credible" else "95% CI"
  cat(sprintf("  direct effect  : %.4g   (%s: %.4g, %.4g)\n",
              x$effect, ci_label, x$effect_ci[1], x$effect_ci[2]))
  cat(sprintf("  naive effect   : %.4g   (un-adjusted, likely confounded)\n",
              x$effect_naive))
  if (est == "bart") {
    cat(sprintf("  delta (finite diff) : %.4g\n", x$delta))
  }
  invisible(x)
}
