# Pilar 1 x Pilar 3 bridge -- Causal 4D time-varying effects
# (edaphos v2.2.1).
#
# Mathematical setup
# ------------------
# Pilar 1's backdoor adjustment returns a time-invariant scalar:
#
#     beta_hat = E[ dY / dX | Z ]   averaged over the sample.
#
# Soil-carbon dynamics are non-stationary: the effect of MAP on SOC
# differs in dry vs. wet decades, pre- vs. post-land-use-change, and
# may drift on inter-annual scales.  Causal 4D estimates a
# trajectory
#
#     beta_hat(t) = argmin_beta  sum_{i in W_t} ( y_i - beta x_i - theta' z_i )^2
#
# on a sliding window W_t of width `window` time-slices and stride
# `step`, where (x, y, z) come from the 4D cube of Pilar 3.  The
# resulting time series beta_hat(t) is complemented by:
#
#   * bootstrap CIs per window
#   * a Mann-Kendall trend test for monotonic change
#   * an autoplot method producing the beta(t) trajectory with a
#     "detected-change" overlay
#
# Required input shape
# --------------------
# A "temporal frame" is a `data.frame` or `tibble` with columns:
#
#     t       -- time index (integer or POSIX)
#     lon,lat -- spatial coordinates (numeric)
#     <x>     -- exposure column (e.g. "map")
#     <y>     -- outcome column   (e.g. "soc")
#     <z...>  -- any number of adjustment covariates
#
# When a raw `temporal_cube` array is supplied, it must be paired
# with a `coord_frame` giving (lon, lat) per (h, w) cell; the function
# converts the cube to a long-format frame internally.
#
# Exports
# -------
#   causal_effect_time_varying(frame, dag, exposure, outcome,
#                                window, step, adjustment, B, seed)
#   causal_effect_trend_test(beta_df)
#   autoplot.edaphos_causal_4d() -- ggplot2 method

