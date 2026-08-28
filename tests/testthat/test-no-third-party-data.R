# =============================================================================
# The package must ship no third-party soil measurements.
#
# This walks every bundled .rds AND every exported dataset under data/,
# RECURSIVELY, descending into places a name-based check cannot see. That is
# not paranoia: the bundle this package used to ship,
# piml_external_anchors.rds, had a .slim_lm() helper that explicitly nulled
# $model and $effects, with a comment asserting only coefficients remained --
# and still shipped residuals and fitted.values named by real WoSIS profile
# ids, plus a row-named qr$qr. Three copies where the author believed there
# were none. A top-level names() check passes that file.
#
# data/ was added on 2026-08-28. Until then this test covered inst/extdata
# only, which is two thirds of what the package ships; the three exported
# grids were scanned by nobody. They turned out clean, but that was luck
# rather than a result, because nothing was looking.
#
# Two companion tests prove the two guards fire -- one injects the historical
# slimmed-lm defect, one hands the lattice check a scatter. A guard that has
# never been shown to fail is not a guard.
# =============================================================================

COORD_NAMES <- c("lon", "lat", "longitude", "latitude", "x", "y",
                 "coord_x", "coord_y")
ID_NAMES    <- c("profile_id", "pedon_key", "point_id", "profile_code",
                 "dataset_id", "observation_id", "upedonid")
# Endpoint-shaped only. An earlier version matched bare service names and
# fired on DAG node labels like "soilgrids_clay", which are column names, not
# payload.
SERVICE_RX  <- "https?://|\\.isric\\.org|\\.openalex\\.org|dataverse.*/api|mapserv|/graphql"

# Upstream WoSIS ids are 6-8 digit integers. Fixture ids are strings like
# "SYN_001", which is the point of giving them that shape.
looks_like_upstream_id <- function(v) {
  if (length(v) == 0) return(FALSE)
  s <- as.character(v[!is.na(v)])
  if (!length(s)) return(FALSE)
  mean(grepl("^[0-9]{6,8}$", s)) > 0.5
}

# Returns a character vector of offences; empty means clean.
scan_object <- function(x, path = "$", depth = 0L, seen = 0L) {
  out <- character(0)
  if (depth > 12L) return(out)

  # -- named numeric/character vectors keyed by upstream ids ----------------
  if (is.atomic(x) && !is.null(names(x)) && looks_like_upstream_id(names(x)))
    out <- c(out, sprintf("%s : atomic vector NAMED by upstream ids (%d)",
                          path, length(x)))

  if (is.data.frame(x)) {
    n <- tolower(names(x))
    explicit <- sum(n %in% c("lon", "lat", "longitude", "latitude"))
    # x/y also name graph-layout columns, so require geographic-looking values
    # and enough distinct pairs before treating them as locations.
    ambiguous <- FALSE
    if (all(c("x", "y") %in% n)) {
      vx <- suppressWarnings(as.numeric(x[[which(n == "x")[1]]]))
      vy <- suppressWarnings(as.numeric(x[[which(n == "y")[1]]]))
      ok <- stats::complete.cases(vx, vy)
      ambiguous <- sum(ok) >= 20L &&
        all(abs(vx[ok]) <= 180) && all(abs(vy[ok]) <= 90) &&
        length(unique(paste(vx[ok], vy[ok]))) >= 20L
    }
    hit_xy <- if (explicit >= 2L || ambiguous) 2L else 0L
    if (hit_xy >= 2L)
      out <- c(out, sprintf("%s : coordinate columns (%s), %d rows", path,
                            paste(intersect(n, COORD_NAMES), collapse = "/"),
                            nrow(x)))
    for (idc in intersect(n, ID_NAMES)) {
      v <- x[[which(n == idc)[1]]]
      if (looks_like_upstream_id(v))
        out <- c(out, sprintf("%s : column '%s' holds upstream ids, %d rows",
                              path, idc, nrow(x)))
    }
    if (!is.null(rownames(x)) && looks_like_upstream_id(rownames(x)))
      out <- c(out, sprintf("%s : ROW NAMES are upstream ids, %d rows",
                            path, nrow(x)))
    return(out)
  }

  # -- model objects re-serialise the data their author thought they dropped
  if (inherits(x, c("lm", "glm", "nls"))) {
    for (slot in c("model", "residuals", "fitted.values", "effects", "qr", "y"))
      if (!is.null(x[[slot]]))
        out <- c(out, scan_object(x[[slot]], paste0(path, "$", slot),
                                  depth + 1L))
    return(out)
  }

  # -- a closure carries its enclosing environment, and everything in it ----
  if (is.function(x)) {
    e <- environment(x)
    if (!is.null(e) && !identical(e, globalenv()) &&
        !identical(e, baseenv()) && !identical(e, emptyenv())) {
      for (nm in ls(e, all.names = TRUE))
        out <- c(out, scan_object(get(nm, envir = e),
                                  sprintf("%s<closure env>$%s", path, nm),
                                  depth + 1L))
    }
    return(out)
  }

  if (is.character(x) && length(x) <= 50L) {
    hit <- grepl(SERVICE_RX, tolower(x))
    # A provenance string naming a service is fine; a payload of them is not.
    if (any(hit) && length(x) > 5L)
      out <- c(out, sprintf("%s : %d strings naming an upstream service",
                            path, sum(hit)))
  }

  if (is.list(x)) {
    nms <- names(x)
    for (i in seq_along(x)) {
      lbl <- if (!is.null(nms) && nzchar(nms[i])) paste0(path, "$", nms[i])
             else sprintf("%s[[%d]]", path, i)
      out <- c(out, scan_object(x[[i]], lbl, depth + 1L))
    }
  }
  out
}

