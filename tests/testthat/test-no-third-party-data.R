# =============================================================================
# The package must ship no third-party soil measurements.
#
# This walks every bundled .rds RECURSIVELY, descending into places a
# name-based check cannot see. That is not paranoia: the bundle this package
# used to ship, piml_external_anchors.rds, had a .slim_lm() helper that
# explicitly nulled $model and $effects, with a comment asserting only
# coefficients remained -- and still shipped residuals and fitted.values named
# by real WoSIS profile ids, plus a row-named qr$qr. Three copies where the
# author believed there were none. A top-level names() check passes that file.
#
# The companion test at the bottom proves this one fires. A guard that has
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
# a scatter, and (b) intersecting them against the full coordinate universe of
# the third-party bundles this package used to ship: zero collisions.
#
# capstone_campaign_results' simulation AOI is a perfect 10x10 grid, 10
# distinct longitudes (-50.000 .. -48.000) crossed with 10 distinct latitudes
# (-16.000 .. -14.000); $decision_matrix, $final_selection and
# $temporal_results$obs_locations are 8-row subsets of that same grid.
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
  "capstone_campaign_results.rds$temporal_results$obs_locations"
)

allowed <- function(offence) {
  if (grepl("^fixture_", offence)) return(TRUE)
  any(vapply(ALLOWED, function(a) startsWith(offence, paste0(a, " :")),
             logical(1)))
}

scan_bundle <- function(path) scan_object(readRDS(path), basename(path))

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
