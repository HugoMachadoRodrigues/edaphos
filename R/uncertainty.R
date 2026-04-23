# Pillar-wide unified uncertainty API (introduced in v1.6.0).
#
# Every pillar in edaphos quantifies uncertainty in its own natural
# format: Pillar 1 returns a block-bootstrap vector of effect
# estimates; Pillar 2 produces either MCMC draws (Bayesian PIML) or
# a deep-ensemble of Neural-ODE fits; Pillar 3 returns a ConvLSTM
# forecast ensemble and/or the posterior of `temporal_kalman_update`;
# Pillar 4 (from v1.6.0) returns a fine-tuned-head ensemble plus
# optional MC-dropout samples; Pillar 5's QRF hands back per-query
# prediction intervals; Pillar 6's Quantum Kernel Ridge Regression
# (from v1.6.0) returns the GP-equivalent posterior variance.
#
# Each of those objects boils down to the same abstract quantity:
# **a posterior over the predictive quantity, expressed either as a
# sample of Monte-Carlo draws or as a Gaussian (mu, sigma) summary**.
#
# This file defines a single S3 class, `edaphos_posterior`, that
# carries that posterior in a shape-preserving way along with an
# optional epistemic / aleatoric decomposition, a method label and
# units. Downstream helpers work on the class:
#
#   uncertainty_calibrate(post, truth)  -> CRPS, PICP@p, MPIW@p,
#                                            reliability curve
#   autoplot(post)                       -> ggplot2 figures by query
#                                            type (effect, map, ...).
#   as_edaphos_posterior(x)              -> S3 generic that adapts
#                                            native pillar objects
#                                            (see adapters in
#                                            causal_*, piml_*,
#                                            temporal_*, foundation_*,
#                                            active_*, quantum_*).

# ---------------------------------------------------------------------------
# Low-level constructor
# ---------------------------------------------------------------------------

