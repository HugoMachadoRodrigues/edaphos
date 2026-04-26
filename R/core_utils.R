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

# v3.8.0 -- friendly-error helper.
#
# Wraps `stop()` with the calling function's name and a "Hint:" line
# so a typical user-facing failure becomes self-diagnosing instead of
# a cryptic R traceback.  Use sparingly at user-facing entry points.
#
# Example:
#   .stopf("`data` must be a data frame, got %s.",
#          class(data)[1L],
#          hint = "Convert with `as.data.frame(data)`.")
.stopf <- function(msg, ..., hint = NULL, call = sys.call(-1L)) {
  fn <- if (is.null(call)) "edaphos" else as.character(call[[1L]])
  body <- if (length(list(...)) > 0L) sprintf(msg, ...) else msg
  full <- sprintf("[%s] %s", fn, body)
  if (!is.null(hint)) full <- paste0(full, "\n  Hint: ", hint)
  stop(full, call. = FALSE)
}

# Friendly type assertion.  If `cond` is FALSE, fails with
#   [<caller>] <name> must be <expected>, got <actual>.
.assert_type <- function(cond, name, expected, actual,
                            hint = NULL, call = sys.call(-1L)) {
  if (isTRUE(cond)) return(invisible(TRUE))
  .stopf("`%s` must be %s, got %s.", name, expected, actual,
          hint = hint, call = call)
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
