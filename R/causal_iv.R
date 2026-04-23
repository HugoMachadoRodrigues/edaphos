# Pillar 1 x Pillar 4 bridge -- Instrumental variable estimation (v1.9.0).
#
# Estimates the causal effect of an exposure X on an outcome Y using
# instruments Z, optionally conditional on exogenous controls W.
# Primary use case: treat foundation-model patch embeddings (or their
# principal components) as candidate instruments to identify causal
# effects under unobserved-confounder regimes that the hand-drawn DAG
# of Pillar 1 cannot block.
#
# Exported surface
#   causal_iv_fit_2sls()      : point estimate + analytic SE, F-stat,
#                                Sargan J-statistic.
#   causal_iv_first_stage()   : first-stage diagnostics (relevance).
#   causal_iv_sargan_test()   : Sargan/Hansen J-test for overidentification.
#   causal_iv_posterior()     : bootstrap posterior as edaphos_posterior.
#   causal_iv_from_embeddings(): convenience wrapper that takes a
#                                feature matrix + PCA reduction + 2SLS.
#
# References
#   Wooldridge, J. M. (2010). Econometric Analysis of Cross Section
#     and Panel Data, 2nd ed., MIT Press.  Chapter 5 gives the
#     closed-form 2SLS estimator and its asymptotic variance.
#   Angrist, J. D. and Pischke, J.-S. (2009). Mostly Harmless
#     Econometrics, Princeton University Press. Chapter 4.
#   Stock, J. H. and Yogo, M. (2005). Testing for weak instruments
#     in linear IV regression.  Econometrics: Theory and
#     Applications, 80, 108.
#   Sargan, J. D. (1958). The estimation of economic relationships
#     using instrumental variables.  Econometrica, 26(3), 393-415.

# ---------------------------------------------------------------------------
# Core 2SLS
# ---------------------------------------------------------------------------