#' Unified posterior object for the edaphos pillars
#'
#' Constructs an `edaphos_posterior` --- the single S3 class that
#' edaphos uses to represent predictive uncertainty regardless of
#' which pillar produced it. The constructor accepts either a
#' sample-based posterior (`samples`) or a Gaussian summary
#' (`mean` + `sd`), and derives the missing fields automatically.
#'
#' @param samples Optional numeric array or matrix. The first axis
#'   is the posterior-draw axis of length `n_samples`; the remaining
#'   axes are the query shape. A 1-D vector is treated as
#'   `n_samples` scalar draws.
#' @param mean Optional numeric array with the query shape. If
#'   `samples` is `NULL`, required together with `sd`.
#' @param sd Optional numeric array with the query shape.
#' @param epistemic_sd,aleatoric_sd Optional numeric arrays with the
#'   query shape; the variance decomposition
#'   `epistemic_sd^2 + aleatoric_sd^2 ~ sd^2` is expected to hold
#'   approximately (exact for Gaussian posteriors).
#' @param probs Numeric vector of quantile probabilities to pre-
#'   compute from `samples`. Defaults to `c(0.05, 0.5, 0.95)`.
#' @param method Character tag describing how the posterior was
#'   produced, for diagnostics and plotting. One of `"ensemble"`,
#'   `"bootstrap"`, `"mcdropout"`, `"bayesian"`, `"loo_cv"`,
#'   `"shots"`, `"analytic"`, `"gaussian"`.
#' @param query_type Character tag describing what the posterior
#'   is over. One of `"effect"`, `"param"`, `"map"`, `"feature"`,
#'   `"sample"`, `"energy"`, `"other"`.
#' @param units Optional free-text tag (e.g. "g/kg", "NDVI z-units").
#' @param metadata Optional list of extra provenance fields.
#' @param n_samples_if_gaussian If only `mean` and `sd` are provided,
#'   the constructor synthesises this many Gaussian draws so that
#'   downstream helpers (`uncertainty_calibrate`, `autoplot`) always
#'   have a sample to work with. Defaults to `500L`.
#'
#' @return An `edaphos_posterior` object. See `?edaphos_posterior`
#'   for the list of invariants the class satisfies.
#' @export
#' @examples
#' # From a posterior sample
#' post <- edaphos_posterior(
#'   samples    = matrix(stats::rnorm(200), nrow = 100, ncol = 2),
#'   method     = "bootstrap",
#'   query_type = "effect",
#'   units      = "g/kg per mm"
#' )
#' post
#'
#' # From a Gaussian summary
#' post2 <- edaphos_posterior(
#'   mean       = c(0.5, 0.7),
#'   sd         = c(0.1, 0.2),
#'   method     = "gaussian",
#'   query_type = "param"
#' )
#' post2
edaphos_posterior <- function(samples = NULL,
                              mean = NULL, sd = NULL,
                              epistemic_sd = NULL, aleatoric_sd = NULL,
                              probs = c(0.05, 0.5, 0.95),
                              method = c("ensemble", "bootstrap",
                                          "mcdropout", "bayesian",
                                          "loo_cv", "shots",
                                          "analytic", "gaussian"),
                              query_type = c("effect", "param", "map",
                                              "feature", "sample",
                                              "energy", "other"),
                              units = NULL,
                              metadata = list(),
                              n_samples_if_gaussian = 500L) {
  method     <- match.arg(method)
  query_type <- match.arg(query_type)
  stopifnot(is.numeric(probs), all(probs > 0 & probs < 1))
  probs <- sort(unique(probs))

  if (is.null(samples) && (is.null(mean) || is.null(sd))) {
    stop("Provide either `samples` or both `mean` and `sd`.", call. = FALSE)
  }

  if (is.null(samples)) {
    # Gaussian shortcut -- synthesise draws so the CRPS / calibration
    # helpers have something to work with.
    stopifnot(is.numeric(mean), is.numeric(sd),
              length(mean) == length(sd), all(sd >= 0))
    n    <- as.integer(n_samples_if_gaussian)
    shape <- if (is.array(mean)) dim(mean) else length(mean)
    # Draw from independent Gaussians and reshape.
    flat <- matrix(stats::rnorm(n * prod(shape),
                                 mean = rep(as.numeric(mean), each = n),
                                 sd   = rep(as.numeric(sd),   each = n)),
                   nrow = n, ncol = prod(shape))
    samples <- if (length(shape) > 1L) {
      array(flat, dim = c(n, shape))
    } else {
      flat
    }
  } else {
    if (!(is.array(samples) || is.matrix(samples) || is.vector(samples))) {
      stop("`samples` must be a numeric vector, matrix or array.",
           call. = FALSE)
    }
    if (is.vector(samples) && !is.matrix(samples) && !is.array(samples)) {
      # Treat a bare numeric vector as n_samples scalar draws.
      samples <- matrix(as.numeric(samples), ncol = 1L)
    }
  }

  # ---- summary stats over the first (sample) axis --------------------------
  n_samples <- dim(samples)[1L]
  query_dims <- dim(samples)[-1L]
  .margin <- if (length(query_dims) == 0L) NULL else seq_along(query_dims) + 1L

  if (is.null(.margin)) {
    # (n_samples, 1) matrix produced from a bare vector
    mean_out <- mean(samples[, 1L])
    sd_out   <- stats::sd(samples[, 1L])
    q_out    <- stats::setNames(
      as.list(stats::quantile(samples[, 1L], probs = probs, names = FALSE)),
      sprintf("q%02d", round(probs * 100))
    )
  } else {
    mean_out <- apply(samples, .margin, mean)
    sd_out   <- apply(samples, .margin, stats::sd)
    q_out    <- stats::setNames(
      lapply(probs, function(p) apply(samples, .margin,
                                        stats::quantile, probs = p,
                                        names = FALSE)),
      sprintf("q%02d", round(probs * 100))
    )
  }

  # If the user passed explicit mean / sd, prefer those over the
  # sample-based summary (relevant when samples were Gaussian-synthesised).
  if (!is.null(mean)) mean_out <- mean
  if (!is.null(sd))   sd_out   <- sd

  structure(
    list(
      mean         = mean_out,
      sd           = sd_out,
      samples      = samples,
      epistemic_sd = epistemic_sd,
      aleatoric_sd = aleatoric_sd,
      quantiles    = q_out,
      method       = method,
      query_type   = query_type,
      units        = units,
      metadata     = as.list(metadata)
    ),
    class = "edaphos_posterior"
  )
}

