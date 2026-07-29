# Pillar 3 x Pillar 5 bridge -- Temporal Active Learning with EnKF
# feedback.
#
# The v1.5.0 stochastic Ensemble Kalman Filter of Pillar 3 produces
# a per-cell *Kalman gain* on every assimilation step -- a map of
# which pixels responded most to the most recent in-situ observation.
# Those cells are, by definition, the ones where the forecast
# ensemble is most *informative to* new data: sampling there next
# maximises the ensemble spread shrinkage per dollar.
#
# `al_query_temporal()` wraps the existing `temporal_kalman_update()`
# output and turns the row-wise gain norm into an AL priority score
# for Pillar 5's candidate selection.

#' Temporal Active Learning: rank candidate cells by their Kalman
#' gain norm after the latest EnKF assimilation
#'
#' Closes the loop between Pillar 3 (4D ConvLSTM + stochastic EnKF
#' assimilation) and Pillar 5 (autonomous active learning).  The
#' Kalman-gain norm is a forward-looking estimate of how much the
#' posterior ensemble would shrink if a new observation were placed
#' at each spatial cell; candidates with high gain are the natural
#' next sampling locations.
#'
#' @param kalman_update A `edaphos_temporal_kalman` object whose
#'   `gain_row_norm` and `analysis_sd` slots are both `H x W` matrices
#'   of per-cell values.  `analysis_sd` already is one, but note that
#'   [`temporal_kalman_update()`] fills `gain_row_norm` with one number
#'   per *observation* (the column norms of the Kalman gain), so a
#'   result taken straight from it is rejected: write a per-cell
#'   informativeness map into that slot first.  See the examples.
#' @param candidate_coords Optional data frame with integer `row` and
#'   `col` grid indices (not lon / lat) that restrict scoring to a
#'   finite set of physically accessible cells.  When `NULL`, every
#'   cell of the analysis grid is a candidate.
#' @param n_select Integer; how many candidates to return.  More than
#'   the number of candidates simply returns them all.
#' @param combine One of `"gain"` (rank by pure gain norm, the v1.5.0
#'   default), `"gain_sd"` (weighted product of gain and remaining
#'   analysis SD), or `"gain_sd_normalised"` (same but each term is
#'   min-max rescaled first -- over the *candidate* set, so restricting
#'   `candidate_coords` reorders this ranking instead of only
#'   filtering it).
#' @return Data frame sorted by descending priority with columns
#'   `row`, `col`, `gain`, `analysis_sd`, `priority`.
#' @examples
#' # Pillar 3 -> Pillar 5. A 30-member forecast of month-12 SOC over a
#' # 12 x 12 Cerrado grid, biased 2 g/kg low, plus an EnKF assimilation
#' # of three fresh profiles. No torch needed for any of this.
#' cube  <- temporal_synth_soc_cube(H = 12L, W = 12L, T_total = 12L,
#'                                  seed = 42L)
#' soc12 <- cube$soc[12L, , ]
#' set.seed(2024L)
#' fc <- array(rep(as.numeric(soc12) - 2, each = 30L),
#'             dim = c(30L, 12L, 12L)) +
#'       array(stats::rnorm(30L * 144L, 0, 1.5), dim = c(30L, 12L, 12L))
#' obs_row <- c(3L, 9L, 6L)
#' obs_col <- c(3L, 9L, 11L)
#' ku <- temporal_kalman_update(fc,
#'                              obs_value = soc12[cbind(obs_row, obs_col)],
#'                              obs_row = obs_row, obs_col = obs_col,
#'                              obs_sd = 0.5, localization_radius = 3,
#'                              seed = 9L)
#'
#' # Trap first: ku$gain_row_norm holds one number per OBSERVATION, not
#' # the H x W per-cell map this function ranks, so the raw EnKF result
#' # is refused.
#' c(is_matrix = is.matrix(ku$gain_row_norm),
#'   length    = length(ku$gain_row_norm))
#' tryCatch(al_query_temporal(ku), error = function(e) conditionMessage(e))
#'
#' # Supply a per-cell informativeness map instead. The realised spread
#' # shrinkage (forecast sd - analysis sd) is the one you can build
#' # from what the EnKF actually returns; with localization_radius = 3
#' # it is 1.099 at the sampled cells and ~0 (median 0.002) elsewhere.
#' ku$gain_row_norm <- apply(fc, c(2, 3), stats::sd) - ku$analysis_sd
#' round(c(at_observed = mean(ku$gain_row_norm[cbind(obs_row, obs_col)]),
#'         grid_median = stats::median(ku$gain_row_norm),
#'         far_corner  = ku$gain_row_norm[1L, 1L]), 4)
#'
#' # combine = "gain" then hands back the three cells you have ALREADY
#' # sampled as the top three. Gain is highest where an observation
#' # sits, so ranking on it alone re-visits your own boreholes.
#' al_query_temporal(ku, n_select = 5L, combine = "gain")
#'
#' # Multiplying by the remaining analysis SD is what stops that: those
#' # cells are now the best-constrained on the grid (sd 0.443 against a
#' # grid median of 1.440), so the product demotes all three out of the
#' # top 5. Read the two columns together, never `gain` alone.
#' round(c(sd_at_observed = mean(ku$analysis_sd[cbind(obs_row, obs_col)]),
#'         sd_grid_median = stats::median(ku$analysis_sd)), 3)
#' as.data.frame(al_query_temporal(ku, n_select = 5L,
#'                                 combine = "gain_sd_normalised"))
#'
#' # candidate_coords takes row / col grid indices -- not lon / lat --
#' # and is where already-sampled cells get dropped. Even then pure
#' # gain picks (7, 11), one cell away from the (6, 11) profile:
#' # spatial redundancy is the SD factor's other job.
#' grid <- expand.grid(row = 1:12, col = 1:12)
#' cand <- grid[!(paste(grid$row, grid$col) %in%
#'                paste(obs_row, obs_col)), ]
#' as.data.frame(al_query_temporal(ku, cand, n_select = 3L,
#'                                 combine = "gain"))
#'
#' # "gain_sd_normalised" rescales within the candidate set, so these
#' # two rankings over the identical 141 cells disagree on the order.
#' a <- al_query_temporal(ku, cand, n_select = 141L,
#'                        combine = "gain_sd_normalised")
#' b <- al_query_temporal(ku, cand, n_select = 141L, combine = "gain_sd")
#' rbind(normalised  = head(paste(a$row, a$col), 4L),
#'       raw_product = head(paste(b$row, b$col), 4L))
#'
#' # Finally, what the assimilation this ranks was worth. Three
#' # profiles on 144 cells sharpen the analysis only where they sit:
#' # RMSE improves by 0.02 g/kg while 90% coverage (0.694 -> 0.667) and
#' # the interval score (6.24 -> 6.36) both get slightly worse, because
#' # the 2 g/kg prior bias survives wherever the taper is zero. That is
#' # the argument for spending the next sample well.
#' truth <- as.numeric(soc12)
#' pk    <- as_edaphos_posterior(ku, units = "g/kg")
#' plo   <- as.numeric(apply(fc, c(2, 3), stats::quantile, 0.05))
#' phi   <- as.numeric(apply(fc, c(2, 3), stats::quantile, 0.95))
#' round(rbind(
#'   prior = c(
#'     rmse   = edaphos_rmse(truth, as.numeric(apply(fc, c(2, 3), mean))),
#'     picp90 = edaphos_picp(truth, plo, phi),
#'     IS     = edaphos_interval_score(truth, plo, phi, alpha = 0.10)),
#'   analysis = c(
#'     rmse   = edaphos_rmse(truth, as.numeric(ku$analysis_mean)),
#'     picp90 = edaphos_picp(truth, as.numeric(pk$quantiles$q05),
#'                                  as.numeric(pk$quantiles$q95)),
#'     IS     = edaphos_interval_score(truth,
#'                                     as.numeric(pk$quantiles$q05),
#'                                     as.numeric(pk$quantiles$q95),
#'                                     alpha = 0.10))), 3)
#' @export
al_query_temporal <- function(kalman_update,
                                candidate_coords = NULL,
                                n_select = 10L,
                                combine = c("gain", "gain_sd",
                                              "gain_sd_normalised")) {
  combine <- match.arg(combine)
  stopifnot(inherits(kalman_update, "edaphos_temporal_kalman"))
  gain_m  <- kalman_update$gain_row_norm
  sd_m    <- kalman_update$analysis_sd
  if (!is.matrix(gain_m) || !is.matrix(sd_m) ||
      !identical(dim(gain_m), dim(sd_m))) {
    stop("`gain_row_norm` and `analysis_sd` must both be H x W ",
          "matrices of per-cell values. temporal_kalman_update() ",
          "returns `gain_row_norm` as one value per observation (the ",
          "column norms of the Kalman gain), so write a per-cell ",
          "informativeness map into that slot before calling.",
          call. = FALSE)
  }

  # Grid -> long frame
  H <- nrow(gain_m); W <- ncol(gain_m)
  grid <- expand.grid(row = seq_len(H), col = seq_len(W))
  grid$gain        <- as.numeric(gain_m)
  grid$analysis_sd <- as.numeric(sd_m)

  # Optional spatial restriction
  if (!is.null(candidate_coords)) {
    if (!all(c("row", "col") %in% names(candidate_coords))) {
      stop("`candidate_coords` must contain columns `row` and `col`.",
            call. = FALSE)
    }
    key      <- paste(grid$row, grid$col)
    key_cand <- paste(candidate_coords$row, candidate_coords$col)
    grid     <- grid[key %in% key_cand, , drop = FALSE]
  }

  grid$priority <- switch(
    combine,
    gain               = grid$gain,
    gain_sd            = grid$gain * grid$analysis_sd,
    gain_sd_normalised = .scale01(grid$gain) * .scale01(grid$analysis_sd)
  )
  grid <- grid[order(-grid$priority), ]
  out  <- utils::head(grid, n_select)
  structure(out,
             class      = c("edaphos_temporal_al_query", "data.frame"),
             combine    = combine,
             n_select   = n_select,
             grid_dims  = c(H, W))
}

.scale01 <- function(x) {
  r <- range(x, na.rm = TRUE)
  if (diff(r) < 1e-12) rep(0, length(x)) else (x - r[1]) / diff(r)
}

#' @export
print.edaphos_temporal_al_query <- function(x, ...) {
  cat("<edaphos_temporal_al_query>  (Pilar 3 x Pilar 5 bridge)\n")
  cat(sprintf("  grid dims : %d x %d\n",
               attr(x, "grid_dims")[1L], attr(x, "grid_dims")[2L]))
  cat(sprintf("  combine   : %s\n", attr(x, "combine")))
  cat(sprintf("  n_select  : %d\n", attr(x, "n_select")))
  cat(sprintf("  top-%d cells (sorted by priority):\n",
               min(attr(x, "n_select"), nrow(x))))
  print(as.data.frame(utils::head(x, 10)))
  invisible(x)
}
