# Pillar 4 -- planetary-scale tile IO and streaming dataset.
#
# This module bridges the MoCo v2 pretraining loop in foundation_moco.R
# to real multi-source raster mosaics. The target scenario is a user
# who wants to pretrain on:
#
#   * SoilGrids 250 m (clay, SOC, pH, CEC, ...)
#   * WorldClim 2.1 (mean annual precipitation, temperature, aridity, ...)
#   * SRTM elevation (+ derived slope, aspect, TWI)
#   * MODIS MOD13Q1 (NDVI, EVI -- optional, needs NASA EarthData)
#   * ERA5-Land (radiation, wind, ET -- optional, needs Copernicus CDS)
#
# ... fused into a common grid, sampled as (C, H, W) patches, and fed
# to the momentum-contrast training loop without loading the whole
# mosaic into RAM.
#
# All heavy dependencies (`terra`, `geodata`, `sf`, `ecmwfr`) are
# Suggests. Every public function fails gracefully with a clear
# install / authentication hint when they are not available.

.tiles_require_terra <- function() {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Install the `terra` package for tile IO: ",
         "install.packages(\"terra\").", call. = FALSE)
  }
  invisible(TRUE)
}

# ---- Public tile sources ----------------------------------------------------

#' Fetch a SoilGrids 250 m stack over an AoI
#'
#' Thin convenience wrapper around `geodata::soil_world()` that pulls
#' the listed variables, crops them to the area of interest, and
#' returns them as a single `terra::SpatRaster` with one layer per
#' variable. SoilGrids is **public and keyless** so no authentication
#' is required.
#'
#' @param variables Character vector of SoilGrids variable codes.
#'   Common choices: `"soc"` (organic carbon), `"clay"`, `"sand"`,
#'   `"phh2o"` (pH in water), `"cec"`, `"bdod"` (bulk density),
#'   `"nitrogen"`, `"cfvo"` (coarse fragments).
#' @param depth Character, one of `"0-5cm"`, `"5-15cm"`, `"15-30cm"`,
#'   `"30-60cm"`, `"60-100cm"`, `"100-200cm"`.
#' @param stat Character, one of `"mean"`, `"Q0.05"`, `"Q0.5"`,
#'   `"Q0.95"`.
#' @param aoi A `terra::SpatExtent`, `sf` bounding box, or a length-4
#'   numeric vector `c(xmin, xmax, ymin, ymax)` in WGS84 degrees.
#' @param path Directory where `geodata` caches raw downloads
#'   (defaults to `tempdir()`).
#'
#' @return A `terra::SpatRaster` with one layer per requested variable,
#'   cropped to the AoI.
#' @export
foundation_tile_source_soilgrids <- function(variables = c("soc", "clay"),
                                               depth = "0-5cm",
                                               stat  = "mean",
                                               aoi,
                                               path  = tempdir()) {
  .tiles_require_terra()
  if (!requireNamespace("geodata", quietly = TRUE)) {
    stop("Install `geodata` to fetch SoilGrids: ",
         "install.packages(\"geodata\").", call. = FALSE)
  }
  ext <- .tiles_coerce_ext(aoi)
  layers <- lapply(variables, function(v) {
    r <- geodata::soil_world(var = v, depth = depth, stat = stat, path = path)
    r <- terra::crop(r, ext)
    names(r) <- paste0("soilgrids_", v)
    r
  })
  do.call(c, layers)
}

#' Fetch a WorldClim 2.1 climate stack over an AoI
#'
#' Keyless download of WorldClim 2.1 variables for a given country or
#' bounding box via `geodata::worldclim_country()` (country-scope) or
#' `geodata::worldclim_global()` (global scope, needs resolution).
#' Cropped to `aoi` and returned as a multi-layer `terra::SpatRaster`.
#'
#' @param variables Character vector. Any of
#'   `c("tavg","tmin","tmax","prec","wind","vapr","bio","elev","srad")`.
#' @param country Optional ISO3 code (e.g. `"BRA"`). If `NULL`,
#'   `res` is used instead.
#' @param res Spatial resolution in arc-minutes (`2.5`, `5`, `10`)
#'   for global downloads.
#' @param aoi See [foundation_tile_source_soilgrids()].
#' @param path Cache directory.
#'
#' @return A `terra::SpatRaster`.
#' @export
foundation_tile_source_worldclim <- function(variables = c("prec", "tavg"),
                                               country = NULL, res = 2.5,
                                               aoi, path = tempdir()) {
  .tiles_require_terra()
  if (!requireNamespace("geodata", quietly = TRUE)) {
    stop("Install `geodata` for WorldClim: ",
         "install.packages(\"geodata\").", call. = FALSE)
  }
  ext <- .tiles_coerce_ext(aoi)
  layers <- lapply(variables, function(v) {
    r <- if (!is.null(country)) {
      geodata::worldclim_country(country, var = v, path = path)
    } else {
      geodata::worldclim_global(var = v, res = res, path = path)
    }
    r <- terra::crop(r, ext)
    names(r) <- paste0("wc_", v, "_", sprintf("%02d", seq_len(terra::nlyr(r))))
    r
  })
  do.call(c, layers)
}