# -- allowlist ---------------------------------------------------------------
# Coordinate-bearing elements that are verified synthetic. Every entry was
# checked by (a) confirming the coordinates form a regular lattice rather than
# a scatter, and (b) intersecting them against the coordinate universe of the
# third-party records this package used to ship.
#
# capstone_campaign_results' simulation AOI is a perfect 10x10 grid, 10
# distinct longitudes (-50.000 .. -48.000) crossed with 10 distinct latitudes
# (-16.000 .. -14.000); $decision_matrix, $final_selection and
# $temporal_results$obs_locations are 8-row subsets of that same grid.
#
# CORRECTION, 2026-08-28. This comment used to end "zero collisions", and for
# capstone that is not what a measurement returns. Recovering the pre-strip
# bundles from commit d8c1998 and subtracting what survives gives 3,047
# distinct removed coordinates, and capstone collides with exactly one of
# them: (-47.9, -14.1), row 8 of $temporal_results$obs_locations.
#
# It is not a leaked profile. What was removed from temporal_cerrado_results
# is itself a perfect 10x10 grid at 0.2 degree spacing -- raster cell centres
# of a simulation domain carrying gridded NDVI, precipitation and temperature,
# not sampling sites -- and both bundles describe that same domain, so they
# share its nodes. The eight rows still shipped carry lon and lat and no
# measurement. The claim is corrected rather than the number, because the
# number is right. tools/provenance-inventory.R recomputes both.
#
# The fixtures are synthetic by construction -- see data-raw/make_fixtures.R,
# which generates from published literature parameters and places points on a
# deliberate lattice for exactly this reason.
#
# ADDING TO THIS LIST IS NOT A FIX. An entry means "checked, and synthetic".
# If a scan fires on something new, verify it the same two ways before
# considering an entry, and record what you checked.
ALLOWED <- c(
  "capstone_campaign_results.rds$aoi",
  "capstone_campaign_results.rds$foundation_pred_df",
  "capstone_campaign_results.rds$candidate_df",
  "capstone_campaign_results.rds$qkrr_df",
  "capstone_campaign_results.rds$decision_matrix",
  "capstone_campaign_results.rds$final_selection",
  "capstone_campaign_results.rds$temporal_results$obs_locations",

  # -- the exported datasets under data/ ------------------------------------
  # Added 2026-08-28, when this test was extended past inst/extdata. Until
  # then data/ was a third of what the package ships and none of it was
  # scanned. Checked the two ways this list demands:
  #
  #   (a) each is a COMPLETE 45 x 45 lattice -- all 2,025 cells filled, one
  #       constant spacing per axis. Real profiles do not fill a rectangle.
  #   (b) intersected against the 3,047 distinct real coordinates that the
  #       2026-08-28 strip removed, recovered from commit d8c1998 by
  #       tools/provenance-inventory.R: zero collisions, all three.
  #
  # (a) is NOT left to this comment. The lattice test below asserts it, so
  # swapping a grid for real profiles fails even though the name sits here.
  "br_amazon", "br_cerrado", "br_pantanal"
)

allowed <- function(offence) {
  if (grepl("^fixture_", offence)) return(TRUE)
  any(vapply(ALLOWED, function(a) startsWith(offence, paste0(a, " :")),
             logical(1)))
}

scan_bundle <- function(path) scan_object(readRDS(path), basename(path))

# data/ is enumerated through utils::data() rather than list.files(). In an
# INSTALLED package there are no .rda files -- data/ has been collapsed into
# Rdata.rdb + Rdata.rdx -- so a file listing finds nothing and the scan would
# silently cover nothing at all, which is the failure mode this test exists to
# prevent. utils::data() resolves in both the source tree and an installation.
dataset_names <- function() {
  r <- utils::data(package = "edaphos")$results
  if (!length(r)) return(character(0))
  unique(sub(" .*$", "", r[, "Item"]))
}

