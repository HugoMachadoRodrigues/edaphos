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

#' Fetch a SoilGrids soil-property stack over an AoI
#'
#' Thin convenience wrapper around `geodata::soil_world()` that pulls
#' the listed variables, crops them to the area of interest, and
#' returns them as a single `terra::SpatRaster` with one layer per
#' variable. SoilGrids is **public and keyless** so no authentication
#' is required.
#'
#' The layers arrive at the resolution `geodata` serves, which is the
#' 30 arc-second (roughly 1 km) aggregation of SoilGrids, not the
#' native 250 m grid; the example prints `terra::res()` to show it.
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
#' @examples
#' \dontrun{
#' # A 2 x 2 degree window over the Brazilian Cerrado. The AoI is
#' # c(xmin, xmax, ymin, ymax) in WGS84 degrees -- not the
#' # c(north, west, south, east) that Copernicus and NASA services use.
#' aoi <- c(-50, -48, -16, -14)
#'
#' soil <- foundation_tile_source_soilgrids(
#'   variables = c("soc", "clay", "phh2o"),
#'   depth = "0-5cm", stat = "mean", aoi = aoi,
#'   path = tools::R_user_dir("edaphos", "cache")
#' )
#' names(soil)   # one layer per variable, prefixed "soilgrids_"
#'
#' # `depth` is normalised internally, so the documented string form and
#' # geodata's own integer upper bound in centimetres are one request:
#' by_string  <- foundation_tile_source_soilgrids("soc", depth = "0-5cm",
#'                                                  aoi = aoi)
#' by_integer <- foundation_tile_source_soilgrids("soc", depth = 5,
#'                                                  aoi = aoi)
#'
#' # Anything outside the six standard intervals is rejected before a
#' # single byte is downloaded, and the message names all six:
#' foundation_tile_source_soilgrids("soc", depth = "0-10cm", aoi = aoi)
#' ## Error: Unknown depth string '0-10cm'. Use one of: 0-5cm, 5-15cm,
#' ##   15-30cm, 30-60cm, 60-100cm, 100-200cm (or an integer in
#' ##   c(5, 15, 30, 60, 100, 200)).
#'
#' # Two limits this wrapper cannot check for you, because they belong
#' # to geodata::soil_world(): `variables` must be one of bdod, cfvo,
#' # clay, nitrogen, ocd, ocs, phh2o, sand, silt, soc, wrb; and geodata's
#' # own help notes that only stat = "mean" down to 60 cm is currently
#' # served, so the quantile statistics and the two deepest intervals
#' # fail at download time rather than at argument checking.
#'
#' # geodata serves the 30 arc-second aggregation of SoilGrids, not the
#' # native 250 m grid, so read the realised cell size off the result
#' # rather than trusting the "250 m" in the product's name. Aligning
#' # these layers onto a 250 m grid resamples; it does not restore
#' # detail that was never downloaded.
#' terra::res(soil)   # ~0.008333 degrees = 30 arc-seconds, roughly 1 km
#'
#' # `path` is geodata's download cache, not scratch space. The default
#' # tempdir() dies with the session, so every new R process re-fetches
#' # the whole global mosaic before cropping to `aoi`.
#' }
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
  # `geodata::soil_world()` expects `depth` as an integer (the upper
  # depth bound in centimetres: one of 5, 15, 30, 60, 100, 200). This
  # wrapper accepts either that integer form *or* the human-readable
  # `"0-5cm"`-style string documented in the @param block above and
  # normalises it on the fly.
  if (is.character(depth)) {
    depth_map <- c("0-5cm" = 5L, "5-15cm" = 15L, "15-30cm" = 30L,
                    "30-60cm" = 60L, "60-100cm" = 100L,
                    "100-200cm" = 200L)
    if (!depth %in% names(depth_map)) {
      stop("Unknown depth string '", depth,
           "'. Use one of: ", paste(names(depth_map), collapse = ", "),
           " (or an integer in c(5, 15, 30, 60, 100, 200)).",
           call. = FALSE)
    }
    depth <- unname(depth_map[[depth]])
  }
  depth <- as.integer(depth)
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
#' @examples
#' \dontrun{
#' aoi <- c(-50, -48, -16, -14)
#'
#' # Country scope: geodata downloads the whole of Brazil at 30
#' # arc-seconds and the crop to `aoi` only happens afterwards, so a
#' # small AoI does not buy a small download.
#' clim <- foundation_tile_source_worldclim(
#'   variables = c("prec", "tavg"), country = "BRA", aoi = aoi,
#'   path = tools::R_user_dir("edaphos", "cache")
#' )
#'
#' # Every monthly WorldClim variable is a 12-layer raster, so the two
#' # variables above give 24 channels, not 2. Check this before the
#' # stack reaches foundation_tile_dataset(): the channel count is what
#' # the encoder's first convolution must match.
#' terra::nlyr(clim)   # 24
#' names(clim)   # wc_prec_01 ... wc_prec_12, wc_tavg_01 ... wc_tavg_12
#' terra::res(clim)    # country scope is always 30 arc-seconds,
#'                     # i.e. ~0.008333 degrees; `res` never enters it
#'
#' # `res` is ignored while `country` is non-NULL. Pass country = NULL
#' # for the global product, which is the right choice when the AoI
#' # crosses a border -- worldclim_country() returns one country only.
#' bio <- foundation_tile_source_worldclim(
#'   variables = "bio", country = NULL, res = 2.5, aoi = aoi
#' )
#'
#' # `bio` is not monthly, so it does not follow the 12-layer rule --
#' # print its channel count instead of assuming one:
#' terra::nlyr(bio)    # 19 bioclimatic variables, named wc_bio_01..19
#'
#' # geodata documents its own `var` argument as one of tmin, tmax,
#' # tavg, prec, wind, vapr, bio. The "elev" and "srad" entries listed
#' # among `variables` above are outside that documented set, although
#' # geodata's stopifnot() does accept them. "elev" in particular is a
#' # single-band product, so it breaks the layer arithmetic above --
#' # again, count, do not assume:
#' el <- foundation_tile_source_worldclim(variables = "elev",
#'                                        country = "BRA", aoi = aoi)
#' terra::nlyr(el)
#'
#' # WorldClim 2.1 is a 1970-2000 climate normal, not a time series.
#' # Stacking it beside a 2020 vegetation composite gives channels that
#' # describe different decades: acceptable for self-supervised
#' # pretraining, wrong for any statement about a particular year.
#' }
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
#' @examples
#' \dontrun{
#' aoi <- c(-50, -48, -16, -14)
#'
#' topo <- foundation_tile_source_srtm(
#'   aoi = aoi, derive = c("slope", "TPI"), country = "BRA",
#'   path = tools::R_user_dir("edaphos", "cache")
#' )
#' names(topo)   # "elev" "slope" "TPI"
#'
#' # `country` picks which national tile geodata fetches and the crop to
#' # `aoi` happens afterwards, so the default "BRA" is wrong the moment
#' # the AoI leaves Brazil. The failure comes from terra, not from a
#' # helpful check: "[crop] extents do not overlap".
#' foundation_tile_source_srtm(aoi = c(30, 32, -2, 0), country = "KEN")
#'
#' # geodata::elevation_30s() masks to the country border by default and
#' # this wrapper does not expose that argument, so an AoI straddling a
#' # border comes back NA on the foreign side.
#' terra::global(topo, "isNA")
#'
#' # Every entry of `derive` goes through terra::terrain(), which needs a
#' # full 3 x 3 neighbourhood, so each derived layer is NA on the outer
#' # ring of the tile even where `elev` is present.
#' # foundation_tile_dataset() imputes those NAs to the layer mean
#' # without warning -- crop with a margin if that matters to you.
#'
#' # `unit = "degrees"` is passed for every derived layer but only
#' # affects "slope" and "aspect"; TPI, TRI and roughness stay in the
#' # units of `elev`.
#'
#' # elevation_30s() is the 30 arc-SECOND (roughly 1 km) aggregation of
#' # the 90 m CGIAR-SRTM, not a 30 m product -- the cell size says so:
#' terra::res(topo)   # ~0.008333 degrees = 30 arc-seconds, roughly 1 km
#' # Slope computed from that is a kilometre-scale gradient and will not
#' # match a slope map derived from a fine LiDAR DEM over the same field.
#' }
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
#' @examples
#' \dontrun{
#' # The stub always errors, whatever you pass it. It exists so that
#' # downstream code has one canonical MODIS entry point to name.
#' foundation_tile_source_modis()
#'
#' # The supported route is to pre-process outside edaphos -- MODIStsp,
#' # rgee or the AppEEARS service all work -- write a GeoTIFF mosaic,
#' # and read it back with terra. Nothing downstream cares where a
#' # raster came from.
#' ndvi <- terra::rast("modis/MOD13Q1_NDVI_2020_cerrado.tif")
#'
#' # MOD13Q1 stores NDVI as int16 with a 1e-4 scale factor and -3000 as
#' # the fill value, and both survive terra::rast() untouched. Drop the
#' # fill and rescale before stacking, otherwise the "ndvi" channel is a
#' # mixture of index values and sentinels.
#' ndvi[ndvi < -2000] <- NA
#' ndvi <- ndvi * 1e-4
#' names(ndvi) <- "ndvi"
#'
#' aoi  <- c(-50, -48, -16, -14)
#' soil <- foundation_tile_source_soilgrids(variables = "soc", aoi = aoi)
#' stack <- foundation_tile_align(list(soil = soil, modis = ndvi),
#'                                  target_res = 0.0025, aoi = aoi)
#' ds <- foundation_tile_dataset(stack, patch_size = 32L,
#'                                 n_patches = 5000L, seed = 1L)
#'
#' # A 16-day composite is not a snapshot: neighbouring pixels of
#' # MOD13Q1 can come from different days. Treat it as one channel of a
#' # pretraining stack, not as a same-date observation of the soil.
#' }
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
#' @examples
#' \dontrun{
#' # The stub always errors; it is a signpost, not an implementation.
#' foundation_tile_source_era5()
#'
#' # Supported route: register at the Copernicus Climate Data Store,
#' # store the key once, request the NetCDF, then convert.
#' ecmwfr::wf_set_key(key = "your-cds-personal-access-token")
#' req <- list(
#'   dataset_short_name = "reanalysis-era5-land-monthly-means",
#'   product_type       = "monthly_averaged_reanalysis",
#'   variable = c("2m_temperature", "total_evaporation"),
#'   year = "2020", month = sprintf("%02d", 1:12), time = "00:00",
#'   # The CDS bounding box is north, west, south, east -- the reverse
#'   # convention to the c(xmin, xmax, ymin, ymax) that every
#'   # foundation_tile_* function in this package expects.
#'   area = c(-14, -50, -16, -48),
#'   format = "netcdf",
#'   target = "era5_land_cerrado_2020.nc"
#' )
#' ecmwfr::wf_request(req, path = tempdir())
#' era5 <- terra::rast(file.path(tempdir(), "era5_land_cerrado_2020.nc"))
#'
#' aoi  <- c(-50, -48, -16, -14)
#' soil <- foundation_tile_source_soilgrids(variables = "soc", aoi = aoi)
#' stack <- foundation_tile_align(list(soil = soil, era5 = era5),
#'                                  target_res = 0.0025, aoi = aoi)
#'
#' # ERA5-Land is a 0.1 degree (roughly 9 km) reanalysis -- confirm on
#' # the object you actually downloaded rather than taking it on trust:
#' terra::res(era5)
#' # Projected onto a 250 m grid with the default bilinear method it
#' # becomes a smooth channel carrying no information below 9 km. That
#' # is harmless for a contrastive encoder and misleading in a
#' # covariate-importance table.
#' }
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
#' @examples
#' if (requireNamespace("terra", quietly = TRUE)) {
#'   # Two Cerrado covariates on deliberately mismatched grids: soil at
#'   # 0.05 degrees, terrain at 0.10, on extents that only partly
#'   # overlap.
#'   set.seed(1)
#'   soc <- terra::rast(nrows = 40, ncols = 40,
#'                      xmin = -50, xmax = -48, ymin = -16, ymax = -14,
#'                      crs = "EPSG:4326")
#'   terra::values(soc) <- stats::rnorm(terra::ncell(soc), 22, 4)
#'   names(soc) <- "soc"
#'
#'   elev <- terra::rast(nrows = 20, ncols = 20,
#'                       xmin = -49.5, xmax = -47.5,
#'                       ymin = -15.5, ymax = -13.5, crs = "EPSG:4326")
#'   terra::values(elev) <- stats::rnorm(terra::ncell(elev), 900, 80)
#'   names(elev) <- "elev"
#'
#'   fused <- foundation_tile_align(list(soil = soc, topo = elev),
#'                                    target_res = 0.05)
#'   print(terra::res(fused))    # both sources now on the 0.05 grid
#'   print(names(fused))         # names come from the rasters, not from
#'                               # the names of `sources`
#'
#'   # The template is the UNION of the source extents, not their
#'   # intersection, so each layer is NA wherever its own source did not
#'   # reach -- 36 percent of the grid here, for both layers.
#'   print(terra::global(fused, "isNA") / terra::ncell(fused))
#'
#'   # `aoi` cuts the template back to ground both sources cover, and
#'   # that is what removes the NA frame.
#'   inner <- foundation_tile_align(list(soil = soc, topo = elev),
#'                                    target_res = 0.05,
#'                                    aoi = c(-49.5, -48, -15.5, -14))
#'   print(terra::global(inner, "isNA"))
#'
#'   # Mixed CRS is handled, but the union is taken AFTER reprojection.
#'   # A UTM 23S tile several degrees east of the soil tile produces a
#'   # mosaic that is 73 and 98 percent NA -- and a contrastive encoder
#'   # will train on it perfectly happily.
#'   utm <- terra::rast(nrows = 30, ncols = 30,
#'                      xmin = 700000, xmax = 760000,
#'                      ymin = 8250000, ymax = 8310000,
#'                      crs = "EPSG:31983")
#'   terra::values(utm) <- stats::rnorm(terra::ncell(utm), 14, 3)
#'   names(utm) <- "clay"
#'   far <- foundation_tile_align(list(soil = soc, clay = utm),
#'                                  target_res = 0.05)
#'   print(dim(far))
#'   print(round(terra::global(far, "isNA") / terra::ncell(far), 2))
#'
#'   # `target_res` is in the units of `target_crs`. The 0.005 default is
#'   # degrees; carrying it over to a metre-based CRS asks for 5 mm
#'   # cells. Give metres -- and read the realised resolution off the
#'   # result, because terra fits a whole number of cells into the
#'   # extent instead of honouring `target_res` exactly.
#'   polyconic <- foundation_tile_align(list(soil = soc),
#'                                        target_res = 5000,
#'                                        target_crs = "EPSG:5880")
#'   print(terra::res(polyconic))   # near 5000 m, not exactly 5000
#'
#'   # Two sources that each carry a layer called "soc" give a stack with
#'   # two layers called "soc", and [["soc"]] then returns both of them
#'   # with only a warning. Rename before aligning, not after.
#'   dup <- foundation_tile_align(list(a = soc, b = soc), target_res = 0.05)
#'   print(names(dup))                  # "soc" "soc"
#'   print(terra::nlyr(dup[["soc"]]))   # 2, after a warning that reads
#'                                      # "[subset] using a name that is
#'                                      # not unique"
#'
#'   # method = "bilinear" is for continuous covariates. Use "near" for
#'   # anything categorical -- interpolating soil-class codes invents
#'   # classes that do not exist.
#' }
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
#' @examples
#' if (requireNamespace("terra", quietly = TRUE)) {
#'   data(br_cerrado, package = "edaphos")
#'   # br_cerrado is a complete 45 x 45 grid, so it converts straight to
#'   # a SpatRaster; x and y have to be the first two columns.
#'   cerr <- terra::rast(br_cerrado[, c("x", "y", "soc", "elev", "twi")],
#'                       type = "xyz", crs = "EPSG:4326")
#'
#'   ds <- foundation_tile_dataset(cerr, patch_size = 8L,
#'                                   n_patches = 200L, seed = 1L)
#'   print(ds)
#'   # (B, C, H, W) -- channel-first, the layout torch conv layers want.
#'   print(dim(ds$sample(batch_size = 4L)))
#'
#'   # Normalisation uses GLOBAL raster statistics computed once at
#'   # construction, never per-batch ones. They are the column statistics
#'   # of the source table -- to floating-point tolerance, not bit for
#'   # bit, because terra accumulates in a different order:
#'   print(c(ds$means[1], mean(br_cerrado$soc)))
#'   print(c(ds$sds[1], stats::sd(br_cerrado$soc)))
#'   print(isTRUE(all.equal(ds$means[1], mean(br_cerrado$soc))))    # TRUE
#'   print(identical(ds$means[1], mean(br_cerrado$soc)))            # FALSE
#'
#'   # `seed` fixes WHICH patches the dataset owns, not which ones a
#'   # call draws. Two datasets built with the same seed agree on
#'   # patch_cells and still disagree on their batches, so seed the RNG
#'   # immediately before sample() when you need a reproducible batch.
#'   d2 <- foundation_tile_dataset(cerr, patch_size = 8L,
#'                                   n_patches = 200L, seed = 1L)
#'   print(identical(ds$patch_cells, d2$patch_cells))   # TRUE
#'   print(identical(ds$sample(4L), d2$sample(4L)))     # FALSE
#'   set.seed(99); b1 <- ds$sample(4L)
#'   set.seed(99); b2 <- d2$sample(4L)
#'   print(identical(b1, b2))                           # TRUE
#'
#'   # normalise = FALSE returns raw units, which is what you want when
#'   # inspecting a patch and not what you want in a contrastive loss:
#'   # elevation in metres would swamp TWI.
#'   raw <- foundation_tile_dataset(cerr, patch_size = 8L,
#'                                    n_patches = 200L, normalise = FALSE,
#'                                    seed = 1L)
#'   set.seed(7); print(round(apply(raw$sample(8L), 2, mean), 2))
#'   set.seed(7); print(round(apply(ds$sample(8L),  2, mean), 2))
#'
#'   # Patch CENTRES must sit at least patch_size %/% 2 cells from every
#'   # edge, so a large patch on a small grid leaves very few of them.
#'   # On 45 x 45 with patch_size = 40 only rows and columns 21 to 25
#'   # qualify -- 25 centres -- and n_patches = 200 is then drawn WITH
#'   # replacement. The dataset reports 200 patches and owns 25 windows.
#'   crowded <- foundation_tile_dataset(cerr, patch_size = 40L,
#'                                        n_patches = 200L, seed = 1L)
#'   print(crowded$n_patches)                          # 200 reported
#'   print(length(unique(crowded$patch_cells)))        # 25 distinct
#'   print(apply(terra::rowColFromCell(cerr,
#'                                     unique(crowded$patch_cells)),
#'               2, range))                            # rows/cols 21..25
#'
#'   # Ask for a patch the grid cannot hold at all and it is an error,
#'   # not a silent shrink.
#'   try(foundation_tile_dataset(cerr, patch_size = 46L, n_patches = 10L))
#'
#'   # A valid_mask restricts eligible centres -- here to the cells above
#'   # mean TWI, which is a bit over half the grid, not exactly half. It
#'   # is resampled onto the stack with method "near", so a coarser mask
#'   # is allowed.
#'   wet <- cerr[["twi"]] > terra::global(cerr[["twi"]], "mean")[1, 1]
#'   print(mean(terra::values(wet)[, 1]))   # fraction of cells kept
#'   dw <- foundation_tile_dataset(cerr, patch_size = 8L, n_patches = 100L,
#'                                   valid_mask = wet, seed = 1L)
#'   print(all(terra::values(wet)[dw$patch_cells, 1] > 0))
#'
#'   # Only the FIRST layer decides eligibility. A gap in any other
#'   # channel is invisible to the sampler; those cells are imputed to
#'   # the channel mean instead, which after normalisation is an exact
#'   # zero. Put the layer with the honest coverage first.
#'   gappy <- cerr
#'   v <- terra::values(gappy[[2]]); v[1:900] <- NA   # the top 20 rows
#'   terra::values(gappy[[2]]) <- v
#'   dg <- foundation_tile_dataset(gappy, patch_size = 8L,
#'                                   n_patches = 200L, seed = 1L)
#'   print(identical(dg$patch_cells, ds$patch_cells))   # TRUE
#'   # Numerator and denominator, plus the gap-free control that shows
#'   # the zeros are imputation and not coincidence:
#'   set.seed(5); print(sum(dg$sample(16L)[, 2, , ] == 0))   # hundreds
#'   print(16L * 8L * 8L)                                    # of 1024
#'   set.seed(5); print(sum(ds$sample(16L)[, 2, , ] == 0))   # 0
#'
#'   # batch_size is capped by n_patches, not by memory.
#'   try(ds$sample(batch_size = 1000L))
#' }
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
