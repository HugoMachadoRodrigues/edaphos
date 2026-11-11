#' Map a fitted model over a covariate raster, with its uncertainty
#'
#' The step from a fitted model to a soil map. `edaphos_map()` takes a fitted
#' model and the covariates at the places to be mapped, predicts at every
#' place, and returns the prediction together with its uncertainty in the
#' same form it was given: a raster in, a raster out; points in, points out.
#'
#' @section Supported models:
#' Each model reports the uncertainty it actually has. Nothing is filled in.
#'
#' | Model | `sd` and quantiles come from |
#' |:------|:-----------------------------|
#' | [bhs_fit()] (Pillar 7) | exact conditional predictive draws, kriging variance included |
#' | [al_fit()] (Pillar 5) | the quantile regression forest's conditional quantiles |
#' | [stats::lm()] | the prediction interval (t distribution, residual variance included) |
#' | [ranger::ranger()] with `quantreg = TRUE` | its conditional quantiles |
#' | [stats::glm()] | nothing: only `mean`, on the response scale |
#' | anything else whose `predict(fit, newdata)` returns one number per row | nothing: only `mean` is returned |
#'
#' For a model in the last row the map has a `mean` layer only. A map without
#' an uncertainty layer is reported as such rather than given a made-up one.
#'
#' @section Coordinates:
#' A raster's cell centres are added to each row as columns named `coords`.
#' A model that uses location (Pillar 7) needs them under the names it was
#' trained with; `edaphos_map()` takes those names from the fit, so `coords`
#' only needs setting for a model that does not record them. The coordinates
#' must be in the same reference system the model was trained in.
#'
#' @param fit A fitted model; see *Supported models*.
#' @param covariates Where to predict. One of
#'   * a `terra::SpatRaster` whose layer names match the model's covariates,
#'   * an `sf` object of points, or
#'   * a data frame carrying the covariates (and the coordinates, for a model
#'     that uses them).
#' @param probs Quantile levels to report, each strictly between 0 and 1.
#' @param coords Names of the two coordinate columns (x, then y). Defaults
#'   to the names the fit recorded, else `c("x", "y")`.
#' @param n_draws Posterior draws per location, for [bhs_fit()] models.
#' @param chunk_size Locations predicted per batch. Lower it if memory runs
#'   short on a large raster.
#' @param ... Passed to the model's `predict()` method.
#'
#' @return The same kind of object as `covariates`:
#'   * a `SpatRaster` with layers `mean`, `sd` and one `q<level>` per
#'     probability (`q5`, `q50`, `q95` by default),
#'   * an `sf` object, or a data frame, with those columns appended.
#'
#'   Locations where any covariate is missing get `NA`. The attribute
#'   `"edaphos_map"` records the model class, where the uncertainty comes
#'   from, and how many locations were predicted.
#'
#' @examples
#' # A synthetic 45 x 45 covariate grid that ships with the package.
#' data(br_cerrado)
#' set.seed(1)
#' train <- br_cerrado[sample(nrow(br_cerrado), 60), ]
#' fit <- lm(soc ~ elev + slope + twi + map_mm + ndvi, data = train)
#'
#' # Data frame in, data frame out:
#' out <- edaphos_map(fit, br_cerrado)
#' head(out[, c("x", "y", "mean", "sd", "q5", "q95")])
#'
#' # Raster in, raster out:
#' if (requireNamespace("terra", quietly = TRUE)) {
#'   r <- terra::rast(br_cerrado[, c("x", "y", "elev", "slope", "twi",
#'                                   "map_mm", "ndvi")], type = "xyz",
#'                    crs = "EPSG:4326")
#'   m <- edaphos_map(fit, r)
#'   m
#'   terra::plot(m[[c("mean", "sd")]])
#' }
#' @export
edaphos_map <- function(fit, covariates, probs = c(0.05, 0.5, 0.95),
                        coords = NULL, n_draws = 500L, chunk_size = 50000L,
                        ...) {
  if (missing(fit) || is.null(fit))
    stop("`fit` is required: a fitted model to map.", call. = FALSE)
  stopifnot(is.numeric(probs), length(probs) >= 1L,
            all(is.finite(probs)), all(probs > 0 & probs < 1))
  probs <- sort(unique(probs))
  chunk_size <- as.integer(chunk_size)
  stopifnot(length(chunk_size) == 1L, chunk_size >= 1L)
  coords <- coords %||% .map_fit_coords(fit) %||% c("x", "y")
  stopifnot(is.character(coords), length(coords) == 2L)

  kind <- if (inherits(covariates, "SpatRaster")) "raster" else
    if (inherits(covariates, "sf")) "sf" else
      if (is.data.frame(covariates)) "data.frame" else
        stop("`covariates` must be a terra SpatRaster, an sf object or a ",
             "data frame, not an object of class '", class(covariates)[1L],
             "'.", call. = FALSE)

  # -- to a data frame of locations ------------------------------------------
  if (kind == "raster") {
    if (!requireNamespace("terra", quietly = TRUE))
      stop("Install `terra` to map over a raster.", call. = FALSE)
    df <- as.data.frame(covariates, xy = TRUE, cells = TRUE, na.rm = FALSE)
    cells <- df$cell
    df$cell <- NULL
    names(df)[1:2] <- coords
  } else if (kind == "sf") {
    if (!requireNamespace("sf", quietly = TRUE))
      stop("Install `sf` to map at sf points.", call. = FALSE)
    geom_type <- unique(as.character(sf::st_geometry_type(covariates)))
    if (!all(geom_type == "POINT"))
      stop("`covariates` as sf must hold POINT geometries; got ",
           paste(geom_type, collapse = ", "), ".", call. = FALSE)
    xy <- sf::st_coordinates(covariates)
    df <- sf::st_drop_geometry(covariates)
    df[[coords[1]]] <- xy[, 1]
    df[[coords[2]]] <- xy[, 2]
  } else {
    df <- covariates
  }
  df <- as.data.frame(df)

  needed <- .map_needed_columns(fit, coords)
  missing_cols <- setdiff(needed, names(df))
  if (length(missing_cols))
    stop("`covariates` lacks column(s) the model needs: ",
         paste(missing_cols, collapse = ", "),
         if (kind == "raster") " (raster layer names must match)." else ".",
         call. = FALSE)
  ok <- if (length(needed))
    stats::complete.cases(df[, needed, drop = FALSE]) else
      rep(TRUE, nrow(df))

  # -- predict, in chunks ----------------------------------------------------
  qnames <- paste0("q", signif(probs * 100, 4))
  out <- matrix(NA_real_, nrow(df), 2L + length(probs),
                dimnames = list(NULL, c("mean", "sd", qnames)))
  idx <- which(ok)
  source <- NA_character_
  for (start in seq(1L, length(idx), by = chunk_size)) {
    if (!length(idx)) break
    rows <- idx[start:min(start + chunk_size - 1L, length(idx))]
    p <- .map_predict(fit, df[rows, , drop = FALSE], probs = probs,
                      n_draws = n_draws, ...)
    if (nrow(p$values) != length(rows))
      stop("the model returned ", nrow(p$values), " predictions for ",
           length(rows), " locations.", call. = FALSE)
    out[rows, ] <- p$values
    source <- p$source
  }
  if (is.na(source)) source <- .map_predict_source(fit)
  has_unc <- !identical(source, "none")
  keep <- if (has_unc) colnames(out) else "mean"
  out <- out[, keep, drop = FALSE]

  info <- list(model = class(fit)[1L], uncertainty = source,
               probs = if (has_unc) probs else numeric(0),
               n_locations = nrow(df), n_predicted = length(idx))

  # -- back to the input's form ----------------------------------------------
  res <- switch(kind,
    raster = {
      tmpl <- terra::rast(covariates, nlyrs = ncol(out))
      vals <- matrix(NA_real_, terra::ncell(tmpl), ncol(out))
      vals[cells, ] <- out
      terra::values(tmpl) <- vals
      names(tmpl) <- colnames(out)
      tmpl
    },
    sf = {
      for (j in colnames(out)) covariates[[j]] <- out[, j]
      covariates
    },
    data.frame = {
      for (j in colnames(out)) covariates[[j]] <- out[, j]
      covariates
    })
  attr(res, "edaphos_map") <- info
  res
}

