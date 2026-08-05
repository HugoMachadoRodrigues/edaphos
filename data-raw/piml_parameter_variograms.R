#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_parameter_variograms.R
#
# Can the pedogenetic ODE be used for MAPPING?
#
# A pedometrician handed a per-pedon depth model reaches for the obvious
# two-stage workflow: fit the ODE at every profile, then krige its parameters
# to make a continuous map of the depth function. That workflow only works if
# the fitted parameters are spatially structured. If they are pure nugget, the
# two-stage approach is dead on arrival and the only route to a map is a
# one-stage hierarchical model in which the parameters are regressed on
# covariates and share a spatial random effect.
#
# The panel's geostatistician asked for exactly this test and predicted it
# would fail. Nobody in this repository had run it. This script does, on all
# 1,105 real multi-horizon WoSIS Cerrado profiles, and reports whatever it
# says.
#
# What it computes, per parameter:
#   * the empirical variogram of the fitted value across profiles
#   * a fitted exponential model, and from it the nugget-to-sill ratio
#   * the same for the residuals after regressing the parameter on the
#     covariates a DSM model would have (climate, terrain) -- because a
#     parameter that is spatially structured ONLY through its covariates is
#     mappable by regression, not by kriging
#
# The nugget-to-sill ratio is the number that decides it. Cambardella et al.
# (1994) call < 25% strong spatial dependence, 25-75% moderate, > 75% weak.
#
# Output: inst/extdata/piml_parameter_variograms.rds
# ---------------------------------------------------------------------------

suppressMessages({
  pkgload::load_all(".", quiet = TRUE)
  library(gstat)
  library(sp)
})

set.seed(11)
D <- readRDS("inst/extdata/piml_wosis_cerrado.rds")
H <- D$horizons
P <- D$profiles

message("fitting the ODE at every profile ...")
fits <- lapply(split(H, H$profile_id), function(s) {
  s <- s[order(s$top), ]
  f <- tryCatch(piml_profile_fit(s$depth_mid, s$soc_g_kg,
                                 top = s$top, bottom = s$bottom),
                error = function(e) NULL)
  if (is.null(f)) return(NULL)
  data.frame(profile_id = s$profile_id[1], x = s$x[1], y = s$y[1],
             log_y0     = log(f$params$y0),
             log_y_asym = log(.piml_asymptote(f$params)),
             log_kappa  = log(f$params$kappa),
             log_mu     = log(f$params$mu),
             monotone   = all(diff(s$soc_g_kg) <= 0),
             stringsAsFactors = FALSE)
})
FP <- do.call(rbind, fits[!vapply(fits, is.null, TRUE)])
FP <- FP[stats::complete.cases(FP) & apply(is.finite(as.matrix(
  FP[, c("log_y0", "log_y_asym", "log_kappa", "log_mu")])), 1, all), ]
message(sprintf("  %d profiles fitted", nrow(FP)))

# Deduplicate coincident locations: WoSIS serves some profiles twice at the
# same coordinates, and gstat cannot form a variogram with zero-distance pairs.
FP <- FP[!duplicated(FP[, c("x", "y")]), ]
message(sprintf("  %d at distinct locations", nrow(FP)))

PARS <- c(log_y0 = "log y0", log_y_asym = "log y(Inf)",
          log_kappa = "log kappa", log_mu = "log mu")

sp_df <- FP
sp::coordinates(sp_df) <- ~ x + y
sp::proj4string(sp_df) <- sp::CRS("+proj=longlat +datum=WGS84")

# Cutoff at a third of the maximum separation, the usual rule: beyond that the
# lag classes carry too few, too-eccentric pairs.
#
# UNITS. With a geographic CRS, gstat computes great-circle distances in
# KILOMETRES, not in the degrees the coordinates are stored in. A cutoff taken
# from dist() on lon/lat is therefore about a hundred times too small, and the
# first version of this script formed its variograms from 149 point pairs out
# of 561,270 -- a "no spatial structure" conclusion drawn from almost no data.
# The cutoff is computed in km, and the pair count is checked below.
.samp  <- as.matrix(FP[sample(nrow(FP), min(1200L, nrow(FP))), c("x", "y")])
.dmax  <- max(.gc_km(.samp))          # the package's one great-circle formula
CUTOFF <- .dmax / 3; NLAGS <- 18
message(sprintf("  max separation %.0f km -> cutoff %.0f km, %d lags",
                .dmax, CUTOFF, NLAGS))

