# Internal utilities shared across pillars.
# Not exported.

`%||%` <- function(a, b) if (is.null(a)) b else a

# Invert a matrix, falling back to a pseudo-inverse when it is singular.
#
# Five call sites in R/causal_iv.R and R/causal_active_learning.R each wrote
#   tryCatch(solve(M), error = function(e) MASS::ginv(M))
# with no check that MASS is available. MASS is in Suggests, which means a
# user may not have it: Suggests are not installed by default. It is also a
# "recommended" package, so it ships with virtually every R build and the
# calls work in practice -- which is why five copies of an unguarded call
# survived. R can be built --without-recommended-packages, and on such a
# machine a singular design produced "there is no package called 'MASS'"
# rather than anything a user could act on.
#
# This is the one place that reaches for it, and it says what to do.
.safe_inverse <- function(M, what = "matrix") {
  inv <- tryCatch(solve(M), error = function(e) NULL)
  if (!is.null(inv)) return(inv)
  if (!requireNamespace("MASS", quietly = TRUE))
    stop(sprintf(paste("the %s is singular and cannot be inverted; the",
                       "pseudo-inverse fallback needs the MASS package.",
                       "Install it with install.packages(\"MASS\"), or supply",
                       "a design of full rank."), what), call. = FALSE)
  MASS::ginv(M)
}

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

# ---------------------------------------------------------------------------
# Great-circle distance in kilometres.
#
# Used by the spatial blocking helper and by the Pillar-10 graph builder, which
# previously carried two near-identical copies of this formula -- each with its
# own optional `sp::spDists` branch. That conditional was a reproducibility
# wart: sp works on the WGS84 ellipsoid and this closed form on a sphere, so
# the same call returned answers differing by up to 0.56% depending on whether
# a Suggests-level package happened to be installed. At a 68 km buffer that is
# ~380 m, enough to move a profile across the buffer boundary. One formula,
# always, is worth more than the third decimal place.
#
# ACCURACY. Spherical (R = 6371.0087714 km, the WGS84 mean radius). Measured
# against sp::spDists on 400 Cerrado points: median relative error 0.14% and
# maximum 0.56% for pairs under 50 km, the range that governs both k-NN
# neighbour selection and the CV buffer. Neighbour ORDER is what the graph
# consumes, and a smooth 0.5% distortion essentially never reorders it.
#
# `a` and `b` are two-column matrices of (lon, lat) in degrees. Returns the
# nrow(a) x nrow(b) matrix of distances.
# ---------------------------------------------------------------------------
.gc_km <- function(a, b = a) {
  a <- as.matrix(a); b <- as.matrix(b)
  stopifnot(ncol(a) == 2L, ncol(b) == 2L)
  R <- 6371.0087714
  la1 <- a[, 2] * pi / 180; lo1 <- a[, 1] * pi / 180
  la2 <- b[, 2] * pi / 180; lo2 <- b[, 1] * pi / 180
  outer(seq_len(nrow(a)), seq_len(nrow(b)), function(i, j) {
    h <- sin((la2[j] - la1[i]) / 2)^2 +
      cos(la1[i]) * cos(la2[j]) * sin((lo2[j] - lo1[i]) / 2)^2
    2 * R * asin(pmin(1, sqrt(h)))
  })
}