# ---------------------------------------------------------------------------
# Print / summary
# ---------------------------------------------------------------------------

#' @export
print.edaphos_posterior <- function(x, ...) {
  cat("<edaphos_posterior>\n")
  cat(sprintf("  method      : %s\n", x$method))
  cat(sprintf("  query_type  : %s\n", x$query_type))
  if (!is.null(x$units)) cat(sprintf("  units       : %s\n", x$units))
  sh <- if (is.array(x$samples)) dim(x$samples) else length(x$samples)
  cat(sprintf("  n_samples   : %d\n", sh[1L]))
  qshape <- if (length(sh) > 1L) paste(sh[-1L], collapse = " x ") else "scalar"
  cat(sprintf("  query shape : %s\n", qshape))
  if (is.numeric(x$mean) && length(x$mean) > 0L) {
    .fm <- function(v) sprintf("[%+.4f, %+.4f]  mean = %+.4f",
                                min(v, na.rm = TRUE),
                                max(v, na.rm = TRUE),
                                mean(v, na.rm = TRUE))
    cat(sprintf("  mean range  : %s\n", .fm(as.numeric(x$mean))))
    cat(sprintf("  sd   range  : %s\n", .fm(as.numeric(x$sd))))
    if (!is.null(x$epistemic_sd))
      cat(sprintf("  epistemic sd: %s\n", .fm(as.numeric(x$epistemic_sd))))
    if (!is.null(x$aleatoric_sd))
      cat(sprintf("  aleatoric sd: %s\n", .fm(as.numeric(x$aleatoric_sd))))
  }
  invisible(x)
}

#' @export
summary.edaphos_posterior <- function(object, ...) {
  print(object)
  cat("\nQuantiles (over query shape):\n")
  for (nm in names(object$quantiles)) {
    v <- as.numeric(object$quantiles[[nm]])
    cat(sprintf("  %-5s : min=%+.4f  med=%+.4f  max=%+.4f\n",
                nm,
                min(v, na.rm = TRUE),
                stats::median(v, na.rm = TRUE),
                max(v, na.rm = TRUE)))
  }
  invisible(object)
}

# ---------------------------------------------------------------------------
# Adapter generic
# ---------------------------------------------------------------------------

#' Coerce a native pillar object to `edaphos_posterior`
#'
#' Each pillar ships an `as_edaphos_posterior()` method that wraps
#' its natural uncertainty representation in the unified class. The
#' default method accepts already-wrapped objects, numeric vectors
#' (treated as a 1-D scalar posterior), and numeric matrices (treated
#' as `n_samples x n_query` matrices).
#'
#' @param x Object to coerce.
#' @param ... Additional arguments passed to the pillar-specific
#'   method (e.g. `query_type`, `units`).
#' @return An `edaphos_posterior`.
#' @export
as_edaphos_posterior <- function(x, ...) UseMethod("as_edaphos_posterior")

#' @export
as_edaphos_posterior.edaphos_posterior <- function(x, ...) x