#' Time-varying causal effect beta(t) over a sliding window
#'
#' Closes the Pilar 1 x Pilar 3 loop: the v1.4.0 backdoor-adjusted
#' estimator is applied within non-overlapping (or overlapping)
#' windows of the temporal frame, producing a beta_hat(t) trajectory
#' with bootstrap CIs.  Mann-Kendall tests for a significant trend.
#'
#' @param frame A data frame with columns `t`, `lon`, `lat`, the
#'   `exposure`, `outcome` and any `adjustment` columns.
#' @param dag A `dagitty` DAG.  Used only to derive the adjustment
#'   set when `adjustment = NULL`.
#' @param exposure,outcome Character column names.
#' @param window Integer; number of distinct `t` values per window.
#' @param step Integer; how many `t` values to advance the window.
#' @param adjustment Optional character vector of adjustment columns.
#' @param B Integer bootstrap replicates per window.  `0` disables
#'   CI estimation (just a point estimate per window).
#' @param min_n Minimum in-window sample size to fit a window.
#'   Windows smaller than this yield `NA` estimates.
#' @param seed Optional RNG seed for bootstrap reproducibility.
#' @return A `data.frame` of class `edaphos_causal_4d` with columns
#'   `t_start`, `t_end`, `t_centre`, `n`, `beta_hat`, `se`, `ci_lo`,
#'   `ci_hi`.
#' @examples
#' # A synthetic 36-slice soil panel: 10 sites, an annual-rainfall
#' # anomaly (mm from the long-term normal) driving topsoil SOC, and
#' # elevation confounding both (orographic rain, cooler moister
#' # soils).  The MAP -> SOC slope is built to decay over the record.
#' set.seed(11)
#' panel <- expand.grid(site = 1:10, t = 1:36)
#' elev  <- runif(10, 400, 1100)
#' panel$elev     <- elev[panel$site]
#' panel$map_anom <- -0.10 * (panel$elev - 750) + rnorm(nrow(panel), 0, 60)
#' panel$soc      <- 22 + 0.006 * panel$elev +
#'   (0.022 - 0.0006 * panel$t) * panel$map_anom + rnorm(nrow(panel), 0, 0.8)
#'
#' # `dag` is consulted only when `adjustment = NULL`, so an explicit
#' # adjustment set lets you pass `dag = NULL`.  Only `t`, the exposure,
#' # the outcome and the adjustment columns are ever read -- the panel
#' # here carries no `lon`/`lat` at all.
#' bt <- causal_effect_time_varying(panel, dag = NULL,
#'                                  exposure = "map_anom", outcome = "soc",
#'                                  window = 12L, step = 3L,
#'                                  adjustment = "elev", B = 0L)
#' bt
#'
#' # Dropping the confounder does not merely add noise: it collapses
#' # the level of the whole trajectory while leaving the downward shape
#' # intact.  A convincing-looking beta(t) decline is therefore no
#' # evidence at all that the backdoor was closed.
#' naive <- causal_effect_time_varying(panel, NULL, "map_anom", "soc",
#'                                     window = 12L, step = 3L,
#'                                     adjustment = character(0), B = 0L)
#' round(rbind(adjusted = bt$beta_hat, naive = naive$beta_hat), 4)
#' round(c(adjusted = mean(bt$beta_hat), naive = mean(naive$beta_hat)), 4)
#'
#' # With B = 0 the interval is exactly beta_hat +/- 1.96 * se, not a
#' # bootstrap.  Note also how the metadata attributes survive
#' # subsetting: `[` KEEPS them when you subset rows (R >= 4.0), but
#' # drops them the moment you subset columns, after which print()
#' # reports "adjustment : <none>".  as.data.frame() is the safe route
#' # when you only want the numbers.
#' isTRUE(all.equal(bt$ci_lo, bt$beta_hat - qnorm(0.975) * bt$se))
#' head(as.data.frame(bt)[, c("t_centre", "n", "beta_hat", "ci_lo")], 3)
#'
#' # dagitty can derive the same adjustment set from the graph instead.
#' if (requireNamespace("dagitty", quietly = TRUE)) {
#'   dag <- dagitty::dagitty(
#'     "dag { elev -> map_anom  elev -> soc  map_anom -> soc }")
#'   bt2 <- causal_effect_time_varying(panel, dag, "map_anom", "soc",
#'                                     window = 12L, step = 3L, B = 0L)
#'   identical(attr(bt2, "adjustment"), "elev")
#' }
#' @export
causal_effect_time_varying <- function(frame, dag,
                                         exposure, outcome,
                                         window = 24L, step = 6L,
                                         adjustment = NULL,
                                         B = 200L, min_n = 30L,
                                         seed = NULL) {
  stopifnot(is.data.frame(frame),
             is.character(exposure), length(exposure) == 1L,
             is.character(outcome),  length(outcome)  == 1L)
  # Resolve adjustment set
  if (is.null(adjustment)) {
    if (!requireNamespace("dagitty", quietly = TRUE))
      stop("Install `dagitty` to auto-derive the adjustment set, or ",
            "pass `adjustment` explicitly.", call. = FALSE)
    adjustment <- tryCatch(
      causal_adjustment_set(dag, exposure, outcome, effect = "direct"),
      error = function(e) character(0)
    )
    if (length(adjustment) == 0L)
      adjustment <- character(0)
  }

  cols_needed <- c("t", exposure, outcome, adjustment)
  miss <- setdiff(cols_needed, names(frame))
  if (length(miss) > 0L)
    stop(sprintf("Columns not found in frame: %s",
                   paste(miss, collapse = ", ")), call. = FALSE)

  t_vec <- sort(unique(frame$t))
  if (length(t_vec) < window)
    stop("Temporal frame has fewer distinct t values than `window`.",
          call. = FALSE)

  if (!is.null(seed)) set.seed(seed)

  # Sliding windows
  t_starts <- seq(1L, length(t_vec) - window + 1L, by = step)
  out <- lapply(t_starts, function(i0) {
    t_in <- t_vec[i0:(i0 + window - 1L)]
    sub  <- frame[frame$t %in% t_in, , drop = FALSE]
    n    <- nrow(sub)
    if (n < min_n) {
      return(data.frame(
        t_start  = t_in[1L], t_end = t_in[length(t_in)],
        t_centre = t_in[length(t_in) %/% 2L + 1L],
        n        = n,
        beta_hat = NA_real_, se = NA_real_,
        ci_lo    = NA_real_, ci_hi = NA_real_,
        stringsAsFactors = FALSE
      ))
    }
    terms <- unique(c(exposure, adjustment))
    form  <- stats::reformulate(terms, response = outcome)
    fit   <- stats::lm(form, data = sub)
    co    <- summary(fit)$coefficients
    beta  <- unname(co[exposure, "Estimate"])
    se    <- unname(co[exposure, "Std. Error"])

    # Optional bootstrap for robust CIs
    if (B > 0L) {
      n_boot <- as.integer(B)
      betas <- numeric(n_boot)
      for (b in seq_len(n_boot)) {
        ix <- sample(n, replace = TRUE)
        fit_b <- tryCatch(stats::lm(form, data = sub[ix, , drop = FALSE]),
                            error = function(e) NULL)
        betas[b] <- if (!is.null(fit_b))
          unname(stats::coef(fit_b)[exposure]) else NA_real_
      }
      betas <- betas[is.finite(betas)]
      if (length(betas) > 10L) {
        ci <- stats::quantile(betas, probs = c(0.025, 0.975),
                                names = FALSE)
      } else {
        ci <- beta + c(-1, 1) * stats::qnorm(0.975) * se
      }
    } else {
      ci <- beta + c(-1, 1) * stats::qnorm(0.975) * se
    }
    data.frame(
      t_start  = t_in[1L], t_end = t_in[length(t_in)],
      t_centre = t_in[length(t_in) %/% 2L + 1L],
      n        = n,
      beta_hat = beta, se = se,
      ci_lo    = ci[1L], ci_hi = ci[2L],
      stringsAsFactors = FALSE
    )
  })
  out_df <- do.call(rbind, out)
  structure(out_df,
             class      = c("edaphos_causal_4d", "data.frame"),
             exposure   = exposure,
             outcome    = outcome,
             adjustment = adjustment,
             window     = window,
             step       = step,
             B          = B)
}

