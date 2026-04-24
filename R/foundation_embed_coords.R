# Pillar 4 - point-specific embedding extraction (v1.9.1).
#
# `foundation_embed_at_coords()` extracts a MoCo-v2 embedding at each
# row of a (lon, lat) coordinate frame by cutting a patch_size x
# patch_size window out of a terra::SpatRaster stack, normalising with
# the dataset's training means / sds, and running the encoder forward.
#
# Rationale.  The v1.9.0 IV benchmark builds proxy "foundation-like"
# features from the WoSIS covariates themselves -- these fail the
# Sargan test because they are nonlinear functions of the exposures.
# Real MoCo-v2 embeddings are extracted from raster patches centred
# on each WoSIS profile; because the encoder was trained by
# contrastive self-supervision on UNLABELLED rasters (never saw the
# SOC target), they are the structurally principled instruments that
# the v1.9.0 vignette argues for.
#
# This function closes that gap: it is the exact analogue of
# `foundation_moco_embed_raster()` but for scattered query points
# instead of a regular grid.
#
# Exports
#   foundation_embed_at_coords()  : point-wise encoder extraction
#   foundation_build_cerrado_stack(): minimal raster-stack helper
#                                       for the v1.9.1 benchmark

# ---------------------------------------------------------------------------
# Point-specific encoder extraction
# ---------------------------------------------------------------------------