one <- function(v, label) {
  vg <- gstat::variogram(stats::as.formula(paste(v, "~ 1")), sp_df,
                         cutoff = CUTOFF, width = CUTOFF / NLAGS)
  # Try several starting ranges and keep the best CONVERGED fit. A single
  # start silently returns a non-converged model, whose nugget ratio is not a
  # measurement of anything -- three of four did exactly that on the first run
  # of this script.
  best <- NULL; conv <- FALSE
  v0 <- stats::var(FP[[v]])
  for (r0 in CUTOFF * c(0.05, 0.15, 0.3, 0.6)) {
    init <- gstat::vgm(psill = 0.5 * v0, model = "Exp", range = r0,
                       nugget = 0.5 * v0)
    fm <- withCallingHandlers(
      tryCatch(gstat::fit.variogram(vg, init), error = function(e) NULL),
      warning = function(w) invokeRestart("muffleWarning"))
    if (is.null(fm) || nrow(fm) < 2) next
    ok <- isTRUE(attr(fm, "singular") == FALSE) &&
          !isTRUE(grepl("No convergence", attr(fm, "fit.message") %||% ""))
    sse <- attr(fm, "SSErr")
    if (is.null(best) || (is.finite(sse) && sse < attr(best, "SSErr"))) {
      best <- fm; conv <- ok
    }
  }
  if (is.null(best)) {
    return(list(name = v, label = label, vg = vg, model = NULL, converged = FALSE,
                nugget = NA_real_, psill = NA_real_, range = NA_real_,
                nugget_ratio = NA_real_))
  }
  nug <- best$psill[best$model == "Nug"]
  psl <- best$psill[best$model != "Nug"]
  rng <- best$range[best$model != "Nug"]
  # The range must lie INSIDE the window the data can see, at both ends.
  #
  # Beyond the cutoff, the variogram has not reached a sill and the range is an
  # extrapolation. Below the first lag distance, it is equally unidentified in
  # the other direction: no pair of profiles is that close, so the fitted rise
  # from the origin is interpolated through empty space. On these data the
  # first lag is ~55 km and two parameters fit ranges of 9 and 12 km, which
  # look like strong spatial dependence and are in fact an artefact of a
  # zero-nugget fit reaching for a sill it attains before the data begin.
  lag1 <- min(vg$dist)
  in_window <- is.finite(rng) && rng <= CUTOFF && rng >= lag1
  list(name = v, label = label, vg = vg, model = best, lag1 = lag1,
       converged = conv, range_in_window = in_window,
       nugget = nug, psill = psl, range = rng,
       nugget_ratio = if (conv && in_window) nug / (nug + psl) else NA_real_)
}

message("empirical variograms of the fitted parameters ...")
raw <- lapply(names(PARS), function(v) one(v, PARS[[v]]))
names(raw) <- names(PARS)

# A variogram is only as good as the pairs behind it. Refuse to proceed on a
# handful, which is exactly the failure this script shipped on its first run.
.npairs <- sum(raw[[1L]]$vg$np)
message(sprintf("  point pairs inside the cutoff: %s of %s possible",
                format(.npairs, big.mark = ","),
                format(choose(nrow(FP), 2), big.mark = ",")))
if (.npairs < 0.05 * choose(nrow(FP), 2)) {
  stop("only ", .npairs, " point pairs fall inside the cutoff -- the cutoff ",
       "units are probably wrong (gstat uses km for a geographic CRS). ",
       "Refusing to report a variogram computed on this little data.",
       call. = FALSE)
}

# The covariate-residual version. If a parameter is spatially structured only
# through climate and terrain, a regression maps it and kriging adds nothing.
CAU <- readRDS("inst/extdata/causal_cerrado_real_v2.rds")$profiles
nn <- function(x0, y0) which.min((CAU$lon - x0)^2 + (CAU$lat - y0)^2)
idx <- vapply(seq_len(nrow(FP)), function(i) nn(FP$x[i], FP$y[i]), integer(1))
COV <- CAU[idx, c("map", "mat", "elev", "slope", "clay", "sand")]
names(COV) <- paste0("cov_", names(COV))
FP2 <- cbind(FP, COV)
FP2 <- FP2[stats::complete.cases(FP2), ]
sp2 <- FP2
sp::coordinates(sp2) <- ~ x + y
sp::proj4string(sp2) <- sp::CRS("+proj=longlat +datum=WGS84")