#' Mann-Kendall trend test on a beta(t) trajectory
#'
#' Non-parametric two-sided Mann-Kendall test for a monotonic trend
#' in the time-varying causal effect.  The S statistic counts sign-
#' consistent pairs; p-value is the normal approximation.
#'
#' @param beta_df An `edaphos_causal_4d` object.
#' @return Named list with `S`, `tau`, `p_value`, `trend_direction`
#'   (`"increasing"` / `"decreasing"` / `"none"`).
#' @examples
#' # One synthetic soil panel per seed: elevation confounds a rainfall
#' # anomaly and topsoil SOC, and `drift` fixes how fast the causal
#' # MAP -> SOC slope decays across the 36 time slices.
#' sim_beta <- function(seed, drift) {
#'   set.seed(seed)
#'   d <- expand.grid(site = 1:10, t = 1:36)
#'   e <- runif(10, 400, 1100)
#'   d$elev     <- e[d$site]
#'   d$map_anom <- -0.10 * (d$elev - 750) + rnorm(nrow(d), 0, 60)
#'   d$soc      <- 22 + 0.006 * d$elev +
#'     (0.022 - drift * d$t) * d$map_anom + rnorm(nrow(d), 0, 0.8)
#'   causal_effect_time_varying(d, NULL, "map_anom", "soc", window = 12L,
#'                              step = 3L, adjustment = "elev", B = 0L)
#' }
#'
#' # A genuine decay is picked up: tau = -1, p = 0.000263, "decreasing".
#' bt <- sim_beta(11, drift = 0.0006)
#' causal_effect_trend_test(bt)
#'
#' # The test reads `beta_hat` and nothing else.  Inflating every
#' # standard error a thousandfold leaves the verdict untouched, so a
#' # window fitted on 30 points votes as loudly as one fitted on 3000.
#' loose <- bt
#' loose$se <- loose$se * 1000
#' identical(causal_effect_trend_test(loose), causal_effect_trend_test(bt))
#'
#' # "none" can also mean "not enough windows": with fewer than four
#' # finite beta_hat values the test returns p_value = NA and direction
#' # "none".  That is silence, not evidence of a stable effect.
#' causal_effect_trend_test(bt[1:3, ])
#'
#' # The normal approximation assumes independent windows.  At step = 3
#' # and window = 12 neighbouring windows share 9 of their 12 slices, so
#' # the p-value is badly anti-conservative: under a constant effect
#' # (drift = 0) it still flags a trend in 0.3 of 60 replicates, six
#' # times the nominal 0.05.  Use step >= window before quoting p.
#' p_null <- vapply(1:60, function(s) {
#'   causal_effect_trend_test(sim_beta(s, drift = 0))$p_value
#' }, numeric(1))
#' mean(p_null < 0.05)
#' @export
causal_effect_trend_test <- function(beta_df) {
  x <- beta_df$beta_hat
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 4L) {
    return(list(S = NA, tau = NA, p_value = NA,
                 trend_direction = "none"))
  }
  S <- 0
  for (i in seq_len(n - 1L)) {
    S <- S + sum(sign(x[(i + 1L):n] - x[i]))
  }
  # Variance of S (no ties correction)
  varS <- n * (n - 1L) * (2L * n + 5L) / 18
  z <- if (S > 0) (S - 1) / sqrt(varS) else
       if (S < 0) (S + 1) / sqrt(varS) else 0
  p <- 2 * (1 - stats::pnorm(abs(z)))
  tau <- S / choose(n, 2L)
  dir <- if (p >= 0.05) "none" else
         if (S > 0)     "increasing" else "decreasing"
  list(S = S, tau = tau, p_value = p, trend_direction = dir, z = z, n = n)
}