# Coordinate names recorded by a fit, when it records any.
.map_fit_coords <- function(fit) {
  if (inherits(fit, "edaphos_bhs")) return(colnames(fit$coords))
  if (inherits(fit, "edaphos_al_model") && length(fit$coords) == 2L)
    return(fit$coords)
  NULL
}

# Columns a location must carry for the fit to predict there.
.map_needed_columns <- function(fit, coords) {
  if (inherits(fit, "edaphos_bhs"))
    return(unique(c(all.vars(stats::delete.response(stats::terms(fit$formula))),
                    colnames(fit$coords))))
  if (inherits(fit, "edaphos_al_model")) return(fit$covariates)
  if (inherits(fit, "ranger")) return(fit$forest$independent.variable.names)
  tt <- tryCatch(stats::delete.response(stats::terms(fit)),
                 error = function(e) NULL)
  if (!is.null(tt)) return(all.vars(tt))
  character(0)
}

.map_predict_source <- function(fit) {
  if (inherits(fit, "edaphos_bhs")) return("posterior predictive draws")
  if (inherits(fit, "edaphos_al_model"))
    return("quantile regression forest")
  if (inherits(fit, "lm") && !inherits(fit, "glm"))
    return("lm prediction interval")
  if (inherits(fit, "ranger") && isTRUE(fit$quantreg))
    return("quantile regression forest")
  "none"
}

