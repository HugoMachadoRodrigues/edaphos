# ---------------------------------------------------------------------------
# Spatially blocked cross-validation folds, with a buffer.
#
# Every blocked fold in this package used to be an inline k-means on longitude
# and latitude whose training set was the exact complement of the test block.
# That is blocking without a dead zone: a training profile can sit immediately
# across the block boundary from a test profile, and if the property is
# spatially autocorrelated at that separation, the "held-out" test row is
# partly memorised rather than predicted.
#
# It is not a hypothetical here. Measured on the 3,077 profile coordinates this
# package benchmarks on, the minimum training-to-test great-circle distance was
# 12.3 km, while the shortest identified variogram range among the fitted
# depth-function parameters is 55 km (data-raw/piml_parameter_variograms.R).
# The nearest training neighbour is therefore well inside the range at which
# the field is correlated, so the unbuffered estimate of predictive skill is
# optimistic by an unknown amount. At a 68 km buffer the exclusion costs 88 of
# those 3,077 rows and lifts the realised minimum to 68.3 km.
#
# Roberts et al. (2017, Ecography 40:913-929) is the standard reference for
# why blocking without a buffer under-states generalisation error.
#
# This helper does three things the inline code did not: it computes distances
# on the sphere rather than in degrees, it removes training rows inside the
# buffer, and it RETURNS how many it removed, so the exclusion appears in the
# record instead of happening silently.
# ---------------------------------------------------------------------------

#' Spatially blocked cross-validation folds with a buffer
#'
#' Assigns rows to `k` spatial blocks by k-means on the coordinates, then, for
#' each fold, drops training rows that lie within `buffer_km` great-circle
#' distance of any test row.
#'
#' @param coords Two-column numeric matrix or data frame of longitude and
#'   latitude, in that order, in degrees.
#' @param k Number of folds.
#' @param buffer_km Width of the dead zone in kilometres. Training rows closer
#'   than this to any test row are excluded from that fold. The default, 68 km,
#'   is the largest identified variogram range among the depth-function
#'   parameters fitted to the profiles shipped with this package; see
#'   `inst/extdata/piml_parameter_variograms.rds`. Set `0` to reproduce the
#'   unbuffered behaviour, which is what earlier versions did implicitly.
#' @param seed Optional integer seed for the k-means start.
#'
#' @return An `edaphos_spatial_folds` object: a list with `fold` (an integer
#'   vector of block assignments), `train` and `test` (lists of row-index
#'   vectors, one per fold), `n_buffered` (rows removed per fold),
#'   `min_dist_km` (the realised minimum training-to-test distance per fold,
#'   which should be at least `buffer_km`), and the settings.
#'
#' @references
#' Roberts DR, Bahn V, Ciuti S, et al. (2017). Cross-validation strategies for
#' data with temporal, spatial, hierarchical, or phylogenetic structure.
#' *Ecography* 40:913-929. \doi{10.1111/ecog.02881}
#'
#' @export
#' @examples
#' data(br_cerrado)
#' xy <- br_cerrado[seq(1, nrow(br_cerrado), by = 20), c("x", "y")]
#'
#' # Scale the buffer to the data. `br_cerrado` is a 0.3-degree demonstration
#' # grid whose widest separation is about 47 km, so the 68 km default -- set
#' # for the Cerrado-wide WoSIS extract -- would empty a fold, and the function
#' # says so rather than returning one silently.
#' try(spatial_block_folds(xy, k = 5, buffer_km = 68, seed = 1))
#'
#' # Without a buffer, the nearest training neighbour of a test row can be
#' # arbitrarily close to it.
#' f0 <- spatial_block_folds(xy, k = 5, buffer_km = 0, seed = 1)
#' round(min(f0$min_dist_km), 2)
#'
#' # With one, no training row is closer than the buffer, and the cost in
#' # discarded training data is reported rather than hidden.
#' f1 <- spatial_block_folds(xy, k = 5, buffer_km = 10, seed = 1)
#' round(min(f1$min_dist_km), 2)
#' f1$n_buffered
#' f1
spatial_block_folds <- function(coords, k = 5L, buffer_km = 68, seed = NULL) {
  coords <- as.matrix(coords[, 1:2, drop = FALSE])
  storage.mode(coords) <- "double"
  stopifnot(nrow(coords) >= k, all(is.finite(coords)),
            is.numeric(buffer_km), length(buffer_km) == 1L, buffer_km >= 0)
  k <- as.integer(k)

  if (!is.null(seed)) set.seed(seed)
  fold <- stats::kmeans(coords, centers = k, nstart = 10L)$cluster

  # Great-circle distance in km. sp::spDists does this; fall back to an inline
  # haversine so the helper does not hard-depend on sp for a 5-line formula.
  gc_dist <- function(a, b) {
    if (requireNamespace("sp", quietly = TRUE)) {
      return(sp::spDists(a, b, longlat = TRUE))
    }
    R <- 6371.0087714
    la1 <- a[, 2] * pi / 180; lo1 <- a[, 1] * pi / 180
    la2 <- b[, 2] * pi / 180; lo2 <- b[, 1] * pi / 180
    outer(seq_len(nrow(a)), seq_len(nrow(b)), function(i, j) {
      dla <- la2[j] - la1[i]; dlo <- lo2[j] - lo1[i]
      h <- sin(dla / 2)^2 + cos(la1[i]) * cos(la2[j]) * sin(dlo / 2)^2
      2 * R * asin(pmin(1, sqrt(h)))
    })
  }

  train <- test <- vector("list", k)
  n_buf <- min_d <- numeric(k)
  for (i in seq_len(k)) {
    te <- which(fold == i)
    tr_all <- which(fold != i)
    d <- gc_dist(coords[tr_all, , drop = FALSE], coords[te, , drop = FALSE])
    nearest <- apply(d, 1L, min)
    keep <- nearest >= buffer_km
    train[[i]] <- tr_all[keep]
    test[[i]]  <- te
    n_buf[i]   <- sum(!keep)
    min_d[i]   <- if (any(keep)) min(nearest[keep]) else NA_real_
  }
  if (any(vapply(train, length, 0L) < 2L)) {
    stop("buffer_km = ", buffer_km, " leaves fewer than two training rows in ",
         "at least one fold. Reduce the buffer or the number of folds.",
         call. = FALSE)
  }

  structure(list(fold = fold, train = train, test = test,
                 n_buffered = n_buf, min_dist_km = min_d,
                 k = k, buffer_km = buffer_km, n = nrow(coords)),
            class = "edaphos_spatial_folds")
}

#' @export
print.edaphos_spatial_folds <- function(x, ...) {
  cat("<edaphos_spatial_folds>\n")
  cat(sprintf("  %d rows, %d blocks, buffer %.0f km\n", x$n, x$k, x$buffer_km))
  cat(sprintf("  test rows per fold : %s\n",
              paste(vapply(x$test, length, 0L), collapse = ", ")))
  cat(sprintf("  training rows kept : %s\n",
              paste(vapply(x$train, length, 0L), collapse = ", ")))
  cat(sprintf("  discarded to buffer: %s (%.1f%% of all rows)\n",
              paste(x$n_buffered, collapse = ", "),
              100 * sum(x$n_buffered) / (x$n * x$k)))
  cat(sprintf("  realised min train-test distance: %.1f km\n",
              min(x$min_dist_km, na.rm = TRUE)))
  if (x$buffer_km == 0) {
    cat("  NOTE: buffer_km = 0 reproduces unbuffered blocking, which\n",
        "        under-states generalisation error when the property is\n",
        "        autocorrelated at the realised distance above.\n", sep = "")
  }
  invisible(x)
}