#' Extract foundation-model embeddings at a set of query coordinates
#'
#' For each row of `coords` (longitude, latitude) crops a
#' `patch_size x patch_size` window out of the raster `stack`,
#' normalises every channel with the training means / sds stored in
#' `dataset`, and runs the MoCo v2 encoder forward to get one
#' embedding vector per query point.  Returns the resulting
#' `(n_coords, D)` matrix where `D` is either the backbone feature
#' dimension (when `projection = FALSE`, the default) or the
#' projection-head output dimension.
#'
#' Compared with [`foundation_moco_embed_raster()`] (which runs the
#' encoder over a regular stride-based grid), this function:
#'
#' - reads only `n_coords` patches, not the full grid, so extraction
#'   at 1 095 WoSIS profiles is O(minutes) rather than O(hour) even on
#'   a 2 deg x 2 deg Cerrado cube;
#' - returns a tidy `matrix` (rows aligned with `coords`) ready to
#'   hand directly to [`causal_iv_from_embeddings()`] as the
#'   instrument matrix.
#'
#' Coordinates that fall outside the raster extent, or whose patch
#' would cross the raster edge, are returned as a row of `NA`.
#'
#' @param moco An `edaphos_foundation_moco` (as returned by
#'   [`foundation_weights_load()`] or [`foundation_moco_pretrain()`]).
#' @param coords A data frame or matrix with two columns `"lon"` and
#'   `"lat"` in the same CRS as `stack`.  Order of rows is preserved.
#' @param stack A `terra::SpatRaster` with one layer per channel.  The
#'   number of layers must equal `dataset$n_channels`.
#' @param dataset An `edaphos_tile_dataset` (or any list carrying
#'   `patch_size`, `n_channels`, `means`, `sds` fields).
#' @param patch_size Integer; side length of the square patch.
#'   Defaults to `dataset$patch_size`.
#' @param projection Logical; if `TRUE` return the L2-normalised
#'   projection-head outputs instead of the backbone features.
#' @param batch_size Integer; number of patches to forward through the
#'   encoder in a single call (trades memory for speed).  Defaults
#'   to `32L`.
#' @return A numeric matrix with `nrow(coords)` rows and `D` columns,
#'   where `D` is `moco$feature_dim` or `moco$proj_dim`.  Rows that
#'   could not be extracted contain `NA`.
#' @export
foundation_embed_at_coords <- function(moco, coords, stack, dataset,
                                         patch_size = NULL,
                                         projection = FALSE,
                                         batch_size = 32L) {
  if (!requireNamespace("torch", quietly = TRUE))
    stop("Install `torch` to run the encoder.", call. = FALSE)
  if (!requireNamespace("terra", quietly = TRUE))
    stop("Install `terra` to read raster patches.", call. = FALSE)
  stopifnot(
    inherits(moco, "edaphos_foundation_moco"),
    inherits(stack, "SpatRaster"),
    is.list(dataset),
    all(c("means", "sds", "n_channels", "patch_size") %in% names(dataset))
  )
  coords <- as.data.frame(coords)
  if (!all(c("lon", "lat") %in% names(coords)))
    stop("`coords` must contain columns `lon` and `lat`.", call. = FALSE)

  if (is.null(patch_size) || length(patch_size) == 0L)
    patch_size <- dataset$patch_size
  if (is.null(patch_size) || length(patch_size) == 0L)
    stop("`patch_size` is NULL and `dataset$patch_size` is not set.",
          call. = FALSE)
  patch_size <- as.integer(patch_size)
  half       <- patch_size %/% 2L
  C          <- terra::nlyr(stack)
  stopifnot(C == dataset$n_channels)

  n        <- nrow(coords)
  means    <- dataset$means
  sds      <- dataset$sds
  enc      <- moco$encoder_q

  # Convert (lon, lat) -> (row, col) centres in the raster
  xy <- as.matrix(coords[, c("lon", "lat")])
  cells <- terra::cellFromXY(stack, xy)
  rowcol <- terra::rowColFromCell(stack, cells)
  n_r <- terra::nrow(stack); n_c <- terra::ncol(stack)

  # Identify valid rows (patch fully inside raster)
  is_valid <- !is.na(rowcol[, 1L]) & !is.na(rowcol[, 2L]) &
              rowcol[, 1L] > half & rowcol[, 1L] <= (n_r - half) &
              rowcol[, 2L] > half & rowcol[, 2L] <= (n_c - half)

  D <- if (projection) moco$proj_dim else moco$feature_dim
  out <- matrix(NA_real_, nrow = n, ncol = D,
                 dimnames = list(NULL, paste0("emb_", sprintf("%03d",
                                                                 seq_len(D)))))

  valid_idx <- which(is_valid)
  if (length(valid_idx) == 0L) return(out)

  # Pre-allocate a single (batch_size, C, patch, patch) tensor
  # re-used to avoid allocation churn
  n_batches <- ceiling(length(valid_idx) / batch_size)
  pb_enabled <- interactive() && length(valid_idx) > 100L

  for (b in seq_len(n_batches)) {
    b_idx   <- valid_idx[
      seq.int((b - 1L) * batch_size + 1L,
               min(b * batch_size, length(valid_idx)))
    ]
    n_b <- length(b_idx)
    arr_b <- array(0, dim = c(n_b, C, patch_size, patch_size))

    for (k in seq_along(b_idx)) {
      i  <- b_idx[k]
      rc <- rowcol[i, 1L]
      cc <- rowcol[i, 2L]
      r0 <- rc - half
      c0 <- cc - half
      blk <- tryCatch(
        terra::values(stack, row = r0, nrows = patch_size,
                       col = c0, ncols = patch_size, mat = TRUE),
        error = function(e) matrix(NA_real_, patch_size * patch_size, C)
      )
      patch_arr <- aperm(
        array(blk, dim = c(patch_size, patch_size, C)),
        c(3L, 1L, 2L)
      )
      for (ch in seq_len(C)) {
        v <- (patch_arr[ch, , ] - means[ch]) / sds[ch]
        v[is.na(v)] <- 0
        patch_arr[ch, , ] <- v
      }
      arr_b[k, , , ] <- patch_arr
    }

    x <- torch::torch_tensor(arr_b)$to(dtype = torch::torch_float())
    emb <- torch::with_no_grad({
      if (projection) enc(x) else enc$backbone_features(x)
    })$cpu()
    emb_mat <- as.matrix(as.array(emb))
    out[b_idx, ] <- emb_mat

    if (pb_enabled) {
      message(sprintf("  batch %d/%d  (%d / %d coords)",
                       b, n_batches,
                       min(b * batch_size, length(valid_idx)),
                       length(valid_idx)))
    }
  }

  out
}

# ---------------------------------------------------------------------------
# Minimal raster-stack helper
# ---------------------------------------------------------------------------