#' @export
as_edaphos_posterior.default <- function(x,
                                          method = "ensemble",
                                          query_type = "other",
                                          units = NULL, ...) {
  if (is.numeric(x) && is.null(dim(x))) {
    return(edaphos_posterior(samples = matrix(x, ncol = 1L),
                              method = method,
                              query_type = query_type,
                              units = units, ...))
  }
  if (is.matrix(x)) {
    return(edaphos_posterior(samples = x,
                              method = method,
                              query_type = query_type,
                              units = units, ...))
  }
  stop(sprintf("No `as_edaphos_posterior` method for class <%s>.",
                paste(class(x), collapse = "/")),
       call. = FALSE)
}

# ---------------------------------------------------------------------------
# Calibration
# ---------------------------------------------------------------------------

#' Calibration diagnostics for an `edaphos_posterior`
#'
#' Computes the continuous ranked probability score (CRPS), a
#' prediction-interval coverage probability (PICP) at each requested
#' nominal level, the mean prediction-interval width (MPIW) at
#' the same levels, and a ready-for-ggplot reliability data frame.
#'
#' The CRPS for a sample-based posterior `F` and a scalar truth `y`
#' is computed from the Monte-Carlo formula
#' \eqn{
#'   \mathrm{CRPS}(F, y) = \tfrac{1}{N}\sum_i |s_i - y|
#'                          - \tfrac{1}{2N^2}\sum_{i,j} |s_i - s_j|
#' }
#' (see Gneiting & Raftery 2007 for the derivation and its strictly
#' proper scoring rule interpretation). The per-query CRPS is
#' averaged across all query cells for a single reported scalar.
#'
#' @param post An `edaphos_posterior`.
#' @param truth Numeric array with the same shape as `post$mean`;
#'   the ground-truth values.
#' @param probs Nominal coverage probabilities at which to report
#'   PICP + MPIW, and for the reliability curve. Defaults to
#'   `seq(0.05, 0.95, by = 0.05)`.
#'
#' @return A list with:
#' \describe{
#'   \item{crps}{Mean sample-based CRPS across query cells.}
#'   \item{picp}{Named vector of empirical coverage, one per `probs`.}
#'   \item{mpiw}{Named vector of mean interval widths, one per `probs`.}
#'   \item{reliability_df}{Data frame with columns `nominal`,
#'     `empirical`, `diff` suitable for `ggplot2::geom_line`.}
#'   \item{point_rmse}{Root-mean-squared error of the posterior mean
#'     against the truth.}
#' }
#' @references
#' Gneiting, T. and Raftery, A. E. (2007). Strictly proper scoring
#' rules, prediction, and estimation. *Journal of the American
#' Statistical Association* **102**(477), 359-378.
#' @export
uncertainty_calibrate <- function(post, truth,
                                   probs = seq(0.05, 0.95, by = 0.05)) {
  stopifnot(inherits(post, "edaphos_posterior"))
  truth <- as.numeric(truth)
  mean_v <- as.numeric(post$mean)
  if (length(mean_v) != length(truth)) {
    stop(sprintf(
      "`truth` has length %d but posterior mean has length %d.",
      length(truth), length(mean_v)), call. = FALSE)
  }

  # Flatten samples to (n_samples, n_query).
  s <- post$samples
  if (!is.matrix(s)) s <- matrix(s, nrow = dim(s)[1L])
  n_samp  <- nrow(s); n_query <- ncol(s)
  stopifnot(n_query == length(truth))

  # -- CRPS via the Monte-Carlo formula, per query cell ---------------------
  crps_per <- vapply(seq_len(n_query), function(j) {
    z <- s[, j]
    term_a <- mean(abs(z - truth[j]))
    # 0.5 * E|Z - Z'| via an unbiased pairwise estimator that is
    # O(N log N) rather than O(N^2): it equals the Gini mean
    # difference of z, which for a sorted sample `zs` is
    # (2 / N^2) * sum_{i=1..N} (2 i - N - 1) * zs[i].
    zs <- sort(z)
    ii <- seq_len(n_samp)
    gmd <- sum((2 * ii - n_samp - 1) * zs) * 2 / (n_samp^2)
    term_a - 0.5 * gmd
  }, numeric(1L))

  # -- PICP and MPIW across the probs grid ---------------------------------
  picp_v <- numeric(length(probs))
  mpiw_v <- numeric(length(probs))
  for (k in seq_along(probs)) {
    p     <- probs[k]
    alpha <- 1 - p
    lo_q  <- apply(s, 2L, stats::quantile, probs = alpha / 2,
                    names = FALSE)
    hi_q  <- apply(s, 2L, stats::quantile, probs = 1 - alpha / 2,
                    names = FALSE)
    picp_v[k] <- mean(truth >= lo_q & truth <= hi_q)
    mpiw_v[k] <- mean(hi_q - lo_q)
  }
  names(picp_v) <- sprintf("%.02f", probs)
  names(mpiw_v) <- names(picp_v)

  # -- Point RMSE (sanity) --------------------------------------------------
  rmse <- sqrt(mean((mean_v - truth)^2))

  list(
    crps           = mean(crps_per),
    crps_per       = crps_per,
    picp           = picp_v,
    mpiw           = mpiw_v,
    reliability_df = data.frame(
      nominal   = probs,
      empirical = picp_v,
      diff      = picp_v - probs
    ),
    point_rmse     = rmse
  )
}