message("variograms of the covariate residuals ...")
resid_one <- function(v, label) {
  fml <- stats::as.formula(paste(v, "~ cov_map + cov_mat + cov_elev +",
                                 "cov_slope + cov_clay + cov_sand"))
  m <- stats::lm(fml, data = FP2)
  vg <- gstat::variogram(fml, sp2, cutoff = CUTOFF, width = CUTOFF / NLAGS)
  init <- gstat::vgm(psill = 0.5 * stats::var(stats::residuals(m)),
                     model = "Exp", range = 1,
                     nugget = 0.5 * stats::var(stats::residuals(m)))
  best <- NULL; conv <- FALSE
  v0 <- stats::var(stats::residuals(m))
  for (r0 in CUTOFF * c(0.05, 0.15, 0.3, 0.6)) {
    init <- gstat::vgm(psill = 0.5 * v0, model = "Exp", range = r0, nugget = 0.5 * v0)
    fm <- withCallingHandlers(
      tryCatch(gstat::fit.variogram(vg, init), error = function(e) NULL),
      warning = function(w) invokeRestart("muffleWarning"))
    if (is.null(fm) || nrow(fm) < 2) next
    ok <- isTRUE(attr(fm, "singular") == FALSE) &&
          !isTRUE(grepl("No convergence", attr(fm, "fit.message") %||% ""))
    if (is.null(best) || attr(fm, "SSErr") < attr(best, "SSErr")) { best <- fm; conv <- ok }
  }
  nug <- if (is.null(best)) NA_real_ else best$psill[best$model == "Nug"]
  psl <- if (is.null(best)) NA_real_ else best$psill[best$model != "Nug"]
  rng <- if (is.null(best)) NA_real_ else best$range[best$model != "Nug"]
  list(name = v, label = label, vg = vg, model = best, converged = conv,
       r2_covariates = summary(m)$r.squared,
       nugget_ratio = if (!is.null(best) && conv && is.finite(rng) && rng <= CUTOFF)
                        nug / (nug + psl) else NA_real_)
}
res <- lapply(names(PARS), function(v) resid_one(v, PARS[[v]]))
names(res) <- names(PARS)

tab <- do.call(rbind, lapply(names(PARS), function(v) data.frame(
  parameter        = PARS[[v]],
  sd               = stats::sd(FP[[v]]),
  converged        = isTRUE(raw[[v]]$converged),
  range_in_window  = isTRUE(raw[[v]]$range_in_window),
  first_lag_km     = raw[[v]]$lag1,
  nugget_ratio     = raw[[v]]$nugget_ratio,
  range_km        = raw[[v]]$range,
  cov_r2           = res[[v]]$r2_covariates,
  nugget_ratio_res = res[[v]]$nugget_ratio,
  stringsAsFactors = FALSE)))

cat("\n=== Is the fitted depth function mappable? ===\n")
cat(sprintf("cutoff %.0f km, %s point pairs.\n", CUTOFF,
            format(.npairs, big.mark = ",")))
cat("nugget_ratio = nugget / (nugget + partial sill).\n")
cat("Cambardella et al. (1994): <0.25 strong, 0.25-0.75 moderate, >0.75 weak.\n\n")
print(tab, row.names = FALSE, digits = 3)

nr <- tab$nugget_ratio[is.finite(tab$nugget_ratio)]
cat(sprintf("\nparameters with an identified variogram (converged, range inside\n"))
cat(sprintf("  the cutoff): %d of %d\n", sum(tab$converged & tab$range_in_window),
            nrow(tab)))
if (length(nr)) {
  cat(sprintf("  of those, median nugget ratio %.2f; weak (>0.75): %d\n",
              stats::median(nr), sum(nr > 0.75)))
}
cat("\nA parameter whose variogram does not reach a sill inside the observed\n")
cat("separations has no identified range, so 'fit the ODE then krige the\n")
cat("parameters' cannot be carried out for it on these data.\n")

saveRDS(list(params = FP, table = tab, raw = raw, residual = res,
             cutoff = CUTOFF, n_profiles = nrow(FP),
             built_by = "data-raw/piml_parameter_variograms.R"),
        "inst/extdata/piml_parameter_variograms.rds")
message("\nwrote inst/extdata/piml_parameter_variograms.rds")