#' Fetch an SRTM elevation raster over an AoI
#'
#' Wraps `geodata::elevation_30s()` (global, 30 arc-second SRTM) and
#' crops it to the AoI. Optionally derives `slope` and `aspect` via
#' `terra::terrain()`.
#'
#' @param aoi See [foundation_tile_source_soilgrids()].
#' @param derive Character vector of additional topographic layers to
#'   compute. Any subset of `c("slope","aspect","TPI","TRI","roughness")`.
#' @param country Optional ISO3 code for country-scope download.
#' @param path Cache directory.
#'
#' @return A `terra::SpatRaster` with layer `elev` plus any derived
#'   layers.
#' @export
foundation_tile_source_srtm <- function(aoi, derive = c("slope"),
                                          country = "BRA",
                                          path = tempdir()) {
  .tiles_require_terra()
  if (!requireNamespace("geodata", quietly = TRUE)) {
    stop("Install `geodata` for SRTM: install.packages(\"geodata\").",
         call. = FALSE)
  }
  ext <- .tiles_coerce_ext(aoi)
  elev <- geodata::elevation_30s(country = country, path = path)
  elev <- terra::crop(elev, ext)
  names(elev) <- "elev"
  extras <- lapply(derive, function(d) {
    r <- terra::terrain(elev, v = d, unit = "degrees")
    names(r) <- d
    r
  })
  do.call(c, c(list(elev), extras))
}

#' MODIS source stub (needs NASA EarthData credentials)
#'
#' Returns a documented error pointing the user to `MODIStsp`, `rgee`
#' or a manual pre-processing step. Provided so that downstream code
#' can reference a canonical MODIS entry point; the implementation
#' will be filled in once the package takes a harder dependency on a
#' MODIS client.
#'
#' Users who already have a MODIS mosaic on disk can skip this
#' function entirely and pass their raster straight to
#' [foundation_tile_align()].
#'
#' @param ... Ignored.
#' @return Nothing; always stops with an install-hint message.
#' @export
foundation_tile_source_modis <- function(...) {
  stop(
    "MODIS ingestion requires NASA EarthData credentials and a MODIS ",
    "client. Install `MODIStsp` or use `rgee` via `reticulate`, ",
    "pre-process your tiles into a GeoTIFF mosaic, and then pass the ",
    "resulting `terra::SpatRaster` straight to ",
    "`foundation_tile_align()`.", call. = FALSE
  )
}

#' ERA5 source stub (needs Copernicus CDS key)
#'
#' Returns a documented error pointing users to `ecmwfr`. As with
#' MODIS, once a CDS key is configured the downloaded NetCDF can be
#' converted to a `terra::SpatRaster` and fed directly into
#' [foundation_tile_align()].
#'
#' @param ... Ignored.
#' @export
foundation_tile_source_era5 <- function(...) {
  stop(
    "ERA5 ingestion requires a Copernicus Climate Data Store API key. ",
    "Install `ecmwfr`, authenticate with `ecmwfr::wf_set_key()`, ",
    "download the NetCDFs via `ecmwfr::wf_request()`, then convert to ",
    "a `terra::SpatRaster` and pass it to `foundation_tile_align()`.",
    call. = FALSE
  )
}

# ---- Internal helpers -------------------------------------------------------