# ---------------------------------------------------------------------------
# Autoplot
# ---------------------------------------------------------------------------

#' Default ggplot for an `edaphos_posterior`
#'
#' Dispatches on the posterior's `query_type` to produce a suitable
#' figure. For `"effect"`, `"param"`, `"energy"` the plot is a
#' posterior-density histogram with a 95 % interval; for `"map"`
#' a three-panel mean / SD / 90 % interval-width facet; for
#' `"sample"` a quantile ribbon indexed by query position; for
#' `"feature"` a faceted density by feature; for `"other"` it falls
#' back to the `"sample"` layout.
#'
#' Requires the `ggplot2` package.
#'
#' @param object An `edaphos_posterior`.
#' @param ... Ignored (for S3 compatibility).
#' @return A `ggplot` object.
#' @exportS3Method ggplot2::autoplot edaphos_posterior
autoplot.edaphos_posterior <- function(object, ...) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Install ggplot2 to use autoplot.edaphos_posterior().",
         call. = FALSE)
  }
  ggplot2 <- asNamespace("ggplot2")
  qt <- object$query_type
  ylab <- if (!is.null(object$units)) object$units else "value"

  if (qt %in% c("effect", "param", "energy")) {
    flat <- as.numeric(object$samples)
    ci   <- stats::quantile(flat, probs = c(0.025, 0.975), names = FALSE)
    df <- data.frame(draw = flat)
    ggplot2$ggplot(df, ggplot2$aes(x = .data$draw)) +
      ggplot2$geom_histogram(bins = 40, fill = "#4A90E2", alpha = 0.7) +
      ggplot2$geom_vline(xintercept = ci, colour = "#D9534F",
                           linetype = "dashed") +
      ggplot2$geom_vline(xintercept = as.numeric(object$mean),
                           colour = "#2C3E50", linewidth = 1.0) +
      ggplot2$labs(x = ylab, y = "count",
                     title = sprintf("Posterior density  (method = %s)",
                                      object$method),
                     subtitle = sprintf("mean = %+.4f  95%%CI = [%+.4f, %+.4f]",
                                         as.numeric(object$mean), ci[1], ci[2])) +
      ggplot2$theme_minimal(base_size = 12)
  } else if (qt == "map") {
    # Expect 2-D mean / sd arrays.
    stopifnot(is.matrix(object$mean) || (is.array(object$mean) &&
                                            length(dim(object$mean)) == 2L))
    H <- dim(object$mean)[1L]; W <- dim(object$mean)[2L]
    df <- data.frame(
      row = rep(seq_len(H), times = W),
      col = rep(seq_len(W), each  = H),
      mean = as.vector(object$mean),
      sd   = as.vector(object$sd)
    )
    if (!is.null(object$quantiles$q05) && !is.null(object$quantiles$q95)) {
      df$width95 <- as.vector(object$quantiles$q95) -
                    as.vector(object$quantiles$q05)
    } else {
      df$width95 <- 3.29 * df$sd    # Gaussian fallback
    }
    long <- do.call(rbind, list(
      cbind(df[, c("row", "col")], panel = "mean",     value = df$mean),
      cbind(df[, c("row", "col")], panel = "sd",       value = df$sd),
      cbind(df[, c("row", "col")], panel = "width95",  value = df$width95)
    ))
    long$panel <- factor(long$panel, levels = c("mean", "sd", "width95"))
    ggplot2$ggplot(long, ggplot2$aes(x = .data$col, y = -.data$row,
                                        fill = .data$value)) +
      ggplot2$geom_raster() +
      ggplot2$facet_wrap(~ .data$panel, nrow = 1L, scales = "free") +
      ggplot2$scale_fill_viridis_c() +
      ggplot2$coord_equal() +
      ggplot2$theme_minimal(base_size = 12) +
      ggplot2$labs(x = NULL, y = NULL, fill = ylab,
                     title = sprintf("Posterior map  (method = %s)",
                                      object$method))
  } else {
    # "sample", "feature", "other" -- treat as a quantile ribbon vs
    # query position.
    mu <- as.numeric(object$mean)
    q_lo <- as.numeric(
      object$quantiles[[head(names(object$quantiles), 1L)]] %||% (mu - object$sd))
    q_hi <- as.numeric(
      object$quantiles[[tail(names(object$quantiles), 1L)]] %||% (mu + object$sd))
    df <- data.frame(i = seq_along(mu), mean = mu, lo = q_lo, hi = q_hi)
    ggplot2$ggplot(df, ggplot2$aes(x = .data$i, y = .data$mean)) +
      ggplot2$geom_ribbon(ggplot2$aes(ymin = .data$lo, ymax = .data$hi),
                            fill = "#4A90E2", alpha = 0.3) +
      ggplot2$geom_line(colour = "#2C3E50") +
      ggplot2$theme_minimal(base_size = 12) +
      ggplot2$labs(x = "query index", y = ylab,
                     title = sprintf("Posterior ribbon  (method = %s)",
                                      object$method))
  }
}

