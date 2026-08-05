#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_wosis_multihorizon.R
#
# Build the REAL multi-horizon depth-profile dataset for Pillar 2.
#
# Why this file exists
# --------------------
# Pillar 2 -- the pedogenetic ODE, the paper's central contribution -- was
# calibrated and illustrated on seven numbers typed by hand into
# data-raw/capstone_campaign_run.R:
#
#     depth_mid = c(5, 15, 25, 40, 60, 80, 100)
#     soc_g_kg  = c(32, 24, 18, 13,  9,  6,  4)
#
# They are not a measured pedon. Meanwhile the repository already contains
# tools/case_cerrado/wosis_orgc_cerrado.gml -- 10,348 real ISRIC WoSIS organic
# carbon horizons over the Brazilian Cerrado, fetched by the author's own
# data-raw/case_cerrado_prepare.R, which then keeps only the shallowest horizon
# of each profile and discards the rest. Every reviewer on the specialist panel
# independently identified this as the submission-ending problem: the empirical
# base of the central pillar was invented while the real data sat unused in the
# same tree.
#
# This script keeps ALL horizons. It also joins bulk density from
# wosis_bdfiod_cerrado.gml so that carbon STOCK -- the quantity that is actually
# conserved, and the one a depth model should be scored on -- can be computed
# rather than only concentration.
#
# Output: inst/extdata/piml_wosis_cerrado.rds
#
# Run from the package root:  Rscript data-raw/piml_wosis_multihorizon.R
# ---------------------------------------------------------------------------

suppressMessages({
  library(sf)
})

ORGC_GML  <- "tools/case_cerrado/wosis_orgc_cerrado.gml"
BDFIOD_GML <- "tools/case_cerrado/wosis_bdfiod_cerrado.gml"
OUT       <- "inst/extdata/piml_wosis_cerrado.rds"

if (!file.exists(ORGC_GML)) {
  stop("Missing ", ORGC_GML, ". Run data-raw/case_cerrado_prepare.R first ",
       "(it fetches the WoSIS WFS layers into tools/case_cerrado/).",
       call. = FALSE)
}

message("=== Pillar 2: real multi-horizon WoSIS profiles ===")

# --- 1. organic carbon horizons ------------------------------------------
message("reading ", ORGC_GML)
orgc_sf <- suppressWarnings(sf::st_read(ORGC_GML, quiet = TRUE))
coords  <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(orgc_sf)))
orgc    <- sf::st_drop_geometry(orgc_sf)
orgc$x  <- coords[, 1]
orgc$y  <- coords[, 2]

num <- function(v) suppressWarnings(as.numeric(v))
orgc$upper_depth <- num(orgc$upper_depth)
orgc$lower_depth <- num(orgc$lower_depth)
orgc$value_avg   <- num(orgc$value_avg)

# WoSIS serves ORGC in g/kg already; keep only physically usable horizons.
# A non-positive concentration is a missing-value code or a units error, not a
# measurement, and Pillar 2's likelihood lives on positive concentrations.
keep <- is.finite(orgc$upper_depth) & is.finite(orgc$lower_depth) &
        is.finite(orgc$value_avg) &
        orgc$upper_depth >= 0 & orgc$upper_depth < orgc$lower_depth &
        orgc$value_avg > 0
message(sprintf("  horizons: %d read, %d usable (%d dropped)",
                nrow(orgc), sum(keep), sum(!keep)))
orgc <- orgc[keep, ]

# --- 2. bulk density, for stock ------------------------------------------
# bdfiod = bulk density of the fine earth fraction, oven dry (kg/dm3 = g/cm3).
bd <- NULL
if (file.exists(BDFIOD_GML)) {
  message("reading ", BDFIOD_GML)
  bd <- sf::st_drop_geometry(suppressWarnings(sf::st_read(BDFIOD_GML, quiet = TRUE)))
  bd$upper_depth <- num(bd$upper_depth)
  bd$lower_depth <- num(bd$lower_depth)
  bd$value_avg   <- num(bd$value_avg)
  bd <- bd[is.finite(bd$upper_depth) & is.finite(bd$lower_depth) &
           is.finite(bd$value_avg) & bd$value_avg > 0 &
           bd$upper_depth < bd$lower_depth, ]
  message(sprintf("  bulk-density horizons: %d over %d profiles",
                  nrow(bd), length(unique(bd$profile_id))))
} else {
  message("  [warn] no bulk-density GML; stock will be NA")
}

# Depth-weighted overlap match: for an ORGC horizon [u, l], average every
# bulk-density horizon that overlaps it, weighted by the overlap length. This
# is the honest join -- BD horizons are not sampled on the same boundaries as
# the carbon horizons, and picking the mid-depth's BD horizon throws away the
# rest of the interval.
bd_for <- function(pid, u, l) {
  if (is.null(bd)) return(NA_real_)
  r <- bd[bd$profile_id == pid, , drop = FALSE]
  if (!nrow(r)) return(NA_real_)
  ov <- pmax(0, pmin(l, r$lower_depth) - pmax(u, r$upper_depth))
  if (sum(ov) <= 0) return(NA_real_)
  sum(r$value_avg * ov) / sum(ov)
}