.tiles_coerce_ext <- function(aoi) {
  .tiles_require_terra()
  if (inherits(aoi, "SpatExtent")) return(aoi)
  if (inherits(aoi, "bbox")) {
    return(terra::ext(aoi["xmin"], aoi["xmax"], aoi["ymin"], aoi["ymax"]))
  }
  if (is.numeric(aoi) && length(aoi) == 4L) {
    return(terra::ext(aoi[1L], aoi[2L], aoi[3L], aoi[4L]))
  }
  stop("Unsupported AoI. Pass a SpatExtent, an sf bbox, or a length-4 ",
       "numeric vector c(xmin, xmax, ymin, ymax).", call. = FALSE)
}

#' Align multiple raster sources onto a common analysis grid
#'
#' Projects every input `SpatRaster` onto a single template (common
#' CRS, common resolution, common extent), stacks them channel-wise,
#' and returns the unified mosaic. Designed to be robust to mixed
#' resolutions (SoilGrids at 250 m, WorldClim at 30 arc-sec, SRTM at
#' 30 arc-sec, MODIS at 250 m, ERA5 at 0.1 degree) so MoCo v2
#' pretraining can consume a single multi-channel tensor.
#'
#' @param sources Named list of `terra::SpatRaster` objects.
#' @param target_res Numeric resolution of the output grid, in the
#'   units of `target_crs`.
#' @param target_crs Character EPSG code of the output CRS (default
#'   `"EPSG:4326"`).
#' @param aoi Optional AoI to crop after reprojection (see
#'   [foundation_tile_source_soilgrids()]).
#' @param method Resampling method for `terra::project()`. Defaults
#'   to `"bilinear"` (good for continuous covariates).
#'
#' @return A single `terra::SpatRaster` with one layer per input
#'   layer, aligned.
#' @export
foundation_tile_align <- function(sources, target_res = 0.005,
                                    target_crs = "EPSG:4326",
                                    aoi = NULL,
                                    method = "bilinear") {
  .tiles_require_terra()
  stopifnot(is.list(sources), length(sources) >= 1L)
  # Template grid: largest bbox across all sources, at target_res.
  exts <- lapply(sources, function(s) {
    r <- terra::project(s[[1L]], target_crs, method = "near")
    terra::ext(r)
  })
  xmin <- min(vapply(exts, function(e) e$xmin, numeric(1L)))
  xmax <- max(vapply(exts, function(e) e$xmax, numeric(1L)))
  ymin <- min(vapply(exts, function(e) e$ymin, numeric(1L)))
  ymax <- max(vapply(exts, function(e) e$ymax, numeric(1L)))
  template <- terra::rast(
    terra::ext(xmin, xmax, ymin, ymax),
    resolution = target_res,
    crs = target_crs
  )
  if (!is.null(aoi)) template <- terra::crop(template, .tiles_coerce_ext(aoi))

  aligned <- lapply(sources, function(s) {
    terra::project(s, template, method = method)
  })
  # SpatRaster concatenation needs the S4 method; Reduce guarantees
  # the right `c` dispatch rather than falling through to base::c.
  Reduce(function(a, b) c(a, b), aligned)
}

# ---- Lazy tile dataset ------------------------------------------------------