scan_dataset <- function(nm) {
  e <- new.env(parent = emptyenv())
  utils::data(list = nm, package = "edaphos", envir = e)
  scan_object(get(nm, envir = e), nm)
}

test_that("no shipped bundle carries third-party records", {
  dir <- system.file("extdata", package = "edaphos")
  skip_if(dir == "", "package not installed")
  files <- list.files(dir, pattern = "[.]rds$", full.names = TRUE)
  skip_if(length(files) == 0L, "no bundles")

  offences <- unlist(lapply(files, scan_bundle), use.names = FALSE)
  offences <- offences[!vapply(offences, allowed, logical(1))]

  expect_equal(offences, character(0),
               info = paste("third-party records found:\n",
                            paste(offences, collapse = "\n ")))
})

test_that("no exported dataset carries third-party records", {
  nms <- dataset_names()
  skip_if(length(nms) == 0L, "no exported datasets")

  offences <- unlist(lapply(nms, scan_dataset), use.names = FALSE)
  offences <- offences[!vapply(offences, allowed, logical(1))]

  expect_equal(offences, character(0),
               info = paste("third-party records found:\n",
                            paste(offences, collapse = "\n ")))
})

# A complete rectangular lattice: every cell of an n x m grid filled, and one
# constant spacing per axis. Real soil profiles do not have this property --
# they are a scatter, and a scatter neither fills a rectangle nor keeps a
# single gap between consecutive distinct values.
is_complete_lattice <- function(d, xcol = "x", ycol = "y") {
  if (!all(c(xcol, ycol) %in% names(d))) return(FALSE)
  ux <- sort(unique(d[[xcol]])); uy <- sort(unique(d[[ycol]]))
  if (length(ux) < 2L || length(uy) < 2L) return(FALSE)
  nrow(d) == length(ux) * length(uy) &&
    length(unique(round(diff(ux), 9))) == 1L &&
    length(unique(round(diff(uy), 9))) == 1L
}

test_that("the allowlisted grids are still complete regular lattices", {
  # This is what earns br_amazon / br_cerrado / br_pantanal their allowlist
  # entries, and it is asserted rather than commented so the entry cannot
  # outlive the fact it rests on. Swapping a grid for a real extract fails
  # here even though the name is allowlisted above.
  nms <- intersect(c("br_amazon", "br_cerrado", "br_pantanal"), dataset_names())
  skip_if(length(nms) == 0L, "no exported grids")

  for (nm in nms) {
    e <- new.env(parent = emptyenv())
    utils::data(list = nm, package = "edaphos", envir = e)
    expect_true(is_complete_lattice(get(nm, envir = e)),
                info = sprintf("%s is no longer a complete regular lattice", nm))
  }
})

test_that("the lattice check actually rejects a scatter", {
  # The companion proof for the guard above. Same shape of evidence the
  # scanner's own firing test gives: without this, "every grid is a lattice"
  # could hold because the check says yes to everything.
  g <- expand.grid(x = seq(-50, -48, length.out = 45),
                   y = seq(-16, -14, length.out = 45))
  expect_true(is_complete_lattice(g))

  set.seed(1)
  scatter <- data.frame(x = stats::runif(2025, -50, -48),
                        y = stats::runif(2025, -16, -14))
  expect_false(is_complete_lattice(scatter))

  # A lattice with cells missing -- the shape a real extract clipped to a
  # bounding box would take.
  expect_false(is_complete_lattice(g[-seq(1, nrow(g), by = 7), ]))

  # Right cell count, irregular spacing on one axis.
  warped <- expand.grid(x = c(seq(-50, -48.1, length.out = 44), -47.0),
                        y = seq(-16, -14, length.out = 45))
  expect_false(is_complete_lattice(warped))
})

test_that("the scanner actually fires on a known-bad object", {
  # Reconstructs the exact defect that motivated this test: an lm that was
  # 'slimmed' by nulling $model, whose residuals and fitted.values are still
  # named by upstream ids.
  ids <- as.character(c(1023812, 1024656, 1024662, 1052215, 1052216))
  y   <- c(2.1, 3.4, 1.8, 4.0, 2.9)
  fit <- stats::lm(y ~ seq_along(y))
  fit$model <- NULL
  fit$effects <- NULL
  names(fit$residuals)     <- ids
  names(fit$fitted.values) <- ids

  bad <- list(hassink = list(model = fit))
  expect_gt(length(scan_object(bad, "bad")), 0L)

  # And on a plain frame of coordinates keyed to upstream ids.
  frame <- data.frame(profile_id = as.numeric(ids),
                      lon = seq(-50, -46, length.out = 5),
                      lat = seq(-15, -11, length.out = 5))
  expect_gt(length(scan_object(list(profiles = frame), "bad2")), 0L)
})
