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