#' Build a lazy patch dataset over a `terra::SpatRaster`
#'
#' Returns an `edaphos_tile_dataset` S3 object that knows how to sample
#' batched `(B, C, H, W)` tensors from the underlying raster on demand
#' -- without ever loading the whole mosaic into memory. The dataset
#' is what [foundation_moco_pretrain_tiles()] consumes.
#'
#' Patch centres are drawn uniformly within the AoI, optionally
#' constrained to a `valid_mask` (e.g. a land-sea mask or a biome
#' polygon). Each patch is a `patch_size x patch_size` window
#' extracted from the raster; missing values are replaced by the
#' per-layer mean.
#'
#' @param stack A `terra::SpatRaster` with the channels to sample.
#' @param patch_size Integer -- spatial side of each patch.
#' @param n_patches Integer -- total number of patches the dataset
#'   should expose. Sampling is with replacement when
#'   `n_patches > total valid cells`.
#' @param valid_mask Optional `terra::SpatRaster` of 0/1 defining
#'   which cells are eligible as patch centres.
#' @param normalise Logical -- if `TRUE` (default) each channel is
#'   standardised to zero mean / unit standard deviation based on the
#'   raster's global statistics.
#' @param seed Optional integer for reproducibility.
#'
#' @return A list of class `edaphos_tile_dataset` with slots
#'   `stack`, `patch_size`, `n_patches`, `n_channels`, `means`,
#'   `sds`, `valid_cells`; and a `sample(batch_size)` function that
#'   returns a `(batch_size, C, H, W)` R array.
#' @export
foundation_tile_dataset <- function(stack, patch_size = 16L,
                                      n_patches = 1000L,
                                      valid_mask = NULL,
                                      normalise  = TRUE,
                                      seed = NULL) {
  .tiles_require_terra()
  stopifnot(inherits(stack, "SpatRaster"),
            patch_size >= 2L, n_patches >= 1L)
  if (!is.null(seed)) set.seed(seed)
  patch_size <- as.integer(patch_size)
  n_patches  <- as.integer(n_patches)
  C <- terra::nlyr(stack)

  # Per-layer global statistics for normalisation.
  if (normalise) {
    stats <- terra::global(stack, c("mean", "sd"), na.rm = TRUE)
    means <- as.numeric(stats$mean)
    sds   <- as.numeric(stats$sd)
    sds[!is.finite(sds) | sds == 0] <- 1
  } else {
    means <- rep(0, C); sds <- rep(1, C)
  }

  # Valid centre cells: either every finite cell in layer 1 or the
  # intersection with `valid_mask`.
  base <- stack[[1L]]
  valid_vec <- !is.na(terra::values(base))[, 1L]
  if (!is.null(valid_mask)) {
    vm <- terra::resample(valid_mask, base, method = "near")
    valid_vec <- valid_vec & (terra::values(vm)[, 1L] > 0)
    valid_vec[is.na(valid_vec)] <- FALSE
  }
  valid_cells <- which(valid_vec)
  if (length(valid_cells) == 0L) {
    stop("No valid cells in the provided raster / mask.", call. = FALSE)
  }
  nrow_r <- terra::nrow(stack); ncol_r <- terra::ncol(stack)
  half <- patch_size %/% 2L
  rc <- terra::rowColFromCell(stack, valid_cells)
  keep <- rc[, 1L] >= half + 1L & rc[, 1L] <= nrow_r - half &
          rc[, 2L] >= half + 1L & rc[, 2L] <= ncol_r - half
  valid_cells <- valid_cells[keep]
  if (length(valid_cells) == 0L) {
    stop("No valid cells leave enough margin for patch_size = ",
         patch_size, ".", call. = FALSE)
  }
  patch_cells <- sample(valid_cells, n_patches,
                         replace = n_patches > length(valid_cells))

  sample_fn <- function(batch_size) {
    stopifnot(batch_size >= 1L, batch_size <= n_patches)
    idx <- sample(n_patches, batch_size)
    cells <- patch_cells[idx]
    rcs <- terra::rowColFromCell(stack, cells)
    out <- array(0, dim = c(batch_size, C, patch_size, patch_size))
    for (b in seq_len(batch_size)) {
      r0 <- rcs[b, 1L] - half
      c0 <- rcs[b, 2L] - half
      block <- terra::values(
        stack,
        row = r0, nrows = patch_size,
        col = c0, ncols = patch_size,
        mat = TRUE
      )   # (patch_size * patch_size) x C
      arr <- aperm(
        array(block, dim = c(patch_size, patch_size, C)),
        c(3L, 1L, 2L)
      )  # C x H x W
      # Normalise and impute NAs with zero (post-centering = column mean).
      for (k in seq_len(C)) {
        v <- (arr[k, , ] - means[k]) / sds[k]
        v[is.na(v)] <- 0
        arr[k, , ] <- v
      }
      out[b, , , ] <- arr
    }
    out
  }

  structure(
    list(
      stack       = stack,
      patch_size  = patch_size,
      n_patches   = n_patches,
      n_channels  = C,
      means       = means,
      sds         = sds,
      patch_cells = patch_cells,
      sample      = sample_fn
    ),
    class = "edaphos_tile_dataset"
  )
}

#' @export
print.edaphos_tile_dataset <- function(x, ...) {
  cat("<edaphos_tile_dataset>\n")
  cat(sprintf("  stack       : %d x %d x %d (rows x cols x channels)\n",
              terra::nrow(x$stack), terra::ncol(x$stack),
              x$n_channels))
  cat(sprintf("  patch_size  : %d x %d\n", x$patch_size, x$patch_size))
  cat(sprintf("  n_patches   : %d\n", x$n_patches))
  cat("  channels    : ",
      paste(names(x$stack), collapse = ", "), "\n", sep = "")
  invisible(x)
}