#' Two-stage least squares (2SLS) instrumental variable estimator
#'
#' Estimates the causal effect of an endogenous exposure `exposure` on
#' an outcome `outcome` using one or more instruments, optionally
#' conditional on exogenous controls.  Implements the classical 2SLS
#' estimator with the Wooldridge (2010) asymptotic variance -- the
#' naive `lm()` SE of the second stage is biased because it treats
#' the generated regressor as observed, a common mistake.
#'
#' Formal setup
#' ------------
#' Let
#'   - `X` be the endogenous exposure (one column),
#'   - `Z` the matrix of instruments,
#'   - `W` the matrix of exogenous controls (included in both stages).
#'
#' Define the augmented matrices `X_all = [W, X]` and
#' `Z_all = [W, Z]` and the projection `P = Z_all (Z_all' Z_all)^-1
#' Z_all'`.  The 2SLS estimator is
#'
#' \deqn{\hat{\beta} = (X_{\text{all}}^\top P X_{\text{all}})^{-1} X_{\text{all}}^\top P Y}
#'
#' with residuals computed using the ORIGINAL `X_all`, not the
#' first-stage fitted values, so that
#'
#' \deqn{\hat{\sigma}^2 = (Y - X_{\text{all}} \hat{\beta})^\top (Y - X_{\text{all}} \hat{\beta}) / (n - k)}
#' \deqn{\widehat{\mathrm{Var}}(\hat{\beta}) = \hat{\sigma}^2 (X_{\text{all}}^\top P X_{\text{all}})^{-1}}
#'
#' Identification conditions (Wooldridge 2010, section 5.1):
#'   - Relevance: \eqn{\mathrm{rank}(Z' X) = \dim(X)}; the first-stage
#'     F-statistic should exceed 10 (Stock & Yogo 2005).
#'   - Exclusion: \eqn{Z} affects \eqn{Y} only through \eqn{X}.
#'   - Unconfoundedness: \eqn{Z \perp U} where \eqn{U} is any
#'     unobserved confounder.
#'
#' @param data A data frame.
#' @param exposure Character; name of the endogenous exposure column.
#' @param outcome Character; name of the outcome column.
#' @param instruments Character vector; names of instrument columns.
#'   More instruments than exposures gives an over-identified model
#'   on which the Sargan test is applicable.
#' @param covariates Optional character vector of exogenous-control
#'   column names included in both first and second stage.
#'
#' @return An `edaphos_causal_iv` object with components `effect`,
#'   `se`, `ci`, `stage1_F`, `stage1_R2`, `sargan_p` (NULL if exactly
#'   identified), `n`, plus auxiliary fits for inspection.
#' @export
causal_iv_fit_2sls <- function(data, exposure, outcome, instruments,
                                 covariates = NULL) {
  stopifnot(is.data.frame(data),
            is.character(exposure),    length(exposure) == 1L,
            is.character(outcome),     length(outcome)  == 1L,
            is.character(instruments), length(instruments) >= 1L)

  cols_needed <- c(exposure, outcome, instruments, covariates)
  miss <- setdiff(cols_needed, names(data))
  if (length(miss) > 0L)
    stop(sprintf("Columns not found: %s",
                   paste(miss, collapse = ", ")), call. = FALSE)
  df <- data[stats::complete.cases(data[, cols_needed, drop = FALSE]), , drop = FALSE]
  n  <- nrow(df)
  if (n < length(cols_needed) + 5L)
    stop("Too few complete rows for 2SLS.", call. = FALSE)

  y <- df[[outcome]]
  X <- as.matrix(df[, exposure, drop = FALSE])
  Z <- as.matrix(df[, instruments, drop = FALSE])
  W <- if (is.null(covariates) || length(covariates) == 0L)
          matrix(numeric(0), nrow = n, ncol = 0L)
       else as.matrix(df[, covariates, drop = FALSE])

  ones <- rep(1, n)
  X_all <- cbind(intercept = ones, W, X)           # n x (1+p_w+1)
  Z_all <- cbind(intercept = ones, W, Z)           # n x (1+p_w+p_z)

  # 2SLS closed form
  ZZ_inv <- tryCatch(solve(crossprod(Z_all)),
                      error = function(e) MASS::ginv(crossprod(Z_all)))
  P_Z    <- Z_all %*% ZZ_inv %*% t(Z_all)
  XPX    <- crossprod(X_all, P_Z %*% X_all)
  XPX_inv <- tryCatch(solve(XPX),
                       error = function(e) MASS::ginv(XPX))
  XPy    <- crossprod(X_all, P_Z %*% y)
  beta   <- as.numeric(XPX_inv %*% XPy)
  names(beta) <- colnames(X_all)

  # Residuals with ORIGINAL X (Wooldridge 2010, eq 5.35)
  resid_iv <- y - X_all %*% beta
  k        <- length(beta)
  sigma2   <- as.numeric(crossprod(resid_iv)) / (n - k)
  V_beta   <- sigma2 * XPX_inv
  se_beta  <- sqrt(diag(V_beta))

  # Extract the causal effect (column of X = exposure)
  effect    <- unname(beta[exposure])
  se_effect <- unname(se_beta[exposure])
  ci        <- effect + c(-1, 1) * stats::qnorm(0.975) * se_effect

  # First-stage F-stat for relevance (regress X on Z_all, test the
  # joint significance of the INSTRUMENTS only)
  fs   <- causal_iv_first_stage(df, exposure, instruments, covariates)

  # Sargan test only when over-identified
  sargan <- NULL
  if (ncol(Z) > 1L) {
    sargan <- causal_iv_sargan_test(df, exposure, outcome,
                                      instruments, covariates)
  }

  structure(list(
    estimator   = "2SLS",
    exposure    = exposure,
    outcome     = outcome,
    instruments = instruments,
    covariates  = covariates,
    effect      = effect,
    se          = se_effect,
    ci_lo       = ci[1],
    ci_hi       = ci[2],
    stage1_F    = fs$F,
    stage1_F_pvalue = fs$F_pvalue,
    stage1_R2   = fs$R2,
    stage1_R2_partial = fs$R2_partial,
    sargan_stat = if (!is.null(sargan)) sargan$stat else NA_real_,
    sargan_df   = if (!is.null(sargan)) sargan$df   else NA_integer_,
    sargan_p    = if (!is.null(sargan)) sargan$p    else NA_real_,
    n           = n,
    coefs       = beta,
    vcov        = V_beta,
    weak_instruments = fs$F < 10
  ), class = "edaphos_causal_iv")
}

