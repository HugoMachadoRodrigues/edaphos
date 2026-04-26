#' Synthetic Cerrado soil sample for edaphos vignettes
#'
#' A 45 x 45 pixel grid (~600 m resolution) over a ~30 km square near
#' Brasília (Distrito Federal), Brazil, with Cerrado-like environmental
#' covariates and a synthesised Soil Organic Carbon (SOC) response. Used
#' as a reproducible, offline stand-in for a real SoilGrids +
#' WorldClim + SRTM stack in the Pillar 5 Brazilian vignette.
#'
#' The `data-raw/prepare_br_cerrado.R` script that ships with the package
#' also contains a ready-to-run block (guarded by `if (FALSE)`) that
#' regenerates the same structure from live SoilGrids / WorldClim /
#' elevation_30s data using `geodata` + `terra`.
#'
#' @format A data frame with 2025 rows and 8 columns:
#' \describe{
#'   \item{x}{Longitude (WGS84, decimal degrees).}
#'   \item{y}{Latitude (WGS84, decimal degrees).}
#'   \item{elev}{Elevation (m a.s.l.).}
#'   \item{slope}{Slope (degrees).}
#'   \item{twi}{Topographic Wetness Index (dimensionless).}
#'   \item{map_mm}{Mean annual precipitation (mm / year).}
#'   \item{ndvi}{Dry-season mean NDVI (dimensionless, 0-1).}
#'   \item{soc}{Soil Organic Carbon, 0-5 cm (g / kg). **Target.**}
#' }
#' @source Synthetic; see `data-raw/prepare_br_cerrado.R`.
"br_cerrado"

#' Synthetic Amazon-rainforest soil sample (NW Brazil)
#'
#' A 45 x 45 pixel grid covering a ~40 km square near Manaus (Amazonas)
#' with the same column schema as [`br_cerrado`].  Distinct
#' distributions vs Cerrado:
#'
#' * Lower elevation (50-300 m) and gentler slopes (0-8 deg).
#' * Much higher rainfall (2200-3000 mm/y) and NDVI (0.75-0.95).
#' * Higher and more right-skewed SOC (35-90 g/kg).
#'
#' Drop-in replacement for `br_cerrado` in any pillar / vignette --
#' useful as a second-region smoke test.
#'
#' @format A data frame with 2025 rows and 8 columns: same schema as
#'   [`br_cerrado`].
#' @source Synthetic; see `data-raw/prepare_br_amazon.R`.
"br_amazon"

#' Synthetic Pantanal-wetland soil sample (MS, Brazil)
#'
#' A 45 x 45 pixel grid covering a ~40 km square in the Brazilian
#' Pantanal (Mato Grosso do Sul) with the same column schema as
#' [`br_cerrado`].  Distinct distributions vs Cerrado:
#'
#' * Very flat (elev 80-150 m, slopes 0-3 deg).
#' * Strongly bimodal TWI and NDVI from the channel/floodplain
#'   geomorphology.
#' * Highly variable SOC (8-95 g/kg) shaped by the flood pulse.
#'
#' @format A data frame with 2025 rows and 8 columns: same schema as
#'   [`br_cerrado`].
#' @source Synthetic; see `data-raw/prepare_br_pantanal.R`.
"br_pantanal"
