## data-raw/make_fixtures.R
##
## Builds the two synthetic fixtures that examples, tests and vignettes run on:
##
##   inst/extdata/fixture_wosis_like.rds     -- WoSIS-shaped profiles/horizons
##   inst/extdata/fixture_soildata_like.rds  -- SoilData-shaped PTF calibration
##
## GENERATIVE PRINCIPLE. Every parameter below comes from published literature
## or is a round number chosen by hand. NOTHING here is fitted to, sampled
## from, or otherwise derived from the third-party bundles this package used
## to ship. That is deliberate and it is the whole point: a simulator fitted
## to 1105 real profiles is a lossy but real encoding of them, and "probably
## safe at 40 draws" is not the standard. The .slim_lm() defect in the old
## piml_external_anchors.rds -- a model object that still carried every record
## after its author believed it stripped -- is the argument against being
## clever here.
##
## Coordinates are a REGULAR LATTICE, not a random scatter. A lattice is
## self-evidently synthetic to anyone who plots it; a scatter is not, and can
## land on a real survey site by chance.
##
## Reproducible: set.seed below, recorded in $meta$seed. Re-running this script
## reproduces the DATA byte-for-byte; only $provenance$built_at differs, which
## the provenance contract requires. Compare with the $provenance element
## dropped if you want a byte check.
##
## Run from the package root:  source("data-raw/make_fixtures.R")

set.seed(20260901L)

SEED <- 20260901L
N_PROFILES <- 120L

# ---- literature parameters --------------------------------------------------
# Jackson RB et al. (1996) Oecologia 108:389-411 -- tropical savanna root
# distribution, beta = 0.972, giving an e-folding depth of -1/log(beta).
BETA_SAVANNA <- 0.972
Z_R <- -1 / log(BETA_SAVANNA)            # ~35.2 cm

# Surface SOC concentration: lognormal, median 25 g/kg. A textbook Cerrado
# Latossolo range (Bernoux et al. 2002; Batlle-Bayer et al. 2010), rounded.
Y0_MEDIAN <- 25
Y0_SDLOG  <- 0.6

# Deep asymptote: SOC does not decay to zero within the profile.
Y_ASYM_MEAN <- 3

# Bulk density from log SOC. Round published PTF form (bd = a + b*log1p(soc));
# a and b are hand-set round numbers, NOT the coefficients fitted to the
# 166-horizon third-party calibration set that used to ship here.
BD_A <- 1.55
BD_B <- -0.12

# ---- a regular lattice inside the Cerrado bounding box ----------------------
# 12 x 10. Sized so causal_dag_test(coords = ) can fit its thin-plate spline:
# below about 100 unique coordinate pairs mgcv refuses the term outright, which
# made man/causal_dag_test.Rd error under --run-donttest.
lons <- seq(-58, -44, length.out = 12L)
lats <- seq(-22, -6,  length.out = 10L)
grid <- expand.grid(lon = lons, lat = lats, KEEP.OUT.ATTRS = FALSE)
stopifnot(nrow(grid) == N_PROFILES)

pid <- sprintf("SYN_%03d", seq_len(N_PROFILES))

# ---- per-profile depth functions -------------------------------------------
y0     <- stats::rlnorm(N_PROFILES, meanlog = log(Y0_MEDIAN), sdlog = Y0_SDLOG)
y_asym <- stats::rgamma(N_PROFILES, shape = 4, rate = 4 / Y_ASYM_MEAN)
z_r    <- Z_R * stats::rlnorm(N_PROFILES, meanlog = 0, sdlog = 0.25)
n_hor  <- sample(4:8, N_PROFILES, replace = TRUE)

soc_at <- function(z, i) y_asym[i] + (y0[i] - y_asym[i]) * exp(-z / z_r[i])

# Ragged missingness, matching the shape of a real survey rather than a clean
# grid: bulk density is measured on a minority of profiles only. Code paths
# that handle NA stay exercised; a fixture with clean missingness silently
# deletes the coverage the old bundle provided.
has_bd <- rep(FALSE, N_PROFILES)
has_bd[sample(N_PROFILES, 24L)] <- TRUE

