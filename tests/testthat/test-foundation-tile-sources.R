# Tests for the five foundation_tile_source_* entry points in
# R/foundation_tiles.R.
#
# WHY THIS FILE EXISTS
# --------------------
# These five functions had no test coverage at all. test-foundation-tiles.R
# exercises foundation_tile_dataset(), foundation_tile_align() and the MoCo
# loop, and stops there -- no test in the package referenced
# foundation_tile_source_soilgrids(), _worldclim(), _srtm(), _modis() or
# _era5().
#
# Their only worked examples are wrapped in \dontrun{}, and a \dontrun example
# is documentation, not a check: R CMD check never runs it, so nothing verified
# that the behaviour it describes still holds. Those examples make specific,
# falsifiable claims -- that "0-5cm" and the integer 5 are the same request,
# that an unknown depth is rejected "before a single byte is downloaded", that
# `res` is ignored while `country` is non-NULL, that WorldClim layers come back
# named wc_prec_01, that derived terrain layers are in degrees. Each of those
# is asserted below.
#
# NOTHING HERE TOUCHES THE NETWORK
# --------------------------------
# Every geodata entry point is replaced for the duration of each test by
# local_geodata() below, which installs mocks for all four download functions.
# Any function not explicitly overridden becomes a TRIPWIRE that errors with
# "NETWORK GUARD". That is deliberate: if a regression removes an argument
# check or an install guard, the test fails loudly on the tripwire instead of
# quietly reaching for SoilGrids.

skip_tiles <- function() {
  skip_if_not_installed("terra")
  skip_if_not_installed("geodata")
}

# A raster comfortably larger than the AoI used throughout, so terra::crop()
# always has something to cut.
aoi_cerrado <- c(-50, -48, -16, -14)

fake_stack <- function(n = 1L) {
  r <- terra::rast(nrows = 60, ncols = 60, nlyrs = n,
                   xmin = -52, xmax = -46, ymin = -18, ymax = -12,
                   crs = "EPSG:4326")
  terra::values(r) <- seq_len(terra::ncell(r) * n)
  r
}

# Install mocks for every geodata download function. Anything not named in
# `...` errors instead of downloading.
local_geodata <- function(..., .env = parent.frame()) {
  boom <- function(...) {
    stop("NETWORK GUARD: a geodata download was attempted", call. = FALSE)
  }
  mocks <- list(soil_world = boom, worldclim_country = boom,
                worldclim_global = boom, elevation_30s = boom)
  overrides <- list(...)
  mocks[names(overrides)] <- overrides
  do.call(testthat::local_mocked_bindings,
          c(mocks, list(.package = "geodata", .env = .env)))
}

# Make requireNamespace() report the named packages as absent, so the install
# guards can be exercised on a machine where they are in fact installed. The
# real function is captured before the mock is installed, so delegation for
# every other package does not recurse.
local_pkg_absent <- function(absent, .env = parent.frame()) {
  real_require <- base::requireNamespace
  testthat::local_mocked_bindings(
    requireNamespace = function(package, ...) {
      if (package %in% absent) return(FALSE)
      real_require(package, ...)
    },
    .package = "base",
    .env = .env
  )
}

# Capture an error object, asserting that one was actually raised.
err_of <- function(expr) {
  e <- tryCatch(expr, error = function(e) e)
  expect_s3_class(e, "error")
  e
}


# ---- MODIS and ERA5 stubs ---------------------------------------------------
# These two are pure: they take `...`, ignore it, and always stop. That makes
# them fully testable offline, and the thing worth testing is that the error
# still names the supported route -- the message IS the feature.

test_that("foundation_tile_source_modis always errors and names the supported route", {
  e <- err_of(foundation_tile_source_modis())
  msg <- conditionMessage(e)

  expect_match(msg, "MODIS ingestion requires NASA EarthData credentials",
               fixed = TRUE)
  # The three signposts the docs promise: two clients and the escape hatch.
  expect_match(msg, "MODIStsp", fixed = TRUE)
  expect_match(msg, "rgee", fixed = TRUE)
  expect_match(msg, "foundation_tile_align()", fixed = TRUE)
  # stop(call. = FALSE): a user-facing signpost should not print the internals.
  expect_null(conditionCall(e))
})

test_that("foundation_tile_source_era5 always errors and names the Copernicus route", {
  e <- err_of(foundation_tile_source_era5())
  msg <- conditionMessage(e)

  expect_match(msg, "ERA5 ingestion requires a Copernicus Climate Data Store API key",
               fixed = TRUE)
  expect_match(msg, "ecmwfr", fixed = TRUE)
  expect_match(msg, "wf_set_key()", fixed = TRUE)
  expect_match(msg, "wf_request()", fixed = TRUE)
  expect_match(msg, "foundation_tile_align()", fixed = TRUE)
  expect_null(conditionCall(e))
})

