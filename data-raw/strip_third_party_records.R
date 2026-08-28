## data-raw/strip_third_party_records.R
##
## One-shot remediation. Rewrites the bundles that stay in inst/extdata so they
## keep their scored/aggregate tables and lose every element that carries a
## third-party measurement or an upstream identifier.
##
## This script is recorded for the audit trail. It is NOT re-runnable against a
## clean checkout: once it has run, its inputs no longer exist. The pre-strip
## copies are archived outside the repository with a sha256 manifest.
##
## WHY AGGREGATES SURVIVE AND RECORDS DO NOT. A per-fold RMSE is a statement
## about a method. A 1095-element vector of measured log1p(SOC) is the dataset.
## The published claims rest on the former, so they survive; the latter is what
## this package must stop redistributing.
##
## ORDER MATTERS in exactly one place: piml_stock_validation.rds ships NO
## metrics table at all -- its RMSE/MAE/Wilcoxon numbers were only ever printed
## to the console by its generator. Strip $stock first and the evidence is gone
## with no way back except a live re-fetch that may not return the same 24
## horizons. So it is computed and stored BEFORE the drop.

setwd_root <- function() {
  if (!file.exists("DESCRIPTION")) stop("run from the package root")
}
setwd_root()

EXT <- file.path("inst", "extdata")
read_b  <- function(n) readRDS(file.path(EXT, paste0(n, ".rds")))
write_b <- function(x, n) saveRDS(x, file.path(EXT, paste0(n, ".rds")),
                                 version = 3, compress = "xz")

removed <- list()
note <- function(bundle, elements, why) {
  removed[[length(removed) + 1L]] <<-
    data.frame(bundle = bundle, removed = paste(elements, collapse = ", "),
               reason = why, stringsAsFactors = FALSE)
}

STRIP_NOTE <- paste(
  "Record-level elements were removed from this bundle because they carried",
  "third-party measurements or upstream identifiers. See",
  "data-raw/strip_third_party_records.R. The aggregate tables that the",
  "published claims rest on are unchanged."
)

# -- 1. piml_stock_validation: PRECOMPUTE, then strip -------------------------
b <- read_b("piml_stock_validation")
s <- b$stock
metrics <- function(obs, hat) c(RMSE = sqrt(mean((hat - obs)^2)),
                                MAE  = mean(abs(hat - obs)),
                                ME   = mean(hat - obs))
b$table <- data.frame(
  method = c("ode", "last", "mean"),
  rbind(metrics(s$stock_obs, s$stock_ode),
        metrics(s$stock_obs, s$stock_last),
        metrics(s$stock_obs, s$stock_mean)),
  row.names = NULL, stringsAsFactors = FALSE
)
b$paired <- data.frame(
  vs       = c("last", "mean"),
  ode_wins = c(sum(abs(s$stock_ode - s$stock_obs) < abs(s$stock_last - s$stock_obs)),
               sum(abs(s$stock_ode - s$stock_obs) < abs(s$stock_mean - s$stock_obs))),
  n        = nrow(s),
  p        = c(stats::wilcox.test(abs(s$stock_ode - s$stock_obs),
                                  abs(s$stock_last - s$stock_obs),
                                  paired = TRUE)$p.value,
               stats::wilcox.test(abs(s$stock_ode - s$stock_obs),
                                  abs(s$stock_mean - s$stock_obs),
                                  paired = TRUE)$p.value),
  stringsAsFactors = FALSE
)
b$n_horizons_scored <- nrow(s)
b$stock <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "piml_stock_validation")
note("piml_stock_validation", "$stock (24 rows)",
     "measured bd + conc_obs + stock_obs per real horizon; $table/$paired computed first")

# -- 2. piml_stock_at_scale --------------------------------------------------
b <- read_b("piml_stock_at_scale")
b$at_scale <- NULL; b$price <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "piml_stock_at_scale")
note("piml_stock_at_scale", "$at_scale (935), $price (24)",
     "soc recoverable as stock_obs/(bd*thickness*0.1); $price duplicated the 24 measured horizons")