# --- 3. assemble ---------------------------------------------------------
d <- data.frame(
  profile_id = as.character(orgc$profile_id),
  x          = orgc$x,
  y          = orgc$y,
  top        = orgc$upper_depth,
  bottom     = orgc$lower_depth,
  soc_g_kg   = orgc$value_avg,
  stringsAsFactors = FALSE
)
d$depth_mid <- (d$top + d$bottom) / 2

# Drop exact duplicate horizons (same profile, same interval) -- WoSIS
# occasionally serves a layer twice under different layer_id.
d <- d[!duplicated(d[, c("profile_id", "top", "bottom")]), ]
d <- d[order(d$profile_id, d$top), ]

message("joining bulk density (depth-weighted overlap)")
d$bd_g_cm3 <- if (is.null(bd)) NA_real_ else
  mapply(bd_for, d$profile_id, d$top, d$bottom)

# Carbon stock of the horizon, Mg/ha:
#   stock = SOC(g/kg) * BD(g/cm3) * thickness(cm) * 0.1
# (g/kg * g/cm3 = g C per 1000 cm3 of soil per cm... the 0.1 converts
#  g/kg x g/cm3 x cm to Mg/ha; coarse fragments are not served by this WoSIS
#  layer, so the stock is a fine-earth stock and is labelled as such.)
d$stock_mg_ha <- d$soc_g_kg * d$bd_g_cm3 * (d$bottom - d$top) * 0.1

# --- 4. keep profiles with enough horizons to identify a depth function ---
# Four horizons is the minimum at which the four-parameter ODE is not
# saturated, and it is the threshold the panel used.
nh <- table(d$profile_id)
multi <- names(nh)[nh >= 4L]
d <- d[d$profile_id %in% multi, ]

# --- 5. per-profile summary ----------------------------------------------
sp <- do.call(rbind, lapply(split(d, d$profile_id), function(s) {
  s <- s[order(s$top), ]
  data.frame(
    profile_id = s$profile_id[1],
    x = s$x[1], y = s$y[1],
    n_hor = nrow(s),
    z_max = max(s$bottom),
    soc_top = s$soc_g_kg[1],
    soc_deepest = s$soc_g_kg[nrow(s)],
    # A monotone non-increasing profile is the class the ODE can represent.
    # The rest -- illuvial bulges, buried A horizons, E-below-A -- are outside
    # its scope and must be reported, not silently fitted.
    #
    # This is a DESCRIPTOR of the whole profile. Do not use it to stratify a
    # cross-validation that holds a horizon out: deciding whether a profile is
    # in the model's domain by reading the horizon you are about to predict is
    # a test-set leak. data-raw/piml_depth_benchmark.R computes its own
    # stratifier from training horizons only, per split.
    monotone_decreasing = all(diff(s$soc_g_kg) <= 0),
    # the same judgement made without the deepest horizon, which is what a
    # leave-the-deepest-out split may legitimately use
    monotone_without_deepest = nrow(s) > 2 &&
      all(diff(s$soc_g_kg[-nrow(s)]) <= 0),
    has_bd = all(is.finite(s$bd_g_cm3)),
    stringsAsFactors = FALSE
  )
}))
rownames(sp) <- NULL

message(sprintf("\nprofiles with >= 4 horizons : %d", nrow(sp)))
message(sprintf("horizons                     : %d", nrow(d)))
message(sprintf("max depth  median / max       : %.0f / %.0f cm",
                median(sp$z_max), max(sp$z_max)))
message(sprintf("monotone non-increasing      : %d (%.1f%%)",
                sum(sp$monotone_decreasing), 100 * mean(sp$monotone_decreasing)))
message(sprintf("with bulk density on every horizon: %d (%.1f%%)",
                sum(sp$has_bd), 100 * mean(sp$has_bd)))

out <- list(
  horizons = d,
  profiles = sp,
  meta = list(
    source = "ISRIC WoSIS latest (wosis_latest_orgc, wosis_latest_bdfiod), Cerrado bbox",
    cached_from = c(ORGC_GML, BDFIOD_GML),
    built_by = "data-raw/piml_wosis_multihorizon.R",
    n_profiles = nrow(sp),
    n_horizons = nrow(d),
    min_horizons_per_profile = 4L,
    units = c(soc = "g/kg", bd = "g/cm3", stock = "Mg/ha fine earth", depth = "cm"),
    note = paste("All horizons retained. Earlier package code kept only the",
                 "shallowest horizon per profile, which is why Pillar 2 had no",
                 "real depth data to fit.")
  )
)

dir.create(dirname(OUT), showWarnings = FALSE, recursive = TRUE)
saveRDS(out, OUT)
message("\nwrote ", OUT, " (", round(file.size(OUT) / 1024), " KB)")