#' @export
print.edaphos_causal_iv <- function(x, ...) {
  cat("<edaphos_causal_iv>\n")
  cat(sprintf("  %s -> %s  (estimator: %s, n = %d)\n",
               x$exposure, x$outcome, x$estimator, x$n))
  if (length(x$covariates) > 0L) {
    cat(sprintf("  covariates  : %s\n",
                 paste(x$covariates, collapse = ", ")))
  }
  cat(sprintf("  instruments : %s\n",
               paste(x$instruments, collapse = ", ")))
  cat(sprintf("  effect      : %.4f  (se = %.4f, 95%% CI [%.4f, %.4f])\n",
               x$effect, x$se, x$ci_lo, x$ci_hi))
  cat(sprintf("  stage-1 F   : %.2f (p = %.3g)  partial R^2 = %.3f\n",
               x$stage1_F, x$stage1_F_pvalue, x$stage1_R2_partial))
  if (!is.na(x$sargan_p)) {
    cat(sprintf("  Sargan J    : chi2(%d) = %.2f, p = %.3f\n",
                 x$sargan_df, x$sargan_stat, x$sargan_p))
  }
  if (isTRUE(x$weak_instruments)) {
    cat("  [warning] Stock-Yogo threshold F < 10; instruments may be weak.\n")
  }
  invisible(x)
}

# ---------------------------------------------------------------------------
# First-stage diagnostics
# ---------------------------------------------------------------------------

#' First-stage regression diagnostics for an IV design
#'
#' Regresses the endogenous exposure on instruments + controls and
#' reports the F-statistic for the joint significance of the
#' INSTRUMENTS (controls partialed out), the partial R-squared, and
#' the overall R-squared.  Stock & Yogo (2005) recommend F > 10 as a
#' rule of thumb to avoid weak-instrument bias.
#'
#' @inheritParams causal_iv_fit_2sls
#' @return Named list with `F`, `F_pvalue`, `R2`, `R2_partial`.
#' @export
causal_iv_first_stage <- function(data, exposure, instruments,
                                    covariates = NULL) {
  cols_needed <- c(exposure, instruments, covariates)
  df <- data[stats::complete.cases(data[, cols_needed, drop = FALSE]), , drop = FALSE]

  # Full: X ~ W + Z,   Reduced: X ~ W
  full_rhs <- paste(c(covariates, instruments), collapse = " + ")
  full_fml <- stats::as.formula(sprintf("%s ~ %s", exposure, full_rhs))
  full_fit <- stats::lm(full_fml, data = df)

  if (is.null(covariates) || length(covariates) == 0L) {
    reduced_fml <- stats::as.formula(sprintf("%s ~ 1", exposure))
  } else {
    reduced_fml <- stats::as.formula(sprintf("%s ~ %s", exposure,
      paste(covariates, collapse = " + ")))
  }
  reduced_fit <- stats::lm(reduced_fml, data = df)

  an <- stats::anova(reduced_fit, full_fit)
  F_stat   <- an$F[2L]
  F_pvalue <- an$`Pr(>F)`[2L]

  R2         <- summary(full_fit)$r.squared
  # Partial R^2 of instruments over controls
  RSS_full   <- sum(stats::residuals(full_fit)^2)
  RSS_reduc  <- sum(stats::residuals(reduced_fit)^2)
  R2_partial <- (RSS_reduc - RSS_full) / RSS_reduc

  list(F = F_stat, F_pvalue = F_pvalue,
        R2 = R2, R2_partial = R2_partial,
        full_fit = full_fit)
}

# ---------------------------------------------------------------------------
# Sargan / Hansen test
# ---------------------------------------------------------------------------