# -- 3. piml_coverage --------------------------------------------------------
b <- read_b("piml_coverage")
b$coverage <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "piml_coverage")
note("piml_coverage", "$coverage (150)",
     "$truth was verbatim upstream laboratory SOC keyed to real profile_id")

# -- 4. piml_depth_benchmark -------------------------------------------------
b <- read_b("piml_depth_benchmark")
b$rows <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "piml_depth_benchmark")
note("piml_depth_benchmark", "$rows (2210)",
     "$obs was verbatim measured WoSIS organic carbon at the true sampling depth")

# -- 5. pilar8_real_pedons ---------------------------------------------------
b <- read_b("pilar8_real_pedons")
b$cv <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "pilar8_real_pedons")
note("pilar8_real_pedons", "$cv (5458)",
     "measured SOC at 7 depth nodes for 1022 real pedons")

# -- 6. interval_width_vs_extrapolation: bin, then strip ---------------------
b <- read_b("interval_width_vs_extrapolation")
pp <- b$per_profile
brk <- stats::quantile(pp$d_km, probs = seq(0, 1, 0.25), na.rm = TRUE)
band <- cut(pp$d_km, breaks = unique(brk), include.lowest = TRUE)
wcols <- grep("^w_", names(pp), value = TRUE)
b$by_distance <- do.call(rbind, lapply(levels(band), function(lv) {
  i <- which(band == lv)
  data.frame(band = lv, n = length(i),
             d_km_mid = stats::median(pp$d_km[i], na.rm = TRUE),
             as.list(stats::setNames(
               vapply(wcols, function(w) mean(pp[[w]][i], na.rm = TRUE), numeric(1)),
               paste0("mean_", wcols))),
             stringsAsFactors = FALSE)
}))
b$per_profile <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "interval_width_vs_extrapolation")
note("interval_width_vs_extrapolation", "$per_profile (1095)",
     "$truth was measured log1p(SOC) per real profile; $by_distance binned first")

# -- 7. benchmark_wosis_6pilar -----------------------------------------------
b <- read_b("benchmark_wosis_6pilar")
b$posterior_bank <- lapply(b$posterior_bank, function(pb) { pb$truth <- NULL; pb })
b$fold_sizes <- as.data.frame(table(fold = b$folds), stringsAsFactors = FALSE)
b$folds <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "benchmark_wosis_6pilar")
note("benchmark_wosis_6pilar", "$posterior_bank[[i]]$truth (1095 total), $folds (1095)",
     "the complete measured target, invertible via $response_scale = log1p")

# -- 8. capstone_campaign_results --------------------------------------------
b <- read_b("capstone_campaign_results")
b$wosis_profiles <- NULL; b$piml_profile_obs <- NULL; b$piml_profile_id <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "capstone_campaign_results")
note("capstone_campaign_results",
     "$wosis_profiles (250), $piml_profile_obs (9), $piml_profile_id",
     "real coordinates + measured SOC; the 9 horizons and the id identified WoSIS pedon 1115679")

# -- 9. capstone_native_calibration ------------------------------------------
b <- read_b("capstone_native_calibration")
for (p in grep("^p[0-9]", names(b), value = TRUE)) {
  b[[p]]$truth <- NULL
  b[[p]]$pedon <- NULL
}
b$strip_note <- STRIP_NOTE
write_b(b, "capstone_native_calibration")
note("capstone_native_calibration", "$p1..$p6 $truth, $p2$pedon (9)",
     "raw measured truth vectors; $p2$pedon was the third copy of pedon 1115679")

# -- 10. piml_prior_sensitivity ----------------------------------------------
b <- read_b("piml_prior_sensitivity")
b$profile_id <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "piml_prior_sensitivity")
note("piml_prior_sensitivity", "$profile_id",
     "bare upstream identifier '1115679' -- no measurements, but it identifies the pedon")

