#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/soildata_uberaba_bd.R
#
# A Cerrado calibration set with MEASURED bulk density on every horizon.
#
# WHY THIS EXISTS. The manuscript said a stock validation at scale "would need
# a pedotransfer function we have not built", and the reason given was that
# WoSIS bulk density covers 3.9% of the Cerrado horizons this package ships.
# That is true of WoSIS. It is not true of the Brazilian soil-data ecosystem.
#
# WHERE IT COMES FROM, AND WHY NOT febr. The `febr` R package points at a
# static ownCloud snapshot (cloud.utfpr.edu.br) that serves ~43 datasets, and
# its copy of ctb0017 has NO bulk-density column at all. The live repository
# is SoilData, a Dataverse at repositorio.soildata.mapbiomas.org holding 301
# datasets, and its copy of the same ctb0017 carries 78 columns including
# "Densidade do solo [g/cm^3]". The difference is the whole reason a
# pedotransfer function is now possible: same dataset id, different richness.
#
# WHAT IT IS. ctb0017 -- "Solos da Bacia Hidrográfica do Rio Uberaba", Minas
# Gerais. 83 profiles, 166 horizons, every one carrying measured bulk density,
# organic carbon, particle-size distribution and the fine-earth fraction, to
# 200 cm. Coordinates lie between 48.5 W and 47.6 W, 20.0 S and 19.5 S --
# inside the Cerrado, on the deeply weathered soils the biome is made of.
#
# WHAT IT IS NOT. One river basin, not the biome. A function calibrated here
# and applied across the Cerrado is extrapolating in space, and the manuscript
# says so rather than presenting 83 profiles as coverage.
#
# Output: inst/extdata/soildata_uberaba_bd.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))

DOI  <- "doi:10.60502/SoilData/QN7OBM"
BASE <- "https://repositorio.soildata.mapbiomas.org"
DEST <- file.path(tempdir(), "ctb0017.xlsx")

num <- function(v) suppressWarnings(as.numeric(gsub(",", ".", as.character(v))))

# --- 1. fetch --------------------------------------------------------------
message("querying SoilData for ", DOI, " ...")
meta <- tryCatch({
  r <- httr2::req_perform(httr2::req_timeout(httr2::request(sprintf(
    "%s/api/datasets/:persistentId/versions/:latest/files?persistentId=%s",
    BASE, DOI)), 120))
  jsonlite::fromJSON(httr2::resp_body_string(r), simplifyVector = FALSE)
}, error = function(e) NULL)

if (is.null(meta) || !length(meta$data))
  stop("SoilData is unreachable or the dataset has no files. This script needs ",
       "network access; the built bundle is shipped so the rest of the ",
       "package does not.", call. = FALSE)

fid <- meta$data[[1]]$dataFile$id
utils::download.file(sprintf("%s/api/access/datafile/%s", BASE, fid),
                     DEST, quiet = TRUE, mode = "wb")
message(sprintf("  %s (%.0f KB)", meta$data[[1]]$dataFile$filename,
                file.size(DEST) / 1024))

# --- 2. harmonise ----------------------------------------------------------
cm <- suppressMessages(readxl::read_excel(DEST, sheet = "camada"))
ev <- suppressMessages(readxl::read_excel(DEST, sheet = "evento"))

# Column names carry their units in the header, which is how the unit
# conversions below are justified rather than assumed:
#   "C [dag/kg^1]"                 dag/kg is percent, so x10 gives g/kg
#   "Densidade do solo [g/cm^3]"   already the unit stock arithmetic wants
#   "Terra fina (mm) [%]"          fine-earth percentage, for a fine-earth stock
stopifnot("C [dag/kg^1]" %in% names(cm),
          "Densidade do solo [g/cm^3]" %in% names(cm))