#' Sargan test for instrument over-identification
#'
#' When the model is over-identified (more instruments than
#' endogenous exposures), the Sargan (1958) J-statistic tests the
#' null hypothesis that all instruments are valid (i.e., the
#' exclusion restriction holds).  The statistic is
#'
#' \deqn{J = n \cdot R^2_{uu}}
#'
#' where `R^2_uu` is the R-squared of regressing the 2SLS residuals
#' on all instruments (and controls).  Under H0, `J ~ chi-sq(L - K)`
#' where `L` is the number of instruments and `K` is the number of
#' endogenous regressors.  Rejection (p < 0.05) is evidence that at
#' least one instrument is invalid.
#'
#' @inheritParams causal_iv_fit_2sls
#' @return Named list with `stat`, `df`, `p`.
#' @export
causal_iv_sargan_test <- function(data, exposure, outcome,
                                    instruments, covariates = NULL) {
  if (length(instruments) < 2L) {
    return(list(stat = NA_real_, df = 0L, p = NA_real_))
  }
  # Run 2SLS internally (avoid recursion by inlining core computation)
  cols_needed <- c(exposure, outcome, instruments, covariates)
  df <- data[stats::complete.cases(data[, cols_needed, drop = FALSE]), , drop = FALSE]
  n  <- nrow(df)

  y <- df[[outcome]]
  X <- as.matrix(df[, exposure, drop = FALSE])
  Z <- as.matrix(df[, instruments, drop = FALSE])
  W <- if (is.null(covariates) || length(covariates) == 0L)
          matrix(numeric(0), nrow = n, ncol = 0L)
       else as.matrix(df[, covariates, drop = FALSE])
  ones <- rep(1, n)
  X_all <- cbind(intercept = ones, W, X)
  Z_all <- cbind(intercept = ones, W, Z)

  ZZ_inv <- tryCatch(solve(crossprod(Z_all)),
                      error = function(e) MASS::ginv(crossprod(Z_all)))
  P_Z    <- Z_all %*% ZZ_inv %*% t(Z_all)
  XPX    <- crossprod(X_all, P_Z %*% X_all)
  XPX_inv <- tryCatch(solve(XPX),
                       error = function(e) MASS::ginv(XPX))
  beta   <- as.numeric(XPX_inv %*% crossprod(X_all, P_Z %*% y))
  resid_iv <- as.numeric(y - X_all %*% beta)

  # R^2 of residuals on full instrument set
  df$.resid_iv <- resid_iv
  aux_rhs <- paste(c(covariates, instruments), collapse = " + ")
  aux_fml <- stats::as.formula(sprintf(".resid_iv ~ %s", aux_rhs))
  aux_fit <- stats::lm(aux_fml, data = df)
  R2uu    <- summary(aux_fit)$r.squared

  L <- length(instruments)  # number of instruments
  K <- 1L                    # number of endogenous regressors (only exposure)
  df_sargan <- L - K
  stat      <- n * R2uu
  p         <- 1 - stats::pchisq(stat, df = df_sargan)
  list(stat = stat, df = df_sargan, p = p)
}

# ---------------------------------------------------------------------------
# Bootstrap posterior
# ---------------------------------------------------------------------------

#' Bootstrap posterior for a 2SLS effect as an edaphos_posterior
#'
#' Wraps [`causal_iv_fit_2sls()`] in a nonparametric bootstrap over
#' rows (or over clusters if `cluster` is supplied) and packages the
#' resulting vector of effect estimates as an [`edaphos_posterior()`]
#' so that [`uncertainty_calibrate()`] and [`autoplot()`] apply
#' uniformly.
#'
#' @inheritParams causal_iv_fit_2sls
#' @param B Integer; number of bootstrap resamples.  Default `500L`.
#' @param cluster Optional character; column in `data` to resample by
#'   block (e.g. `"kmeans_cluster"` for spatial resampling).
#' @param seed Optional RNG seed.
#' @param units Optional units string.
#' @return An `edaphos_posterior` with `query_type = "effect"` and
#'   `method = "bootstrap"`.
#' @export
causal_iv_posterior <- function(data, exposure, outcome, instruments,
                                  covariates = NULL,
                                  B = 500L, cluster = NULL,
                                  seed = NULL, units = NULL) {
  if (!is.null(seed)) set.seed(seed)
  draws <- numeric(B)
  if (!is.null(cluster)) {
    stopifnot(cluster %in% names(data))
    clusters_all    <- data[[cluster]]
    unique_clusters <- unique(clusters_all)
    for (b in seq_len(B)) {
      resampled <- sample(unique_clusters, replace = TRUE)
      ix <- unlist(lapply(resampled,
                           function(k) which(clusters_all == k)),
                    use.names = FALSE)
      fit <- tryCatch(
        causal_iv_fit_2sls(data[ix, , drop = FALSE], exposure, outcome,
                           instruments, covariates),
        error = function(e) NULL)
      draws[b] <- if (!is.null(fit)) fit$effect else NA_real_
    }
  } else {
    for (b in seq_len(B)) {
      ix  <- sample(nrow(data), replace = TRUE)
      fit <- tryCatch(
        causal_iv_fit_2sls(data[ix, , drop = FALSE], exposure, outcome,
                           instruments, covariates),
        error = function(e) NULL)
      draws[b] <- if (!is.null(fit)) fit$effect else NA_real_
    }
  }
  draws <- draws[!is.na(draws)]

  edaphos_posterior(
    samples    = matrix(draws, ncol = 1L),
    method     = "bootstrap",
    query_type = "effect",
    units      = units,
    metadata   = list(
      exposure    = exposure, outcome = outcome,
      instruments = instruments, covariates = covariates,
      estimator   = "2SLS", B = length(draws),
      cluster     = cluster
    )
  )
}

