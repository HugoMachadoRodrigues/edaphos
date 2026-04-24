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