#' @export
print.edaphos_causal_4d <- function(x, ...) {
  cat("<edaphos_causal_4d>  (Pilar 1 x Pilar 3 bridge)\n")
  cat(sprintf("  target effect : %s -> %s\n",
               attr(x, "exposure"), attr(x, "outcome")))
  adj <- attr(x, "adjustment")
  cat(sprintf("  adjustment    : %s\n",
               if (length(adj) == 0L) "<none>" else paste(adj, collapse = ", ")))
  cat(sprintf("  window / step : %d / %d\n",
               attr(x, "window"), attr(x, "step")))
  cat(sprintf("  n windows     : %d\n", nrow(x)))
  cat(sprintf("  beta_hat mean : %.4f (range [%.4f, %.4f])\n",
               mean(x$beta_hat, na.rm = TRUE),
               min(x$beta_hat,  na.rm = TRUE),
               max(x$beta_hat,  na.rm = TRUE)))
  tt <- causal_effect_trend_test(x)
  cat(sprintf("  Mann-Kendall  : S=%s, tau=%s, p=%s, trend=%s\n",
               format(tt$S, digits = 3),
               format(tt$tau, digits = 3),
               format(tt$p_value, digits = 3),
               tt$trend_direction))
  invisible(x)
}

#' Plot a time-varying causal effect trajectory
#'
#' Returns a `ggplot` object showing beta(t) + bootstrap CI ribbon,
#' with a Mann-Kendall trend summary as the plot subtitle.  Requires
#' `ggplot2`.
#'
#' @param object An `edaphos_causal_4d` frame from
#'   [`causal_effect_time_varying()`].
#' @param ... Unused.
#' @return A `ggplot` object.
#' @examples
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   # Synthetic panel whose MAP -> SOC effect decays over 36 slices,
#'   # with elevation as the confounder that must be adjusted away.
#'   set.seed(11)
#'   panel <- expand.grid(site = 1:10, t = 1:36)
#'   elev  <- runif(10, 400, 1100)
#'   panel$elev     <- elev[panel$site]
#'   panel$map_anom <- -0.10 * (panel$elev - 750) + rnorm(nrow(panel), 0, 60)
#'   panel$soc      <- 22 + 0.006 * panel$elev +
#'     (0.022 - 0.0006 * panel$t) * panel$map_anom + rnorm(nrow(panel), 0, 0.8)
#'
#'   boot <- causal_effect_time_varying(panel, NULL, "map_anom", "soc",
#'                                      window = 12L, step = 3L,
#'                                      adjustment = "elev", B = 100L,
#'                                      seed = 42)
#'   g <- causal_4d_plot(boot)
#'   print(inherits(g, "ggplot"))   # print(g) draws it on the device
#'
#'   # The subtitle is a live Mann-Kendall test on exactly the windows
#'   # being drawn, so it inherits their overlap.  Read it as a label
#'   # for the curve, not as an independent significance test.
#'   print(g$labels$subtitle)
#'
#'   # The ribbon is simply ci_lo/ci_hi.  With B = 0 those are the OLS
#'   # normal limits rather than a bootstrap, and the ribbon looks no
#'   # different: here the bootstrap band is in fact the narrower of
#'   # the two (mean width 0.00485 against 0.00515).
#'   norm <- causal_effect_time_varying(panel, NULL, "map_anom", "soc",
#'                                      window = 12L, step = 3L,
#'                                      adjustment = "elev", B = 0L)
#'   print(round(c(bootstrap = mean(boot$ci_hi - boot$ci_lo),
#'                 normal    = mean(norm$ci_hi - norm$ci_lo)), 5))
#'
#'   # No autoplot() method is registered for this class, despite the
#'   # wording of the error raised when ggplot2 is missing.
#'   inherits(try(ggplot2::autoplot(boot), silent = TRUE), "try-error")
#' }
#' @export
causal_4d_plot <- function(object, ...) {
  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("Install `ggplot2` to use autoplot.", call. = FALSE)
  d <- as.data.frame(object)
  tt <- causal_effect_trend_test(object)
  ggplot2::ggplot(d, ggplot2::aes(x = .data$t_centre,
                                     y = .data$beta_hat)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$ci_lo,
                                         ymax = .data$ci_hi),
                           alpha = 0.25, fill = "#2980B9") +
    ggplot2::geom_line(linewidth = 1, colour = "#2980B9") +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed",
                         colour = "grey50") +
    ggplot2::labs(
      x = "Time (window centre)",
      y = sprintf("beta_hat( %s -> %s )",
                  attr(object, "exposure"),
                  attr(object, "outcome")),
      title = "Time-varying causal effect",
      subtitle = sprintf(
        "Mann-Kendall: S=%s, tau=%s, p=%s (%s)",
        format(tt$S, digits = 3),
        format(tt$tau, digits = 3),
        format(tt$p_value, digits = 3),
        tt$trend_direction
      )
    )
}