test_that("the stubs ignore their arguments rather than dispatching on them", {
  # `@param ... Ignored` -- a plausible half-implementation would start
  # branching on aoi/variables and let some argument combination through
  # (or fail with a different error, e.g. "unused argument").
  args <- list(
    list(),
    list(aoi = aoi_cerrado),
    list(variables = "NDVI", aoi = aoi_cerrado, path = tempdir()),
    list(NULL),
    list(1, 2, 3)
  )
  for (a in args) {
    expect_match(conditionMessage(err_of(do.call(foundation_tile_source_modis, a))),
                 "MODIS ingestion requires", fixed = TRUE)
    expect_match(conditionMessage(err_of(do.call(foundation_tile_source_era5, a))),
                 "ERA5 ingestion requires", fixed = TRUE)
  }
})

test_that("the stubs signpost without first demanding terra or geodata", {
  # A signpost must work on a bare install. If someone adds
  # .tiles_require_terra() to these stubs, a user with neither package gets
  # "install terra" instead of being told how to get MODIS data at all.
  local_pkg_absent(c("terra", "geodata"))

  expect_match(conditionMessage(err_of(foundation_tile_source_modis())),
               "MODIS ingestion requires", fixed = TRUE)
  expect_match(conditionMessage(err_of(foundation_tile_source_era5())),
               "ERA5 ingestion requires", fixed = TRUE)
})


# ---- AoI coercion, reached through the public functions ---------------------

test_that("a malformed AoI is rejected before any download is attempted", {
  skip_tiles()
  local_geodata()   # every download function is a tripwire

  # NB: a 2 x 2 numeric matrix is deliberately NOT in this list -- it satisfies
  # is.numeric() && length() == 4 and is accepted, which is existing (harmless)
  # behaviour, not a bug to pin.
  bad <- list(
    "cerrado",                              # character
    c("-50", "-48", "-16", "-14"),          # right length, wrong type
    c(-50, -48, -16),                       # length 3, not 4
    c(-50, -48, -16, -14, -12),             # length 5
    list(xmin = -50, xmax = -48, ymin = -16, ymax = -14),  # plain list
    NULL
  )

  for (a in bad) {
    for (call_it in list(
      function(x) foundation_tile_source_soilgrids("soc", aoi = x),
      function(x) foundation_tile_source_worldclim("prec", country = "BRA", aoi = x),
      function(x) foundation_tile_source_srtm(aoi = x)
    )) {
      msg <- conditionMessage(err_of(call_it(a)))
      # The AoI check must be what fired -- not the tripwire, which would
      # mean a bad extent had already been handed to a download.
      expect_match(msg, "Unsupported AoI", fixed = TRUE)
      expect_match(msg, "c(xmin, xmax, ymin, ymax)", fixed = TRUE)
    }
  }
})

test_that("the numeric, SpatExtent and sf-bbox spellings of an AoI agree", {
  skip_tiles()
  skip_if_not_installed("sf")
  local_geodata(soil_world = function(...) fake_stack(1L))

  by_numeric <- foundation_tile_source_soilgrids("soc", aoi = aoi_cerrado)
  by_extent  <- foundation_tile_source_soilgrids(
    "soc", aoi = terra::ext(-50, -48, -16, -14))
  # st_bbox stores xmin, ymin, xmax, ymax -- a DIFFERENT order from the
  # c(xmin, xmax, ymin, ymax) the numeric branch takes. .tiles_coerce_ext()
  # indexes the bbox by name for exactly that reason; positional indexing
  # would silently produce ext(-50, -16, -48, -14) here.
  by_bbox <- foundation_tile_source_soilgrids(
    "soc", aoi = sf::st_bbox(c(xmin = -50, ymin = -16, xmax = -48, ymax = -14),
                             crs = sf::st_crs(4326)))

  expect_equal(unname(as.vector(terra::ext(by_extent))),
               unname(as.vector(terra::ext(by_numeric))))
  expect_equal(unname(as.vector(terra::ext(by_bbox))),
               unname(as.vector(terra::ext(by_numeric))))
  # And the crop actually happened: the AoI is a ninth of the fake raster's
  # 6 x 6 degree span, so a no-op crop would leave a much bigger extent.
  # fake_stack() is 60 x 60 over 6 degrees, so 0.1-degree cell edges fall
  # exactly on the AoI and terra::crop() has nothing to snap outward to.
  expect_equal(unname(as.vector(terra::ext(by_numeric))), c(-50, -48, -16, -14))
})


