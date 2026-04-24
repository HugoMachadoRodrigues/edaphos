# Pillar 3 x Pillar 5 bridge -- Temporal Active Learning with EnKF
# feedback (v2.1.2).
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
#' @param kalman_update A `edaphos_temporal_kalman` object returned
#'   by [`temporal_kalman_update()`].  Must carry the `gain_row_norm`
#'   and `analysis_sd` fields (they are produced by default).
#' @param candidate_coords Optional data frame with `lon`, `lat`
#'   columns that restrict scoring to a finite set of physically
#'   accessible cells.  When `NULL`, every cell of the analysis grid
#'   is a candidate.
#' @param n_select Integer; how many candidates to return.
#' @param combine One of `"gain"` (rank by pure gain norm, the v1.5.0
#'   default), `"gain_sd"` (weighted product of gain and remaining
#'   analysis SD), or `"gain_sd_normalised"` (same but each term is
#'   percentile-normalised first).
#' @return Data frame sorted by descending priority with columns
#'   `row`, `col`, `gain`, `analysis_sd`, `priority`.
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
  stopifnot(is.matrix(gain_m), is.matrix(sd_m),
             identical(dim(gain_m), dim(sd_m)))

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