# ---------------------------------------------------------------------------
# Convenience: embeddings -> PCA -> IV
# ---------------------------------------------------------------------------

#' Fit 2SLS using foundation-model (or proxy) embeddings as instruments
#'
#' Convenience wrapper that:
#'   1. Takes a matrix of per-profile embeddings (rows = profiles,
#'      columns = embedding dims),
#'   2. Reduces them to `n_pcs` principal components,
#'   3. Attaches the PCs to `data` as new columns named `PC_1`, ...,
#'   4. Runs [`causal_iv_fit_2sls()`] with the PCs as instruments.
#'
#' Using the top `n_pcs` principal components instead of raw
#' embedding dimensions keeps the instrument count manageable
#' (avoiding the curse of dimensionality) and ensures the instruments
#' are orthogonal (which simplifies the Sargan diagnostics).  The
#' default `n_pcs = 5L` yields a 4-over-identified model for a
#' single-exposure query, enabling the Sargan J-test.
#'
#' @param data Data frame with `exposure`, `outcome` and any
#'   `covariates`.
#' @param embeddings Numeric matrix with `nrow(data)` rows (one per
#'   data row) and any number of columns (embedding dimensions).
#' @param exposure,outcome,covariates See [`causal_iv_fit_2sls()`].
#' @param n_pcs Integer; number of top principal components to keep
#'   as instruments.  Default `5L`.
#' @return `edaphos_causal_iv` object (see [`causal_iv_fit_2sls()`]).
#' @export
causal_iv_from_embeddings <- function(data, embeddings,
                                        exposure, outcome,
                                        covariates = NULL,
                                        n_pcs = 5L) {
  stopifnot(nrow(embeddings) == nrow(data),
            n_pcs >= 1L, n_pcs <= ncol(embeddings))
  # Drop zero-variance columns before PCA
  vv <- apply(embeddings, 2, stats::var, na.rm = TRUE)
  emb <- embeddings[, vv > 1e-12, drop = FALSE]
  pr  <- stats::prcomp(emb, center = TRUE, scale. = TRUE,
                         rank. = n_pcs)
  pc_mat <- pr$x[, seq_len(n_pcs), drop = FALSE]
  colnames(pc_mat) <- paste0("PC_", seq_len(n_pcs))
  df <- cbind(data, as.data.frame(pc_mat))
  fit <- causal_iv_fit_2sls(df,
                              exposure    = exposure,
                              outcome     = outcome,
                              instruments = colnames(pc_mat),
                              covariates  = covariates)
  fit$pca_rotation        <- pr$rotation[, seq_len(n_pcs), drop = FALSE]
  fit$pca_variance_explained <- summary(pr)$importance[2, seq_len(n_pcs)]
  fit$embedding_cols      <- colnames(emb)
  fit
}

# ---------------------------------------------------------------------------
# Adapter to edaphos_posterior (for `as_edaphos_posterior()` dispatch)
# ---------------------------------------------------------------------------

#' @export
as_edaphos_posterior.edaphos_causal_iv <- function(x, units = NULL, ...) {
  # Gaussian shortcut from the analytic SE
  edaphos_posterior(
    mean       = x$effect,
    sd         = x$se,
    method     = "analytic",
    query_type = "effect",
    units      = units,
    metadata   = list(
      exposure    = x$exposure, outcome = x$outcome,
      instruments = x$instruments, covariates = x$covariates,
      estimator   = x$estimator, n = x$n,
      stage1_F    = x$stage1_F, sargan_p = x$sargan_p
    )
  )
}