# ---- SoilGrids: depth normalisation -----------------------------------------

test_that("every documented depth string maps to geodata's integer upper bound", {
  skip_tiles()
  # An off-by-one or copy-paste slip in depth_map is invisible at runtime --
  # it just downloads the wrong horizon -- so pin all six pairs.
  expected <- c("0-5cm" = 5L, "5-15cm" = 15L, "15-30cm" = 30L,
                "30-60cm" = 60L, "60-100cm" = 100L, "100-200cm" = 200L)

  for (nm in names(expected)) {
    seen <- new.env(parent = emptyenv())
    local_geodata(soil_world = function(...) {
      seen$args <- list(...)
      fake_stack(1L)
    })
    foundation_tile_source_soilgrids("soc", depth = nm, aoi = aoi_cerrado)
    expect_identical(seen$args$depth, expected[[nm]],
                     info = paste("depth =", nm))
  }
})

test_that("the string and integer spellings of depth are the same request", {
  skip_tiles()
  capture_depth <- function(d) {
    seen <- new.env(parent = emptyenv())
    local_geodata(soil_world = function(...) {
      seen$args <- list(...)
      fake_stack(1L)
    })
    out <- foundation_tile_source_soilgrids("soc", depth = d, aoi = aoi_cerrado)
    list(args = seen$args, names = names(out))
  }

  by_string  <- capture_depth("0-5cm")
  by_double  <- capture_depth(5)
  by_integer <- capture_depth(5L)

  # geodata::soil_world() builds its filename from `depth`, so the type
  # matters, not just the value: as.integer() must survive the string branch.
  expect_identical(by_string$args$depth, 5L)
  expect_identical(by_double$args$depth, 5L)
  expect_identical(by_integer$args$depth, 5L)
  # Nothing else about the request differs between the spellings.
  expect_identical(by_string$args, by_integer$args)
  expect_identical(by_string$names, by_integer$names)
})

test_that("an unknown depth is rejected before the AoI is even evaluated", {
  skip_tiles()
  local_geodata()   # tripwires: reaching a download here is a failure

  # `aoi` has no default. R's lazy evaluation means this call only succeeds in
  # raising the DEPTH error if the depth check runs before .tiles_coerce_ext()
  # forces `aoi`. Move the coercion above the depth block and this becomes
  # 'argument "aoi" is missing, with no default'.
  msg <- conditionMessage(err_of(
    foundation_tile_source_soilgrids("soc", depth = "0-10cm")))

  expect_match(msg, "Unknown depth string '0-10cm'", fixed = TRUE)
  expect_false(grepl("aoi", msg, fixed = TRUE))
  expect_false(grepl("NETWORK GUARD", msg, fixed = TRUE))

  # The message enumerates all six intervals -- the docs promise it "names all
  # six", and a hand-written list drifts from depth_map the moment one changes.
  for (nm in c("0-5cm", "5-15cm", "15-30cm", "30-60cm", "60-100cm", "100-200cm")) {
    expect_match(msg, nm, fixed = TRUE)
  }
  # ...and points at the integer alternative.
  expect_match(msg, "(or an integer in c(5, 15, 30, 60, 100, 200))", fixed = TRUE)
})

test_that("depths outside the six standard intervals are all rejected", {
  skip_tiles()
  local_geodata()
  for (d in c("0-10cm", "5cm", "0-5", "0-5CM", "", "200-300cm")) {
    expect_match(conditionMessage(err_of(
      foundation_tile_source_soilgrids("soc", depth = d, aoi = aoi_cerrado))),
      "Unknown depth string", fixed = TRUE)
  }
})


# ---- SoilGrids: request pass-through and layer naming -----------------------

test_that("soilgrids forwards var/stat/path unchanged and prefixes each layer", {
  skip_tiles()
  seen <- new.env(parent = emptyenv())
  seen$calls <- list()
  cache <- file.path(tempdir(), "edaphos-tile-cache")
  local_geodata(soil_world = function(...) {
    seen$calls[[length(seen$calls) + 1L]] <- list(...)
    fake_stack(1L)
  })

  out <- foundation_tile_source_soilgrids(
    variables = c("soc", "clay", "phh2o"),
    depth = "5-15cm", stat = "Q0.5", aoi = aoi_cerrado, path = cache
  )

  # One download per variable, in the order asked for.
  expect_length(seen$calls, 3L)
  expect_equal(vapply(seen$calls, function(x) x$var, character(1)),
               c("soc", "clay", "phh2o"))
  # `stat` and `path` are forwarded, not quietly replaced by the defaults.
  # (`path` in particular is geodata's download cache; ignoring it would send
  # every request back to tempdir() and re-fetch the global mosaic each time.)
  for (cl in seen$calls) {
    expect_identical(cl$stat, "Q0.5")
    expect_identical(cl$path, cache)
    expect_identical(cl$depth, 15L)
  }

  # One layer per variable, prefixed, in request order.
  expect_s4_class(out, "SpatRaster")
  expect_equal(terra::nlyr(out), 3L)
  expect_equal(names(out), c("soilgrids_soc", "soilgrids_clay", "soilgrids_phh2o"))
})