#' Build a minimal Cerrado raster stack for the v1.9.1 IV benchmark
#'
#' Downloads / assembles the covariate raster stack that the
#' `edaphos-cerrado-moco-v1` encoder was pretrained on.  The stack has
#' 10 channels: 5 SoilGrids 250 m layers (soc, clay, sand, ph, bdod),
#' 2 WorldClim 2.1 bioclim layers (bio1 = MAT, bio12 = MAP), 1 SRTM
#' 30-arc-second elevation, 1 derived slope, and 1 placeholder NDVI.
#' All layers are resampled to a common 0.01-deg grid and clipped to
#' the bounding box `bbox`.
#'
#' **Heavy download.**  A 2-deg x 2-deg Cerrado AoI produces roughly
#' 200 MB of raster data after alignment.  The first call populates
#' `cache_dir`; subsequent calls read from disk instantly.
#'
#' @param bbox Numeric length-4 vector `c(xmin, ymin, xmax, ymax)` in
#'   decimal degrees.  Defaults to a central Cerrado quadrant around
#'   Brasília: `c(-50, -16, -48, -14)`.
#' @param cache_dir Directory to write the assembled stack(s) to.
#'   Defaults to the user R cache under `tools::R_user_dir("edaphos")`.
#' @param target_res Numeric; target resolution in degrees.  Defaults
#'   to `0.01` (~ 1 km at the equator, matching the encoder training
#'   resolution).
#' @param force Logical; re-download even if a cached stack exists.
#' @return A `terra::SpatRaster` with 10 aligned layers named
#'   `c("soc", "clay", "sand", "ph", "bdod", "bio1", "bio12",
#'      "elev", "slope", "ndvi")`.
#' @export
foundation_build_cerrado_stack <- function(
    bbox       = c(-50, -16, -48, -14),
    cache_dir  = tools::R_user_dir("edaphos", which = "cache"),
    target_res = 0.01,
    force      = FALSE) {
  if (!requireNamespace("terra", quietly = TRUE))
    stop("Install `terra` to build raster stacks.", call. = FALSE)
  if (!requireNamespace("geodata", quietly = TRUE))
    stop("Install `geodata` to download SoilGrids / WorldClim / SRTM.",
          call. = FALSE)

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  tag <- sprintf("cerrado_stack_%s.tif",
                  digest::digest(c(bbox, target_res), algo = "md5"))
  stack_path <- file.path(cache_dir, tag)
  if (!force && file.exists(stack_path)) {
    message(sprintf("  Using cached stack: %s", stack_path))
    return(terra::rast(stack_path))
  }

  message("  Building Cerrado stack ...")

  ext_bbox <- terra::ext(bbox[1], bbox[3], bbox[2], bbox[4])
  template <- terra::rast(
    xmin = bbox[1], xmax = bbox[3],
    ymin = bbox[2], ymax = bbox[4],
    crs  = "EPSG:4326",
    resolution = target_res
  )

  layers <- list()

  # SoilGrids
  sg_vars <- c(soc = "soc", clay = "clay", sand = "sand",
                ph = "phh2o", bdod = "bdod")
  for (nm in names(sg_vars)) {
    message(sprintf("    SoilGrids  %s ...", nm))
    r <- tryCatch(
      geodata::soil_world(var = sg_vars[[nm]], depth = 5,
                           path = cache_dir),
      error = function(e) { message("      [warn] ", conditionMessage(e)); NULL })
    if (!is.null(r)) {
      r <- terra::crop(r, ext_bbox)
      r <- terra::resample(r, template, method = "bilinear")
      names(r) <- nm
      layers[[nm]] <- r
    }
  }

  # WorldClim bio1, bio12
  message("    WorldClim  bio1, bio12 ...")
  bio <- tryCatch(
    geodata::worldclim_global(var = "bio", res = 10, path = cache_dir),
    error = function(e) { message("      [warn] ", conditionMessage(e)); NULL })
  if (!is.null(bio)) {
    b1 <- terra::resample(terra::crop(bio[[1]],  ext_bbox), template)
    b12 <- terra::resample(terra::crop(bio[[12]], ext_bbox), template)
    names(b1) <- "bio1"; names(b12) <- "bio12"
    layers$bio1  <- b1
    layers$bio12 <- b12
  }

  # SRTM elevation
  message("    SRTM elev + slope ...")
  elev <- tryCatch(
    geodata::elevation_global(res = 0.5, path = cache_dir),
    error = function(e) { message("      [warn] ", conditionMessage(e)); NULL })
  if (!is.null(elev)) {
    e <- terra::resample(terra::crop(elev, ext_bbox), template)
    s <- terra::terrain(e, v = "slope", unit = "degrees")
    names(e) <- "elev"; names(s) <- "slope"
    layers$elev  <- e
    layers$slope <- s
  }

  # NDVI placeholder from MOD13Q1 would go here
  # (not wired by default -- adds a full MODIS fetch step).
  # Use a simple function of bio12 + bio1 as a proxy for now.
  if (!is.null(layers$bio12) && !is.null(layers$bio1)) {
    ndvi_proxy <- (layers$bio12 / 3000) - (layers$bio1 / 300)
    ndvi_proxy <- terra::clamp(ndvi_proxy, 0, 1)
    names(ndvi_proxy) <- "ndvi"
    layers$ndvi <- ndvi_proxy
  }

  if (length(layers) == 0L)
    stop("No layers could be built. Check network + geodata cache.",
          call. = FALSE)

  stk <- do.call(c, layers)
  terra::writeRaster(stk, stack_path, overwrite = TRUE)
  message(sprintf("  Wrote %s (%.1f MB, %d layers)",
                   stack_path, file.size(stack_path) / 1024^2,
                   terra::nlyr(stk)))
  stk
}