hor <- do.call(rbind, lapply(seq_len(N_PROFILES), function(i) {
  k    <- n_hor[i]
  brk  <- c(0, cumsum(round(stats::runif(k, 10, 45))))
  top  <- brk[-(k + 1L)]
  bot  <- brk[-1L]
  mid  <- (top + bot) / 2
  soc  <- soc_at(mid, i) * stats::rlnorm(k, 0, 0.08)
  bd   <- if (has_bd[i]) BD_A + BD_B * log1p(soc) + stats::rnorm(k, 0, 0.03) else NA_real_
  data.frame(
    profile_id  = pid[i],
    x           = grid$lon[i],
    y           = grid$lat[i],
    top         = top,
    bottom      = bot,
    soc_g_kg    = round(soc, 2),
    depth_mid   = mid,
    bd_g_cm3    = round(bd, 3),
    stock_mg_ha = round(soc * bd * (bot - top) * 0.1, 2),
    stringsAsFactors = FALSE
  )
}))

# A handful of horizons lose bulk density even on measured profiles.
drop_bd <- sample(which(!is.na(hor$bd_g_cm3)), max(1L, round(0.04 * nrow(hor))))
hor$bd_g_cm3[drop_bd]    <- NA_real_
hor$stock_mg_ha[drop_bd] <- NA_real_

# ---- profile summary, carrying BOTH schemas --------------------------------
# The piml_* columns keep the mechanistic examples working; the long covariate
# names are the nodes of causal_cerrado_real_dag(), so the DAG examples can
# still assert all(names(dag) %in% names(prof)).
agg <- function(f) vapply(split(hor, hor$profile_id), f, numeric(1))[pid]

clay  <- round(stats::runif(N_PROFILES, 15, 65), 1)
sand  <- round(pmax(5, 95 - clay - stats::runif(N_PROFILES, 5, 25)), 1)
trees <- round(stats::rbeta(N_PROFILES, 2, 3) * 100, 1)
crop  <- round(stats::rbeta(N_PROFILES, 1.5, 6) * (100 - trees), 1)

profiles <- data.frame(
  profile_id               = pid,
  x                        = grid$lon,
  y                        = grid$lat,
  lon                      = grid$lon,
  lat                      = grid$lat,
  n_hor                    = n_hor,
  z_max                    = agg(function(d) max(d$bottom)),
  soc_top                  = agg(function(d) d$soc_g_kg[which.min(d$depth_mid)]),
  soc_deepest              = agg(function(d) d$soc_g_kg[which.max(d$depth_mid)]),
  monotone_decreasing      = TRUE,
  monotone_without_deepest = TRUE,
  has_bd                   = has_bd,
  # DAG node names
  soc_topsoil_gkg          = agg(function(d) d$soc_g_kg[which.min(d$depth_mid)]),
  soilgrids_clay           = clay,
  soilgrids_sand           = sand,
  soilgrids_bdod           = round(BD_A + BD_B * log1p(agg(function(d) mean(d$soc_g_kg))), 3),
  wc_bio_01                = round(stats::runif(N_PROFILES, 21, 27), 2),
  wc_bio_12                = round(stats::runif(N_PROFILES, 900, 2000)),
  wc_landcover_trees       = trees,
  wc_landcover_cropland    = crop,
  wc_landcover_grassland   = round(pmax(0, 100 - trees - crop), 1),
  elev                     = round(stats::runif(N_PROFILES, 300, 1100)),
  slope                    = round(stats::rgamma(N_PROFILES, shape = 2, rate = 0.6), 2),
  stringsAsFactors         = FALSE
)
rownames(profiles) <- NULL

# ---- the deep demonstration pedon ------------------------------------------
# Nine horizons, so man/piml_prior_literature.Rd keeps its shape after
# capstone_campaign_results.rds$piml_profile_obs is dropped. The values are
# generated here and are NOT the nine measurements of the real pedon that used
# to ship; a test asserts they differ.
ped_top <- c(0, 12, 35, 60, 100, 150, 250, 350, 450)
ped_bot <- c(12, 35, 60, 100, 150, 250, 350, 450, 550)
ped_mid <- (ped_top + ped_bot) / 2
pedon <- data.frame(
  profile_id = "SYN_PEDON_01",
  top        = ped_top,
  bottom     = ped_bot,
  depth_mid  = ped_mid,
  soc_g_kg   = round(2.4 + (31.5 - 2.4) * exp(-ped_mid / 38), 2),
  stringsAsFactors = FALSE
)