# ---- WorldClim: scope dispatch ----------------------------------------------

test_that("a non-NULL country uses worldclim_country and never passes res", {
  skip_tiles()
  seen <- new.env(parent = emptyenv())
  # worldclim_global stays a tripwire: if the branch inverts, this fails.
  local_geodata(worldclim_country = function(...) {
    seen$args <- list(...)
    fake_stack(12L)
  })

  foundation_tile_source_worldclim("prec", country = "BRA", res = 10,
                                   aoi = aoi_cerrado, path = tempdir())

  expect_identical(seen$args[[1L]], "BRA")   # country passed positionally
  expect_identical(seen$args$var, "prec")
  expect_identical(seen$args$path, tempdir())
  # The docs are explicit that `res` is ignored under country scope. If it
  # leaked through it would land in worldclim_country's `version` argument.
  expect_null(seen$args$res)
  expect_length(seen$args, 3L)
})

test_that("country = NULL uses worldclim_global and forwards res", {
  skip_tiles()
  seen <- new.env(parent = emptyenv())
  # worldclim_country stays a tripwire.
  local_geodata(worldclim_global = function(...) {
    seen$args <- list(...)
    fake_stack(19L)
  })

  out <- foundation_tile_source_worldclim("bio", country = NULL, res = 2.5,
                                          aoi = aoi_cerrado)

  expect_identical(seen$args$var, "bio")
  expect_identical(seen$args$res, 2.5)
  expect_null(seen$args$country)
  # bio is not monthly: the naming must follow the layer count, not a
  # hard-coded 12.
  expect_equal(terra::nlyr(out), 19L)
  expect_equal(names(out)[c(1L, 19L)], c("wc_bio_01", "wc_bio_19"))
})

test_that("worldclim names layers wc_<var>_<nn> with a zero-padded index", {
  skip_tiles()
  local_geodata(worldclim_country = function(...) fake_stack(12L))

  out <- foundation_tile_source_worldclim(c("prec", "tavg"), country = "BRA",
                                          aoi = aoi_cerrado)

  # Two monthly variables are 24 channels, not 2 -- the count the encoder's
  # first convolution has to match.
  expect_equal(terra::nlyr(out), 24L)
  expect_equal(names(out),
               c(paste0("wc_prec_", sprintf("%02d", 1:12)),
                 paste0("wc_tavg_", sprintf("%02d", 1:12))))
  # sprintf("%d") instead of "%02d" would give wc_prec_1, which sorts wrongly
  # and contradicts the documented names.
  expect_true(all(grepl("_(0[1-9]|1[0-2])$", names(out))))
})

test_that("a single-band worldclim product still gets a _01 suffix", {
  skip_tiles()
  local_geodata(worldclim_country = function(...) fake_stack(1L))

  out <- foundation_tile_source_worldclim("elev", country = "BRA",
                                          aoi = aoi_cerrado)
  expect_equal(terra::nlyr(out), 1L)
  expect_equal(names(out), "wc_elev_01")
})


# ---- SRTM -------------------------------------------------------------------

# A synthetic east-west elevation ramp -- deliberately steeper than real
# terrain, so terrain() has a gradient large enough that degrees and radians
# cannot be confused. Same 60 x 60 / 6-degree geometry as fake_stack(), so the
# 0.1-degree cell edges line up with the AoI and crop() need not snap outward.
fake_elev <- function(step = 2000) {
  r <- terra::rast(nrows = 60, ncols = 60,
                   xmin = -52, xmax = -46, ymin = -18, ymax = -12,
                   crs = "EPSG:4326")
  terra::values(r) <- rep(seq(0, by = step, length.out = 60), times = 60)
  r
}