H <- data.frame(
  profile_id = as.character(cm[["Identificação do evento"]]),
  top        = num(cm[["Profundidade inicial [cm]"]]),
  bottom     = num(cm[["Profundidade final [cm]"]]),
  soc_g_kg   = num(cm[["C [dag/kg^1]"]]) * 10,
  bd_g_cm3   = num(cm[["Densidade do solo [g/cm^3]"]]),
  clay       = num(cm[["Argila (mm) [%]"]]),
  silt       = num(cm[["Silte (mm) [%]"]]),
  sand       = num(cm[["Areia (mm) [%]"]]),
  fine_earth = num(cm[["Terra fina (mm) [%]"]]),
  gravel     = num(cm[["Cascalho (mm) [%]"]]),
  ph_h2o     = num(cm[["pH em Água"]]),
  stringsAsFactors = FALSE
)
H$depth_mid <- (H$top + H$bottom) / 2
H$thickness <- H$bottom - H$top

E <- data.frame(
  profile_id = as.character(ev[["ID do evento"]]),
  lon        = num(ev[["Longitude [m]"]]),
  lat        = num(ev[["Latitude [m]"]]),
  elev       = num(ev[["Altitude (m)"]]),
  soil_class = as.character(ev[["Classificação de solo"]]),
  land_use   = as.character(ev[["Uso atual da terra"]]),
  stringsAsFactors = FALSE
)
H <- merge(H, E, by = "profile_id", all.x = TRUE)

# --- 3. refuse what cannot be used -----------------------------------------
# A horizon is usable for calibrating a density function only if it carries
# density, carbon, a real thickness and a location. Dropping is reported, not
# silent.
ok <- is.finite(H$bd_g_cm3) & is.finite(H$soc_g_kg) &
      is.finite(H$top) & is.finite(H$bottom) & H$bottom > H$top &
      is.finite(H$lon) & is.finite(H$lat)
message(sprintf("horizons: %d read, %d usable (%d dropped)",
                nrow(H), sum(ok), sum(!ok)))
H <- H[ok, ]

# Physical sanity. A bulk density outside 0.3-2.2 g/cm3 is not a soil; a
# carbon concentration above 600 g/kg is not a mineral horizon.
bad <- H$bd_g_cm3 < 0.3 | H$bd_g_cm3 > 2.2 | H$soc_g_kg < 0 | H$soc_g_kg > 600
if (any(bad)) {
  message(sprintf("  %d horizons outside physical bounds, dropped", sum(bad)))
  H <- H[!bad, ]
}

cat(sprintf("\n=== ctb0017, Bacia do Rio Uberaba (MG) ===\n"))
cat(sprintf("%d horizons over %d profiles\n", nrow(H), length(unique(H$profile_id))))
cat(sprintf("lon %.2f to %.2f | lat %.2f to %.2f\n",
            min(H$lon), max(H$lon), min(H$lat), max(H$lat)))
cat(sprintf("depth to %g cm | bulk density %.2f-%.2f g/cm3 | carbon %.1f-%.1f g/kg\n",
            max(H$bottom), min(H$bd_g_cm3), max(H$bd_g_cm3),
            min(H$soc_g_kg), max(H$soc_g_kg)))
cat(sprintf("clay %.0f-%.0f%% | fine earth on %d of %d horizons\n",
            min(H$clay, na.rm = TRUE), max(H$clay, na.rm = TRUE),
            sum(is.finite(H$fine_earth)), nrow(H)))
cat("\nsoil classes (first word):\n")
print(sort(table(sub(" .*", "", H$soil_class)), decreasing = TRUE)[1:6])

saveRDS(list(
             # Binds this bundle to the script that made it: see R/provenance.R.
             provenance = edaphos_provenance(),
             horizons = H,
             doi = DOI, source = "SoilData (Dataverse)",
             dataset = "ctb0017 - Solos da Bacia Hidrografica do Rio Uberaba",
             fetched_at = format(Sys.Date()),
             built_by = "data-raw/soildata_uberaba_bd.R"),
        "inst/extdata/soildata_uberaba_bd.rds")
message("\nwrote inst/extdata/soildata_uberaba_bd.rds")