# ---------------------------------------------------------------------------
# Calibration autoplot
# ---------------------------------------------------------------------------

#' Reliability diagram from a calibration result
#'
#' Given the output of [`uncertainty_calibrate()`], draws a reliability
#' diagram (nominal vs empirical coverage) with the identity line.
#'
#' @param calib List returned by [`uncertainty_calibrate()`].
#' @param ... Ignored.
#' @return A `ggplot` object.
#' @export
uncertainty_plot_reliability <- function(calib, ...) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Install ggplot2 to use uncertainty_plot_reliability().",
         call. = FALSE)
  }
  ggplot2 <- asNamespace("ggplot2")
  stopifnot(is.list(calib), !is.null(calib$reliability_df))
  df <- calib$reliability_df
  ggplot2$ggplot(df, ggplot2$aes(x = .data$nominal, y = .data$empirical)) +
    ggplot2$geom_abline(slope = 1, intercept = 0, linetype = "dashed",
                          colour = "grey50") +
    ggplot2$geom_line(colour = "#4A90E2", linewidth = 0.8) +
    ggplot2$geom_point(colour = "#2C3E50", size = 1.8) +
    ggplot2$coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
    ggplot2$labs(x = "nominal coverage",
                   y = "empirical coverage",
                   title = sprintf(
                     "Reliability  (CRPS = %.4f, RMSE = %.4f)",
                     calib$crps, calib$point_rmse)) +
    ggplot2$theme_minimal(base_size = 12)
}

# ---------------------------------------------------------------------------
# Tiny local helper to avoid an Imports dependency on purrr
# ---------------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a)) b else a
