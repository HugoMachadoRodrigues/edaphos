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
#'
#' @examples
#' # A liming study confounded by management: unobserved agronomic
#' # intensity raises both soil pH and yield, so no regression of
#' # yield on pH can identify the causal effect.
#' set.seed(42)
#' n <- 300
#' mgmt      <- rnorm(n)          # unobserved agronomic intensity
#' carbonate <- runif(n, 0, 12)   # parent-rock CaCO3, per cent
#' quarry_km <- runif(n, 1, 60)   # distance to the nearest lime quarry
#' ph    <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km +
#'          0.45 * mgmt + rnorm(n, 0, 0.25)
#' yield <- 1.0 + 1.5 * ph + 1.3 * mgmt + rnorm(n, 0, 0.4)
#' soil  <- data.frame(ph, yield, carbonate, quarry_km)
#'
#' # The true effect is 1.5 t/ha per pH unit. OLS returns 2.85 --
#' # nearly double -- because it credits pH with the yield that
#' # management delivered.
#' ols <- lm(yield ~ ph, data = soil)
#' coef(ols)[["ph"]]
#'
#' # 2SLS uses only the pH variation forced by geology, which
#' # management cannot touch: 1.62, with a 95 per cent interval that
#' # covers 1.5.
#' fit <- causal_iv_fit_2sls(soil, exposure = "ph", outcome = "yield",
#'                           instruments = c("carbonate", "quarry_km"))
#' fit
#'
#' # Consistency is bought with variance: the IV standard error here
#' # is about twice the OLS one. Quoting the narrow OLS interval
#' # around the wrong number is what this estimator exists to avoid.
#' c(ols = summary(ols)$coefficients["ph", "Std. Error"], iv = fit$se)
#'
#' # `effect` is the exposure coefficient alone; `coefs` carries the
#' # whole second-stage vector and `vcov` its 2SLS covariance -- not
#' # the naive lm() covariance of a regression on fitted values.
#' fit$coefs
#' sqrt(diag(fit$vcov))
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
#'
#' @examples
#' # Relevance is the one IV assumption the data can actually check,
#' # so run the first stage before trusting any 2SLS point estimate.
#' set.seed(42)
#' n <- 300
#' mgmt      <- rnorm(n)
#' carbonate <- runif(n, 0, 12)   # parent-rock CaCO3, per cent
#' quarry_km <- runif(n, 1, 60)   # distance to the nearest lime quarry
#' clay      <- rnorm(n, 35, 8)   # exogenous control that also drives pH
#' ph <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km + 0.06 * clay +
#'       0.45 * mgmt + rnorm(n, 0, 0.25)
#' soil <- data.frame(ph, carbonate, quarry_km, clay,
#'                    rainfall_resid = rnorm(n))
#'
#' fs <- causal_iv_first_stage(soil, exposure = "ph",
#'                             instruments = c("carbonate", "quarry_km"),
#'                             covariates = "clay")
#' c(F = fs$F, R2 = fs$R2, R2_partial = fs$R2_partial)
#'
#' # F = 81 clears the Stock-Yogo rule of thumb by a wide margin. The
#' # rule is not a significance test: F = 10 is roughly where 2SLS
#' # bias back towards OLS, and under-coverage of the nominal 95 per
#' # cent interval, stop being negligible.
#' fs$F > 10
#'
#' # The trap: `R2` scores the WHOLE first stage, controls included,
#' # so it stays respectable even when the instruments are worthless.
#' # Replacing them with noise leaves R2 at 0.35 -- down from 0.58, but
#' # still the sort of number that reads as "the model fits", and all
#' # of it carried by clay. F and the partial R2 do not survive the
#' # substitution at all: 81 -> 0.33 and 0.354 -> 0.001. A drop of
#' # 40 per cent against drops of 245x and 320x is the whole point --
#' # only `R2_partial` and `F` speak to identification.
#' bad <- causal_iv_first_stage(soil, exposure = "ph",
#'                              instruments = "rainfall_resid",
#'                              covariates = "clay")
#' c(F = bad$F, R2 = bad$R2, R2_partial = bad$R2_partial)
#'
#' # `full_fit` is the fitted lm, so the individual first-stage slopes
#' # can be signed against agronomy: carbonate raises pH, distance to
#' # the quarry lowers it.
#' coef(fs$full_fit)
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
#'
#' @examples
#' # `carb_direct` and `quarry_direct` let an instrument reach yield
#' # WITHOUT going through pH, i.e. break the exclusion restriction.
#' sim_liming <- function(seed = 42, carb_direct = 0,
#'                        quarry_direct = 0) {
#'   set.seed(seed)
#'   n <- 300
#'   mgmt      <- rnorm(n)
#'   carbonate <- runif(n, 0, 12)
#'   quarry_km <- runif(n, 1, 60)
#'   ph    <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km +
#'            0.45 * mgmt + rnorm(n, 0, 0.25)
#'   yield <- 1.0 + 1.5 * ph + 1.3 * mgmt + rnorm(n, 0, 0.4) +
#'            carb_direct * carbonate + quarry_direct * quarry_km
#'   data.frame(ph, yield, carbonate, quarry_km)
#' }
#' soil <- sim_liming()
#'
#' # The test needs MORE instruments than endogenous exposures. One
#' # instrument for one exposure is exactly identified: there is
#' # nothing to over-identify, and you get NA rather than a
#' # reassuring p-value.
#' causal_iv_sargan_test(soil, "ph", "yield", instruments = "carbonate")
#'
#' # Two instruments, both valid by construction: J = 0.27 on 1 df,
#' # p = 0.60, no evidence against the exclusion restriction.
#' causal_iv_sargan_test(soil, "ph", "yield",
#'                       instruments = c("carbonate", "quarry_km"))
#'
#' # Let carbonate fertilise the crop directly, breaking exclusion for
#' # that instrument only. The two instruments now disagree about the
#' # effect and the test fires: J = 19.6, p = 9.4e-06.
#' causal_iv_sargan_test(sim_liming(carb_direct = 0.15), "ph", "yield",
#'                       instruments = c("carbonate", "quarry_km"))
#'
#' # What a non-rejection does NOT prove. Break BOTH instruments in
#' # proportion to their first-stage strength and they agree on the
#' # same wrong answer, so Sargan sees no conflict (p = 0.92) while
#' # 2SLS returns 2.93 against a truth of 1.5. The J-statistic
#' # compares instruments with each other; a bias they share is
#' # invisible to it, and no over-identification test can license the
#' # exclusion restriction on its own.
#' soil_worse <- sim_liming(carb_direct = 0.15, quarry_direct = -0.015)
#' causal_iv_sargan_test(soil_worse, "ph", "yield",
#'                       instruments = c("carbonate", "quarry_km"))$p
#' causal_iv_fit_2sls(soil_worse, "ph", "yield",
#'                    instruments = c("carbonate", "quarry_km"))$effect
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
#'
#' @examples
#' # Geology is a landscape attribute, so the instruments are constant
#' # within a farm -- and the agronomy shock is shared within a farm
#' # too. That is the regime where row-wise resampling lies.
#' set.seed(7)
#' n_farm     <- 40
#' farm       <- rep(seq_len(n_farm), each = 8)
#' farm_shock <- rnorm(n_farm, 0, 1.2)[farm]   # shared agronomy
#' carbonate  <- runif(n_farm, 0, 12)[farm]    # parent-rock CaCO3
#' quarry_km  <- runif(n_farm, 1, 60)[farm]    # km to the lime quarry
#' n     <- length(farm)
#' mgmt  <- rnorm(n)
#' ph    <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km +
#'          0.45 * mgmt + rnorm(n, 0, 0.25)
#' yield <- 1.0 + 1.5 * ph + 1.3 * mgmt + farm_shock + rnorm(n, 0, 0.4)
#' soil  <- data.frame(ph, yield, carbonate, quarry_km, farm)
#'
#' # Resampling rows pretends the 320 plots are 320 independent draws.
#' iv_rows <- causal_iv_posterior(
#'   soil, "ph", "yield", instruments = c("carbonate", "quarry_km"),
#'   B = 150L, seed = 1, units = "t/ha per pH unit")
#'
#' # Resampling farms respects the level at which the instruments and
#' # the shock actually vary.
#' iv_farms <- causal_iv_posterior(
#'   soil, "ph", "yield", instruments = c("carbonate", "quarry_km"),
#'   B = 150L, cluster = "farm", seed = 1, units = "t/ha per pH unit")
#'
#' # The cluster bootstrap is about twice as wide, 0.48 against 0.23.
#' # The analytic 2SLS standard error, 0.22, agrees with the row
#' # bootstrap and is just as wrong: neither knows the effective
#' # sample size is 40 farms, not 320 plots.
#' fit <- causal_iv_fit_2sls(soil, "ph", "yield",
#'                           instruments = c("carbonate", "quarry_km"))
#' c(analytic = fit$se, boot_rows = iv_rows$sd, boot_farms = iv_farms$sd)
#'
#' # The centre barely moves: clustering is about uncertainty, not
#' # about bias. Both results are ordinary edaphos_posterior objects.
#' iv_farms
#' c(rows = iv_rows$mean, farms = iv_farms$mean)
#'
#' # Resamples that fail to fit are dropped silently, so check how
#' # many draws actually survived before quoting an interval.
#' iv_farms$metadata$B
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
#'
#' @examples
#' # Patch embeddings as candidate instruments. Only four of the
#' # twelve dimensions track the parent material; the other eight
#' # track canopy, which carries no geology at all.
#' set.seed(11)
#' n <- 300
#' mgmt      <- rnorm(n)
#' carbonate <- runif(n, 0, 12)
#' quarry_km <- runif(n, 1, 60)
#' ph    <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km +
#'          0.45 * mgmt + rnorm(n, 0, 0.25)
#' yield <- 1.0 + 1.5 * ph + 1.3 * mgmt + rnorm(n, 0, 0.4)
#' soil  <- data.frame(ph, yield)
#'
#' canopy <- rnorm(n)
#' emb <- cbind(
#'   matrix(canopy, n, 8)           + matrix(rnorm(n * 8, 0, 0.5), n),
#'   matrix(scale(carbonate), n, 2) + matrix(rnorm(n * 2, 0, 0.5), n),
#'   matrix(scale(quarry_km), n, 2) + matrix(rnorm(n * 2, 0, 0.5), n)
#' )
#' colnames(emb) <- paste0("emb_", 1:12)
#'
#' # The trap: prcomp ranks components by variance in the EMBEDDING,
#' # not by relevance to the exposure. PC_1 holds 0.56 of that
#' # variance and is pure canopy, so on its own it is a
#' # non-instrument: F = 0.03 and an interval from -13.5 to +19.4.
#' causal_iv_from_embeddings(soil, emb, "ph", "yield", n_pcs = 1L)
#'
#' # Three PCs reach the geology directions: F = 45.6, and the
#' # interval [0.87, 1.75] covers the true effect of 1.5.
#' causal_iv_from_embeddings(soil, emb, "ph", "yield", n_pcs = 3L)
#'
#' # More PCs is not monotonically better. The default n_pcs = 5L buys
#' # extra Sargan degrees of freedom but dilutes the joint first-stage
#' # F, which tests a growing number of restrictions: it falls from
#' # 45.6 at three PCs to 27.9 at five while the estimate barely
#' # moves. Choose n_pcs on the first stage, not on a default.
#' sapply(1:5, function(k)
#'   causal_iv_from_embeddings(soil, emb, "ph", "yield",
#'                             n_pcs = k)$stage1_F)
#'
#' # `pca_variance_explained` documents the choice, but read it as an
#' # audit trail rather than a relevance ranking -- PC_1 dominates it
#' # and is the one component that identifies nothing.
#' fit <- causal_iv_from_embeddings(soil, emb, "ph", "yield", n_pcs = 3L)
#' round(fit$pca_variance_explained, 3)
#'
#' # Constant embedding dimensions are dropped before PCA rather than
#' # breaking `scale. = TRUE`; `embedding_cols` records what survived.
#' length(causal_iv_from_embeddings(soil, cbind(emb, dead_dim = 1),
#'                                  "ph", "yield",
#'                                  n_pcs = 3L)$embedding_cols)
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
