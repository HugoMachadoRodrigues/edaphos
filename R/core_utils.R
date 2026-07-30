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

# ---------------------------------------------------------------------------
# Backend resolution for the deep-learning pillars (P8/P9/P10).
#
# `backend = "auto"` (the default) resolves to "torch" when a working libtorch
# is present and to "r" otherwise.  This keeps torch the real, preferred backend
# while staying safe on machines without libtorch (CRAN's check machine, most
# CI): the call falls back to the pure-R reference implementation instead of
# erroring.  `backend = "torch"` is explicit and errors if libtorch is absent;
# `backend = "r"` forces the reference path.
#
# When the R path is used AND it is only a reference implementation (frozen
# random features, uncalibrated sampler), `r_note` explains that once per
# session so a user does not mistake a scaffold for the trained model.  The
# note is a message(), not a warning(), so it never trips R CMD check.
.edaphos_noted <- new.env(parent = emptyenv())

.note_reference_backend <- function(fn, msg) {
  if (is.null(.edaphos_noted[[fn]])) {
    assign(fn, TRUE, envir = .edaphos_noted)
    message(sprintf("[%s] %s", fn, msg))
  }
  invisible(NULL)
}

.torch_usable <- function() {
  isTRUE(tryCatch(torch::torch_is_installed(), error = function(e) FALSE))
}

.resolve_backend <- function(backend = c("auto", "r", "torch"),
                             fn = "model", r_note = NULL) {
  backend <- match.arg(backend)
  ok <- .torch_usable()
  if (backend == "torch" && !ok)
    stop(sprintf(paste0("[%s] backend = 'torch' needs the 'torch' package with a ",
                        "working libtorch. Install it with torch::install_torch(), ",
                        "or use backend = 'auto' (falls back to R) or 'r'."), fn),
         call. = FALSE)
  if (backend == "auto") backend <- if (ok) "torch" else "r"
  if (backend == "r" && !is.null(r_note)) .note_reference_backend(fn, r_note)
  backend
}
