# Internal utilities shared across pillars.
# Not exported.

`%||%` <- function(a, b) if (is.null(a)) b else a

.assert_covariates <- function(data, covariates) {
  missing <- setdiff(covariates, names(data))
  if (length(missing) > 0L) {
    stop("Covariates not found in data: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

.assert_coords <- function(data, coords) {
  if (is.null(coords)) return(invisible(TRUE))
  if (length(coords) != 2L) {
    stop("`coords` must be a length-2 character vector naming the x/y ",
         "columns.", call. = FALSE)
  }
  missing <- setdiff(coords, names(data))
  if (length(missing) > 0L) {
    stop("Coordinate columns not found in data: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

.rmse <- function(obs, pred) {
  sqrt(mean((obs - pred)^2, na.rm = TRUE))
}

.norm01 <- function(v) {
  v <- as.numeric(v)
  r <- suppressWarnings(diff(range(v, na.rm = TRUE)))
  if (!is.finite(r) || r <= 0) return(rep(1, length(v)))
  (v - min(v, na.rm = TRUE)) / r
}