test_that("srtm forwards country and stacks elev first, then derived layers in order", {
  skip_tiles()
  seen <- new.env(parent = emptyenv())
  local_geodata(elevation_30s = function(...) {
    seen$args <- list(...)
    fake_elev()
  })

  out <- foundation_tile_source_srtm(aoi = aoi_cerrado,
                                     derive = c("slope", "TPI", "roughness"),
                                     country = "KEN", path = tempdir())

  # `country` selects which national tile is fetched. Hard-coding it to the
  # "BRA" default would make every non-Brazilian AoI silently wrong.
  expect_identical(seen$args$country, "KEN")
  expect_identical(seen$args$path, tempdir())

  expect_equal(terra::nlyr(out), 4L)
  expect_equal(names(out), c("elev", "slope", "TPI", "roughness"))
})

test_that("srtm with an empty derive returns elevation alone", {
  skip_tiles()
  local_geodata(elevation_30s = function(...) fake_elev())

  out <- foundation_tile_source_srtm(aoi = aoi_cerrado, derive = character(0))
  expect_equal(terra::nlyr(out), 1L)
  expect_equal(names(out), "elev")
})

test_that("derived slope comes back in degrees, not radians", {
  skip_tiles()
  local_geodata(elevation_30s = function(...) fake_elev())

  out <- foundation_tile_source_srtm(aoi = aoi_cerrado, derive = "slope")
  max_slope <- max(terra::values(out[["slope"]]), na.rm = TRUE)

  # A slope in radians cannot exceed pi/2, so a value above it proves the
  # channel is in degrees. (terra::terrain()'s own default is already
  # "degrees", so merely deleting the explicit argument is a no-op today --
  # what this pins is the unit that actually comes out, against someone
  # switching it to "radians" or terra changing its default. Either would
  # rescale the channel by ~57x and quietly skew every covariate table
  # downstream.)
  expect_gt(max_slope, pi / 2)
  expect_lte(max_slope, 90)
})

test_that("srtm crops to the AoI before deriving terrain", {
  skip_tiles()
  local_geodata(elevation_30s = function(...) fake_elev())

  out <- foundation_tile_source_srtm(aoi = aoi_cerrado, derive = "slope")
  # The fake tile spans 6 x 6 degrees; the AoI is 2 x 2. A missing crop would
  # leave the full national tile and blow up memory on a real download.
  expect_equal(unname(as.vector(terra::ext(out))), c(-50, -48, -16, -14))
  expect_equal(dim(out)[1:2], c(20L, 20L))
})


# ---- Optional-dependency guards ---------------------------------------------

test_that("each geodata-backed source names its own product in the install hint", {
  skip_tiles()
  local_geodata()          # tripwires first...
  local_pkg_absent("geodata")   # ...then hide geodata

  # Copy-paste is the obvious failure mode here: three near-identical guards,
  # and a wrong product name sends the user looking in the wrong place.
  expect_match(conditionMessage(err_of(
    foundation_tile_source_soilgrids("soc", aoi = aoi_cerrado))),
    "Install `geodata` to fetch SoilGrids", fixed = TRUE)

  expect_match(conditionMessage(err_of(
    foundation_tile_source_worldclim("prec", country = "BRA", aoi = aoi_cerrado))),
    "Install `geodata` for WorldClim", fixed = TRUE)

  expect_match(conditionMessage(err_of(
    foundation_tile_source_srtm(aoi = aoi_cerrado))),
    "Install `geodata` for SRTM", fixed = TRUE)
})

test_that("the geodata guard fires before the AoI is coerced or anything downloads", {
  skip_tiles()
  local_geodata()
  local_pkg_absent("geodata")

  # Even a valid AoI must not get as far as a download, and even an invalid
  # one must report the missing package rather than the bad extent: the
  # install hint is the actionable message when geodata is absent.
  msg <- conditionMessage(err_of(
    foundation_tile_source_srtm(aoi = "not an aoi")))
  expect_match(msg, "Install `geodata` for SRTM", fixed = TRUE)
  expect_false(grepl("NETWORK GUARD", msg, fixed = TRUE))
})

test_that("the terra guard fires before the geodata guard", {
  skip_tiles()
  local_geodata()
  local_pkg_absent(c("terra", "geodata"))

  # terra is checked first in all three, so with both absent the terra hint
  # wins -- it is the more fundamental dependency and the one every other
  # tile function needs too.
  for (call_it in list(
    function() foundation_tile_source_soilgrids("soc", aoi = aoi_cerrado),
    function() foundation_tile_source_worldclim("prec", country = "BRA",
                                                aoi = aoi_cerrado),
    function() foundation_tile_source_srtm(aoi = aoi_cerrado)
  )) {
    msg <- conditionMessage(err_of(call_it()))
    expect_match(msg, "Install the `terra` package for tile IO", fixed = TRUE)
    expect_false(grepl("geodata", msg, fixed = TRUE))
  }
})