SYNTHETIC_NOTE <- paste(
  "These are simulated values generated from published literature",
  "parameters. They are NOT measurements, and must not be used for",
  "inference or reported as data."
)

fixture_wosis_like <- list(
  profiles = profiles,
  horizons = hor,
  pedon    = pedon,
  meta     = list(
    synthetic    = TRUE,
    source       = "generated by data-raw/make_fixtures.R",
    seed         = SEED,
    n_profiles   = N_PROFILES,
    n_horizons   = nrow(hor),
    parameters   = list(beta_savanna = BETA_SAVANNA, z_r = Z_R,
                        y0_median = Y0_MEDIAN, y0_sdlog = Y0_SDLOG,
                        y_asym_mean = Y_ASYM_MEAN, bd_a = BD_A, bd_b = BD_B),
    references   = c("Jackson RB et al. (1996) Oecologia 108:389-411"),
    note         = SYNTHETIC_NOTE
  )
)

# ---- fixture 2: SoilData-shaped PTF calibration ----------------------------
n_sd  <- 30L
sd_lon <- seq(-47.5, -45.5, length.out = 6L)
sd_lat <- seq(-20.5, -18.5, length.out = 5L)
sd_grid <- expand.grid(lon = sd_lon, lat = sd_lat, KEEP.OUT.ATTRS = FALSE)
sd_pid <- sprintf("SYN-P%02d", seq_len(n_sd))

sd_rows <- do.call(rbind, lapply(seq_len(n_sd), function(i) {
  mid  <- c(10, 40)
  soc  <- round(soc_at(mid, ((i - 1L) %% N_PROFILES) + 1L) * stats::rlnorm(2, 0, 0.1), 2)
  bd   <- round(BD_A + BD_B * log1p(soc) + stats::rnorm(2, 0, 0.03), 3)
  cl   <- round(stats::runif(1, 20, 60), 1)
  si   <- round(stats::runif(1, 5, min(40, 99 - cl)), 1)
  data.frame(
    profile_id = sd_pid[i],
    lon = sd_grid$lon[i], lat = sd_grid$lat[i],
    depth_mid = mid, bd_g_cm3 = bd, soc_g_kg = soc,
    # fractions sum to exactly 100 -- a real-data tell the checking code looks
    # for, worth preserving even though these values are invented
    clay = cl, silt = si, sand = round(100 - cl - si, 1),
    ph_h2o = round(stats::runif(2, 4.5, 6.2), 2),
    stringsAsFactors = FALSE
  )
}))
stopifnot(all(abs(sd_rows$clay + sd_rows$silt + sd_rows$sand - 100) < 1e-9))

fixture_soildata_like <- list(
  horizons = sd_rows,
  meta = list(
    synthetic = TRUE,
    source    = "generated by data-raw/make_fixtures.R",
    seed      = SEED,
    note      = SYNTHETIC_NOTE
  )
)

# The provenance contract every other bundle honours: name the script that
# produced these bytes, and hash it.
.prov <- function() {
  h <- edaphos:::.script_hash(file.path("data-raw", "make_fixtures.R"))
  list(script          = file.path("data-raw", "make_fixtures.R"),
       script_sha256   = unname(h[["hash"]]),
       hash_algo       = unname(h[["algo"]]),
       package_version = as.character(utils::packageVersion("edaphos")),
       r_version       = paste(R.version$major, R.version$minor, sep = "."),
       built_at        = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
       seed            = SEED)
}
fixture_wosis_like$provenance    <- .prov()
fixture_soildata_like$provenance <- .prov()

saveRDS(fixture_wosis_like,
        file.path("inst", "extdata", "fixture_wosis_like.rds"),
        version = 3, compress = "xz")
saveRDS(fixture_soildata_like,
        file.path("inst", "extdata", "fixture_soildata_like.rds"),
        version = 3, compress = "xz")

message(sprintf("fixture_wosis_like.rds    %d profiles, %d horizons, %d-horizon pedon",
                nrow(profiles), nrow(hor), nrow(pedon)))
message(sprintf("fixture_soildata_like.rds %d profiles, %d horizons",
                n_sd, nrow(sd_rows)))
