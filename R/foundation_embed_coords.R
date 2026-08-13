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
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed()) &&
#'     requireNamespace("terra", quietly = TRUE)) {
#'
#'   # A 2 deg x 2 deg Cerrado tile at 0.05 deg (40 x 40 cells) with
#'   # three covariate channels, standing in for the 31-channel stack
#'   # that foundation_build_cerrado_stack() downloads.
#'   cerrado <- terra::rast(nrows = 40, ncols = 40,
#'                          xmin = -50, xmax = -48,
#'                          ymin = -16, ymax = -14,
#'                          crs = "EPSG:4326", nlyrs = 3)
#'   xy <- terra::xyFromCell(cerrado, seq_len(terra::ncell(cerrado)))
#'   terra::values(cerrado) <- cbind(
#'     900 + 260 * sin((xy[, 1] + 50) * 2.4) - 140 * (xy[, 2] + 16),
#'     1500 - 90 * (xy[, 1] + 50) + 40 * cos((xy[, 2] + 16) * 3),
#'     0.45 + 0.18 * sin((xy[, 1] + 50) * 1.7 + (xy[, 2] + 16)))
#'   names(cerrado) <- c("elev", "map_mm", "ndvi")
#'
#'   # Touch torch once before relying on `seed`: the call that loads
#'   # the backend does not keep it.
#'   invisible(torch::torch_manual_seed(11L))
#'   set.seed(42)
#'   tiles <- foundation_tile_dataset(cerrado, patch_size = 8L,
#'                                    n_patches = 24L, seed = 1)
#'   moco  <- foundation_moco_pretrain(tiles$sample(12),
#'                                     feature_dim = 8L, proj_dim = 4L,
#'                                     epochs = 2L, batch_size = 6L,
#'                                     seed = 11L)
#'
#'   # Five profiles: three interior, one outside the tile, and one
#'   # inside it but in the very first column of cells.
#'   sites <- data.frame(
#'     site = c("BR-01", "BR-02", "BR-03", "BR-04", "BR-05"),
#'     lon  = c(-49.50, -48.70, -49.10, -46.20, -49.96),
#'     lat  = c(-15.40, -14.60, -15.50, -15.00, -15.40))
#'
#'   # Put the encoder in eval mode before extracting anything.
#'   # foundation_moco_pretrain() hands it back in TRAINING mode and
#'   # the backbone is full of BatchNorm, which in training mode
#'   # standardises with the statistics of the batch in front of it:
#'   # a site's embedding then depends on which other sites share its
#'   # batch, and `batch_size` stops being only a memory knob.
#'   b32 <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
#'                                     batch_size = 32L)
#'   b01 <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
#'                                     batch_size = 1L)
#'   invisible(moco$encoder_q$eval())
#'   e32 <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
#'                                     batch_size = 32L)
#'   e01 <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
#'                                     batch_size = 1L)
#'   # First entry is the size of the leak; the second is zero to
#'   # numerical precision.
#'   print(c(train_mode = max(abs(b32 - b01), na.rm = TRUE),
#'           eval_mode  = max(abs(e32 - e01), na.rm = TRUE)))
#'
#'   # One row per site, in the order supplied, `feature_dim` columns
#'   # named emb_001 ... emb_008.
#'   print(dim(e32))
#'   print(colnames(e32))
#'
#'   # Rows 4 and 5 come back all NA for two different reasons that
#'   # look identical in the output: BR-04 is outside the raster,
#'   # while BR-05 is inside it but a patch centred there would run
#'   # off the western edge.  Carry the site identifiers alongside --
#'   # the matrix has no row names to tell you which is which.
#'   print(cbind(sites["site"], usable = stats::complete.cases(e32)))
#'
#'   # The margin required is exactly `patch_size %/% 2` = 4 cells.
#'   # Marching east from the western edge, the first four columns of
#'   # the raster are refused and the fifth is the first that returns
#'   # an embedding.
#'   transect <- data.frame(lon = -49.975 + 0.05 * (0:5), lat = -15.4)
#'   print(is.na(foundation_embed_at_coords(moco, transect, cerrado,
#'                                          tiles)[, 1]))
#'
#'   # NA is only ever a geometric verdict.  Missing covariate values
#'   # inside the window are imputed at the channel mean, so a site
#'   # sitting on a NoData hole still gets a full embedding row --
#'   # only terra::extract() will tell you it is uninformed.
#'   holed <- cerrado
#'   hole  <- terra::cellFromXY(holed, as.matrix(expand.grid(
#'     lon = -49.10 + c(-0.05, 0, 0.05),
#'     lat = -15.50 + c(-0.05, 0, 0.05))))
#'   vals <- terra::values(holed)
#'   vals[hole, ] <- NA
#'   terra::values(holed) <- vals
#'   emb_holed <- foundation_embed_at_coords(moco, sites, holed, tiles)
#'   # All three covariates are NA at BR-03 (column 1 is terra's ID),
#'   # yet the embedding row is finite.
#'   print(terra::extract(holed, sites[3, c("lon", "lat")]))
#'   print(all(is.finite(emb_holed[3, ])))
#'
#'   # `projection = TRUE` returns the L2-normalised projection head
#'   # instead of the backbone features: `proj_dim` columns, and every
#'   # extracted row has unit length.
#'   proj <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
#'                                      projection = TRUE)
#'   ok <- stats::complete.cases(proj)
#'   print(c(ncol = ncol(proj),
#'           norm = unique(round(sqrt(rowSums(proj[ok, ]^2)), 6))))
#' }
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
  # The encoder may have been trained on "mps"/"cuda", leaving its weights on
  # that device, while the patch tensors below are built on the CPU. Running a
  # CPU input through GPU-resident weights throws a device mismatch (surfacing
  # on macOS as "Mismatched Tensor types in NNPack convolutionOutput"). Embedding
  # is a one-shot forward pass, so move the encoder to the CPU for it and put it
  # in eval mode; the returned embeddings are already `$cpu()` below.
  if (inherits(enc, "nn_module")) {
    enc <- enc$to(device = torch::torch_device("cpu"))
    enc$eval()
  }

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
# The channel contract of each stack schema.  `foundation_build_cerrado_stack()`
# asserts against these before writing anything to the cache, because the
# encoder's input layer is fixed and a short stack is not a smaller stack --
# it is the wrong stack.
.stack_layer_names <- function(schema = c("v1_encoder", "minimal")) {
  schema <- match.arg(schema)
  sg <- c("soc", "clay", "sand", "phh2o", "bdod")
  if (schema == "v1_encoder")
    c(sg, sprintf("wc_prec_%02d", 1:12), sprintf("wc_tavg_%02d", 1:12),
      "elev", "slope")
  else
    c(sg, "bio1", "bio12", "elev", "slope", "ndvi")
}