# -- 11. temporal_cerrado_results --------------------------------------------
# NASA POWER and MODIS MOD13Q1 are US-government public domain, so there is no
# licence conflict here. It is removed under the owner's blanket rule against
# bundling third-party measurements: $truth_future is 3600 observed values at
# 100 named coordinates.
b <- read_b("temporal_cerrado_results")
b$meta$lons <- NULL; b$meta$lats <- NULL
b$ensemble_forecast <- NULL; b$truth_future <- NULL; b$obs <- NULL
b$prior    <- b$prior[intersect(names(b$prior), "rmse")]
b$analysis <- b$analysis[intersect(names(b$analysis),
                                   c("rmse", "n_obs", "n_ens"))]
b$scaling <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "temporal_cerrado_results")
note("temporal_cerrado_results",
     "$truth_future (3600), $ensemble_forecast, $obs, $scaling, $meta$lons/$lats, gridded means",
     "observed NDVI/precip/temp at 100 named coordinates, invertible to physical units via $scaling")

# -- 12. case_cerrado_results ------------------------------------------------
# Originally slated for deletion. Restored and stripped instead: only
# $profiles is the payload, while $results, $predictions, $sources and
# $provenance are aggregates that vignettes/case-cerrado-end-to-end.Rmd and the
# manuscript depend on. $predictions holds 1095-length PREDICTION vectors --
# model output, not measurements, and they cannot reconstruct the truth.
b <- read_b("case_cerrado_results")
b$profiles <- NULL
b$emb_cols <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "case_cerrado_results")
note("case_cerrado_results", "$profiles (1095 x 70), $emb_cols",
     "real WoSIS profiles with coordinates, survey codes and 250 CC BY-NC rows")

# -- 13. causal_cerrado_real_v2 ----------------------------------------------
# Also originally slated for deletion. vignettes/edaphos-paper.Rmd reads eight
# aggregate elements from it ($n_profiles, $iv, $effects, $simpson, $encoder,
# $dag, $sources) and only $profiles is the payload.
b <- read_b("causal_cerrado_real_v2")
b$profiles <- NULL
b$strip_note <- STRIP_NOTE
write_b(b, "causal_cerrado_real_v2")
note("causal_cerrado_real_v2", "$profiles (3077 x 11)",
     "the widest real WoSIS pull in the package: 2872 distinct coordinates")

# -- report ------------------------------------------------------------------
tab <- do.call(rbind, removed)
utils::write.csv(tab, file.path("data-raw", "build", "stripped_elements.csv"),
                 row.names = FALSE)
for (i in seq_len(nrow(tab)))
  message(sprintf("%-34s -- removed %s", tab$bundle[i], tab$removed[i]))
message(sprintf("\n%d bundles rewritten", nrow(tab)))

# -- provenance ---------------------------------------------------------------
# Every bundle rewritten above now has bytes this script produced, not its
# original generator. Leaving the old $provenance$script in place would make
# the block a lie -- and edaphos_provenance_check() would correctly call it
# stale. So each stripped bundle records THIS script as its producer, keeping
# the original generator alongside so the chain is not lost.
STRIP_SCRIPT <- file.path("data-raw", "strip_third_party_records.R")
h <- edaphos:::.script_hash(STRIP_SCRIPT)

for (n in tab$bundle) {
  f <- file.path(EXT, paste0(n, ".rds"))
  if (!file.exists(f)) next
  b <- readRDS(f)
  if (is.null(b$provenance)) b$provenance <- list()
  b$provenance$built_from  <- b$provenance$script %||% NA_character_
  b$provenance$built_from_sha256 <- b$provenance$script_sha256 %||% NA_character_
  b$provenance$script        <- STRIP_SCRIPT
  b$provenance$script_sha256 <- unname(h[["hash"]])
  b$provenance$hash_algo     <- unname(h[["algo"]])
  b$provenance$built_at      <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  saveRDS(b, f, version = 3, compress = "xz")
}
message(sprintf("provenance re-pointed on %d bundles", length(tab$bundle)))