# One batch of locations -> list(values = matrix(mean, sd, q...), source).
.map_predict <- function(fit, nd, probs, n_draws, ...) {
  src <- .map_predict_source(fit)
  n <- nrow(nd)
  vals <- matrix(NA_real_, n, 2L + length(probs))

  summarise_draws <- function(S) {          # S: draws x locations
    cbind(colMeans(S), apply(S, 2L, stats::sd),
          t(apply(S, 2L, stats::quantile, probs = probs, names = FALSE)))
  }

  if (inherits(fit, "edaphos_bhs")) {
    p <- stats::predict(fit, nd, quantiles = probs, n_draws = n_draws,
                        draws = TRUE, ...)
    vals <- summarise_draws(attr(p, "draws"))
  } else if (inherits(fit, "edaphos_al_model")) {
    post <- active_learning_posterior(fit, newdata = nd)
    vals <- summarise_draws(post$samples)
  } else if (inherits(fit, "ranger")) {
    if (isTRUE(fit$quantreg)) {
      grid <- seq(0.01, 0.99, by = 0.01)
      Q <- stats::predict(fit, data = nd, type = "quantiles",
                          quantiles = grid, ...)$predictions
      vals[, 1] <- stats::predict(fit, data = nd, ...)$predictions
      vals[, 2] <- apply(Q, 1L, stats::sd)
      vals[, -(1:2)] <- stats::predict(fit, data = nd, type = "quantiles",
                                       quantiles = probs,
                                       ...)$predictions
    } else {
      vals[, 1] <- stats::predict(fit, data = nd, ...)$predictions
    }
  } else if (identical(src, "lm prediction interval")) {
    pr <- stats::predict(fit, newdata = nd, se.fit = TRUE, ...)
    sd_pred <- sqrt(pr$se.fit^2 + pr$residual.scale^2)
    vals[, 1] <- pr$fit
    vals[, 2] <- sd_pred
    for (k in seq_along(probs))
      vals[, 2L + k] <- pr$fit + stats::qt(probs[k], pr$df) * sd_pred
  } else if (inherits(fit, "glm")) {
    # the response scale, not the link scale predict.glm() defaults to
    vals[, 1] <- stats::predict(fit, newdata = nd, type = "response", ...)
  } else {
    pr <- tryCatch(stats::predict(fit, newdata = nd, ...),
                   error = function(e) e)
    if (inherits(pr, "error") || !is.numeric(pr) || length(pr) != n)
      stop("edaphos_map() does not know how to map a model of class '",
           class(fit)[1L], "': its predict(fit, newdata) did not return ",
           "one number per location", if (inherits(pr, "error"))
             paste0(" (", conditionMessage(pr), ")"), ".", call. = FALSE)
    vals[, 1] <- as.numeric(pr)
  }
  list(values = vals, source = src)
}