.stack_expected_layers <- function(schema = c("v1_encoder", "minimal")) {
  length(.stack_layer_names(match.arg(schema)))
}

# Is a file sitting at a schema-keyed cache path actually a stack for that
# schema? Split out of the cache-hit branch so it can be tested without the
# network: the branch itself falls through to a rebuild, and a rebuild needs
# every remote source, which is not a thing a unit test should require to
# prove that a two-layer file is not a thirty-one-layer stack.
#
# Returns TRUE, or a character string saying what is wrong -- a shape that
# lets the caller put the reason in its message rather than inventing one.
.cached_stack_ok <- function(path, schema) {
  want <- .stack_layer_names(schema)
  # Warnings suppressed as well as errors: terra grumbles on a file that is
  # not a raster, and that grumble is this function's input, not its output.
  r <- suppressWarnings(tryCatch(terra::rast(path), error = function(e) NULL))
  if (is.null(r)) return("unreadable")
  n <- terra::nlyr(r)
  if (n != length(want))
    return(sprintf("%d layers, expected %d", n, length(want)))
  if (!identical(names(r), want))
    return(sprintf("layer names differ (first mismatch: %s)",
                   utils::head(setdiff(want, names(r)), 1L)))
  TRUE
}


#' Build the Cerrado raster stack for IV / quantum-foundation benchmarks
#'
#' Downloads / assembles the covariate raster stack that the
#' `edaphos-cerrado-moco-v1` encoder was pretrained on.  As of v4.0.0
#' the stack matches the v1 encoder's 31-channel input schema:
#'
#' \itemize{
#'   \item 5 SoilGrids layers for the 0-5 cm interval
#'         (`soc`, `clay`, `sand`, `phh2o`, `bdod`)
#'   \item 12 monthly WorldClim 2.1 precipitation layers
#'         (`wc_prec_01` ... `wc_prec_12`)
#'   \item 12 monthly WorldClim 2.1 mean-temperature layers
#'         (`wc_tavg_01` ... `wc_tavg_12`)
#'   \item `elev`, the 30-arc-second SRTM aggregation, plus `slope`
#'         derived from it locally with `terra::terrain()` -- `slope`
#'         is computed, not downloaded
#' }
#'
#' Every source arrives at 30 arc-seconds (roughly 1 km), so this is a
#' ~1 km stack throughout.  `geodata::soil_world()` serves the 30
#' arc-second aggregation of SoilGrids -- it rewrites its own URL to
#' `soc_0-5cm_mean_30s.tif` and friends -- not SoilGrids' native 250 m;
#' WorldClim 2.1 country tiles are 30 arc-second; and
#' `geodata::elevation_30s()` is the 30 arc-second aggregation of the
#' 90 m CGIAR-SRTM.  All 31 layers are resampled to a common
#' `target_res`-degree grid and clipped to `bbox`.  That grid is finer
#' than the data it carries: resampling onto it does not restore
#' detail the sources never had.
#'
#' Earlier versions assembled only a 10-channel subset, which forced
#' the IV benchmark (`data-raw/causal_iv_benchmark_real.R`) to fall
#' back to a synthetic 31-channel stack -- the v4.0.0 rewrite closes
#' that gap.
#'
#' **Heavy download.**  Not because of the file it writes: the default
#' 2-deg x 2-deg AoI at 0.01 deg is 200 x 200 cells x 31 `FLT4S`
#' layers, single-digit megabytes on disk.  The cost is what `geodata`
#' fetches in order to build it and leaves behind in `cache_dir` --
#' five global SoilGrids rasters and the whole-Brazil WorldClim `prec`
#' and `tavg` tiles, all cropped only after they land.  Shrinking
#' `bbox` does not shrink the download.  The example measures both.
#'
#' @param bbox Numeric length-4 vector `c(xmin, ymin, xmax, ymax)` in
#'   decimal degrees.  Defaults to a central Cerrado quadrant around
#'   Brasilia: `c(-50, -16, -48, -14)`.
#' @param cache_dir Directory to write the assembled stack(s) to.
#'   Defaults to the user R cache under `tools::R_user_dir("edaphos")`.
#' @param target_res Numeric; target resolution in degrees.  Defaults
#'   to `0.01` (about 1.1 km at the equator), the grid the v1 encoder
#'   was trained on and close to the 30 arc-second (0.00833 deg) grid
#'   every source arrives on.
#' @param force Logical; re-download even if a cached stack exists.
#' @param schema One of `"v1_encoder"` (default; 31-channel encoder-
#'   compatible stack) or `"minimal"` (10-channel legacy stack used
#'   pre-v4.0.0).  Pass `"minimal"` to reproduce the older bundles.
#' @return A `terra::SpatRaster` with the requested number of aligned
#'   layers.
#' @examples
#' \dontrun{
#' # Needs `terra`, `geodata` and `digest` installed, and a network.
#'
#' # The default call assembles the 31-layer "v1_encoder" stack over a
#' # 2 deg x 2 deg quadrant around Brasilia at 0.01 deg.  What actually
#' # crosses the wire: five GLOBAL SoilGrids rasters for the 0-5 cm
#' # interval, the whole Brazil WorldClim 2.1 country tiles for `prec`
#' # and `tavg` (12 monthly layers each, cropped only after download --
#' # this is the dominant cost), and the Brazil SRTM elevation tile.
#' # `slope` is not downloaded: it is derived locally from `elev` with
#' # terra::terrain().
#' stk <- foundation_build_cerrado_stack()
#' terra::nlyr(stk)             # 31
#' names(stk)[c(1:5, 30:31)]    # soc clay sand phh2o bdod elev slope
#'
#' # Every one of those sources is a 30 arc-second (roughly 1 km)
#' # product -- geodata rewrites the SoilGrids URL to end in
#' # "_30s.tif", so the native 250 m SoilGrids never enters this
#' # package.  The 0.01 deg output grid is finer than the data on it;
#' # the resample that put it there is interpolation, not detail.
#' terra::res(stk)              # 0.01 0.01
#' sg <- geodata::soil_world(var = "soc", depth = 5, vsi = TRUE)
#' terra::sources(sg)           # .../soc_0-5cm_mean_30s.tif
#' terra::res(sg)               # 0.008333333 = 1/120 deg = 30 arc-sec
#'
#' # The written file is small; the download is not, and both live in
#' # cache_dir.  Measure them instead of trusting either intuition.
#' cache_dir <- tools::R_user_dir("edaphos", which = "cache")
#' assembled <- list.files(cache_dir, pattern = "cerrado_stack_",
#'                         full.names = TRUE)
#' round(file.size(assembled) / 1024^2, 1)   # 200 x 200 x 31 FLT4S: a few MB
#' round(sum(file.size(list.files(cache_dir, recursive = TRUE,
#'                                full.names = TRUE)),
#'           na.rm = TRUE) / 1024^2, 1)      # the raw sources: far larger
#'
#' # The cache key is (schema, bbox, target_res): `schema` goes into
#' # the file name verbatim and the other two are md5-hashed after it,
#' # giving cerrado_stack_<schema>_<md5>.tif.  A repeat of the same
#' # call touches no network at all and reports "Using cached stack:".
#' stk_again <- foundation_build_cerrado_stack()
#' basename(terra::sources(stk_again))
#'
#' # A different AoI or resolution is a different key, hence a fresh
#' # download that lands beside the first one rather than replacing it.
#' # `force = TRUE` is the only way to re-fetch and overwrite the file
#' # for a key you have already built; it leaves the other keys alone.
#' stk_small <- foundation_build_cerrado_stack(bbox = c(-49, -15, -48, -14))
#' stk_fresh <- foundation_build_cerrado_stack(force = TRUE)
#'
#' # `cache_dir` is handed to geodata as its own download `path`, so
#' # the directory ends up holding the raw SoilGrids / WorldClim / SRTM
#' # rasters as well as the assembled .tif.  Point it at a disk with
#' # room, and reuse the same one across sessions.
#' stk_tmp <- foundation_build_cerrado_stack(
#'   cache_dir = file.path(tempdir(), "edaphos-stacks"))
#'
#' # "minimal" is not a smaller stack, it is a different one: 10 layers
#' # (soc, clay, sand, phh2o, bdod, bio1, bio12, elev, slope, ndvi) and
#' # no monthly climate at all.  The published v1 encoder's input layer
#' # is fixed at 31 channels -- `foundation_weights_list()` reports
#' # `n_channels` -- so a minimal stack cannot feed it.  It exists to
#' # reproduce the pre-v4.0.0 bundles.
#' legacy <- foundation_build_cerrado_stack(schema = "minimal")
#' terra::nlyr(legacy)          # 10
#'
#' # If any single source is unreachable, that layer is skipped with a
#' # warning and the function then stops with the list of missing
#' # names, having written nothing: a partially downloaded stack never
#' # reaches the cache, so a failed run cannot be silently inherited by
#' # the next one.
#'
#' # One exception to that loudness. `elev` is fetched with
#' # geodata::elevation_30s(country = "BRA"), which masks to the
#' # Brazilian border, so an AoI crossing into a neighbour comes back
#' # NA on the far side -- and `slope`, derived from it, with it.  If
#' # that call errors the code falls back to
#' # geodata::elevation_global(res = 0.5): the same 30 arc-seconds, but
#' # WorldClim's elevation product rather than SRTM, and unmasked.  No
#' # warning marks the substitution, and the layer is called `elev`
#' # either way.
#' terra::global(stk[[c("elev", "slope")]], "isNA")
#'
#' # Downstream: the stack feeds a tile dataset, and the dataset plus a
#' # pretrained encoder give one instrument row per soil profile.  Note
#' # that foundation_tile_dataset() derives the normalisation
#' # statistics from the stack you just built, not from the encoder's
#' # training run -- v1's training means / sds were never persisted
#' # (`foundation_weights_list()` reports `norm_stats_status` as
#' # "unrecoverable"), so this is the documented substitute, not a
#' # match.
#' tiles <- foundation_tile_dataset(stk, patch_size = 16L,
#'                                  n_patches = 2000L, seed = 1)
#' moco  <- foundation_weights_load("edaphos-cerrado-moco-v1")
#' profiles <- data.frame(lon = c(-49.5, -48.7), lat = c(-15.4, -14.6))
#' emb <- foundation_embed_at_coords(moco, profiles, stk, tiles)
#' dim(emb)                     # 2 x 64 = registry feature_dim for v1
#'
#' # Unlike foundation_moco_pretrain(), foundation_weights_load() calls
#' # $eval() before handing the encoder over, so the BatchNorm /
#' # batch_size interaction documented in the
#' # foundation_embed_at_coords() example does not apply here.  Check
#' # rather than assume if you built the encoder some other way.
#' moco$encoder_q$training      # FALSE
#' }
#' @export
foundation_build_cerrado_stack <- function(
    bbox       = c(-50, -16, -48, -14),
    cache_dir  = tools::R_user_dir("edaphos", which = "cache"),
    target_res = 0.01,
    force      = FALSE,
    schema     = c("v1_encoder", "minimal")) {
  if (!requireNamespace("terra", quietly = TRUE))
    stop("Install `terra` to build raster stacks.", call. = FALSE)
  if (!requireNamespace("geodata", quietly = TRUE))
    stop("Install `geodata` to download SoilGrids / WorldClim / SRTM.",
          call. = FALSE)
  schema <- match.arg(schema)

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  tag <- sprintf("cerrado_stack_%s_%s.tif",
                  schema,
                  digest::digest(c(bbox, target_res), algo = "md5"))
  stack_path <- file.path(cache_dir, tag)
  if (!force && file.exists(stack_path)) {
    # A CACHE ENTRY THAT VIOLATES ITS OWN KEY IS NOT A HIT.
    #
    # The build path below refuses to write a stack whose layer count does
    # not match the schema -- that guard was added after a partial network
    # failure produced a short stack. It does nothing for the stacks written
    # BEFORE it existed: the filename is keyed on (schema, bbox, resolution),
    # so a truncated file sitting at that path is returned for good, under an
    # informational message, to every caller that asks for the schema it
    # fails to satisfy.
    #
    # Reading the header is cheap -- terra::rast() on a path is lazy, so this
    # costs a header read, not a raster read -- and a mismatch falls through
    # to a rebuild rather than erroring, because a corrupt cache entry should
    # be replaced, not turned into a wall. If the sources are still
    # unreachable the build guard below reports exactly which layers are
    # missing, which is a better error than anything that could be raised
    # here.
    verdict <- .cached_stack_ok(stack_path, schema)
    if (isTRUE(verdict)) {
      message(sprintf("  Using cached stack: %s", stack_path))
      return(terra::rast(stack_path))
    }
    message(sprintf(paste("  Cached stack at %s does not satisfy schema '%s'",
                          "(%s); rebuilding."),
                    stack_path, schema, verdict))
  }

  message(sprintf("  Building Cerrado stack (schema = %s) ...", schema))

  ext_bbox <- terra::ext(bbox[1], bbox[3], bbox[2], bbox[4])
  template <- terra::rast(
    xmin = bbox[1], xmax = bbox[3],
    ymin = bbox[2], ymax = bbox[4],
    crs  = "EPSG:4326",
    resolution = target_res
  )

  layers <- list()

  # ---- 5 SoilGrids layers -------------------------------------------
  sg_vars <- c(soc = "soc", clay = "clay", sand = "sand",
                phh2o = "phh2o", bdod = "bdod")
  for (nm in names(sg_vars)) {
    message(sprintf("    SoilGrids  %s ...", nm))
    r <- tryCatch(
      geodata::soil_world(var = sg_vars[[nm]], depth = 5,
                           path = cache_dir),
      error = function(e) {
        warning(sprintf("layer fetch failed: %s", conditionMessage(e)),
                call. = FALSE); NULL
      })
    if (!is.null(r)) {
      r <- terra::crop(r, ext_bbox)
      r <- terra::resample(r, template, method = "bilinear")
      names(r) <- nm
      layers[[nm]] <- r
    }
  }

  if (schema == "v1_encoder") {
    # ---- 12 monthly WorldClim precip layers -------------------------
    message("    WorldClim  prec (12 monthly layers) ...")
    prec <- tryCatch(
      geodata::worldclim_country("BRA", var = "prec", path = cache_dir),
      error = function(e) {
        warning(sprintf("layer fetch failed: %s", conditionMessage(e)),
                call. = FALSE); NULL
      })
    if (!is.null(prec)) {
      prec <- terra::resample(terra::crop(prec, ext_bbox), template,
                                method = "bilinear")
      names(prec) <- sprintf("wc_prec_%02d", seq_len(terra::nlyr(prec)))
      for (i in seq_len(terra::nlyr(prec))) {
        layers[[names(prec)[i]]] <- prec[[i]]
      }
    }

    # ---- 12 monthly WorldClim tavg layers ---------------------------
    message("    WorldClim  tavg (12 monthly layers) ...")
    tavg <- tryCatch(
      geodata::worldclim_country("BRA", var = "tavg", path = cache_dir),
      error = function(e) {
        warning(sprintf("layer fetch failed: %s", conditionMessage(e)),
                call. = FALSE); NULL
      })
    if (!is.null(tavg)) {
      tavg <- terra::resample(terra::crop(tavg, ext_bbox), template,
                                method = "bilinear")
      names(tavg) <- sprintf("wc_tavg_%02d", seq_len(terra::nlyr(tavg)))
      for (i in seq_len(terra::nlyr(tavg))) {
        layers[[names(tavg)[i]]] <- tavg[[i]]
      }
    }
  } else {
    # legacy 10-channel "minimal" schema: bio1 + bio12 only
    message("    WorldClim  bio1, bio12 ...")
    bio <- tryCatch(
      geodata::worldclim_global(var = "bio", res = 10, path = cache_dir),
      error = function(e) {
        warning(sprintf("layer fetch failed: %s", conditionMessage(e)),
                call. = FALSE); NULL
      })
    if (!is.null(bio)) {
      b1  <- terra::resample(terra::crop(bio[[1]],  ext_bbox), template)
      b12 <- terra::resample(terra::crop(bio[[12]], ext_bbox), template)
      names(b1) <- "bio1"; names(b12) <- "bio12"
      layers$bio1  <- b1
      layers$bio12 <- b12
    }
  }

  # ---- 2 SRTM layers ------------------------------------------------
  message("    SRTM  elev + slope ...")
  elev <- tryCatch(
    geodata::elevation_30s(country = "BRA", path = cache_dir),
    error = function(e) {
      # elevation_30s can fail if country tile is unavailable; try
      # the global-coarse fallback so downstream code still has elev.
      tryCatch(
        geodata::elevation_global(res = 0.5, path = cache_dir),
        error = function(e2) {
          warning(sprintf("elevation fetch failed: %s",
                          conditionMessage(e2)), call. = FALSE); NULL
        })
    })
  if (!is.null(elev)) {
    e <- terra::resample(terra::crop(elev, ext_bbox), template)
    s <- terra::terrain(e, v = "slope", unit = "degrees")
    names(e) <- "elev"; names(s) <- "slope"
    layers$elev  <- e
    layers$slope <- s
  }

  if (schema == "minimal") {
    # legacy ndvi proxy for the 10-channel stack
    if (!is.null(layers$bio12) && !is.null(layers$bio1)) {
      ndvi_proxy <- (layers$bio12 / 3000) - (layers$bio1 / 300)
      ndvi_proxy <- terra::clamp(ndvi_proxy, 0, 1)
      names(ndvi_proxy) <- "ndvi"
      layers$ndvi <- ndvi_proxy
    }
  }

  if (length(layers) == 0L)
    stop("No layers could be built. Check network + geodata cache.",
          call. = FALSE)

  # Every source fetch above degrades to NULL on failure and is merely
  # skipped, so a partial network failure used to yield a silently
  # truncated stack that was then written to the schema-keyed cache and
  # reused for good.  A schema is a contract about channel count: assert
  # it before anything is cached.
  expected <- .stack_expected_layers(schema)
  if (terra::nlyr(stk_n <- terra::rast(layers)) != expected) {
    got <- names(layers)
    stop(sprintf(paste0(
      "schema '%s' requires %d layers but only %d could be built (%s).\n",
      "  Missing: %s\n",
      "  Nothing has been cached. Re-run when every source is reachable, ",
      "or pass schema = \"minimal\" for the 10-channel stack."),
      schema, expected, length(got), paste(got, collapse = ", "),
      paste(setdiff(.stack_layer_names(schema), got), collapse = ", ")),
      call. = FALSE)
  }

  # `do.call(c, layers)` falls through to base::c when terra isn't
  # attached.  `terra::rast(list_of_spatrasters)` is the canonical
  # multi-layer constructor and dispatches reliably.
  stk <- stk_n
  terra::writeRaster(stk, stack_path, overwrite = TRUE)
  message(sprintf("  Wrote %s (%.1f MB, %d layers)",
                   stack_path, file.size(stack_path) / 1024^2,
                   terra::nlyr(stk)))
  stk
}
