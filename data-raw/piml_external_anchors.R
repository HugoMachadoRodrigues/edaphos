#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_external_anchors.R
#
# Do the fitted parameters mean what the mechanism says they mean?
#
# Pillar 2 claims its parameters are identified and interpretable. Identified
# it demonstrates; interpretable it asserts. Nothing in the package has ever
# confronted a fitted parameter with a quantity from outside the fit, so
# "y(Inf) is the mineral-associated floor" and "z_r is a rooting depth scale"
# have been labels rather than findings.
#
# This script tests two DIRECTIONAL predictions that the mechanism makes and a
# curve-fitting device does not. Both are falsifiable, and both are reported
# whichever way they come out.
#
#   ANCHOR 1 -- Hassink saturation.
#   Hassink (1997) showed that the capacity of a soil to preserve carbon in
#   association with the fine (< 20 um) fraction rises with the mass of that
#   fraction. If y(Inf) really is a mineral-associated floor, it must increase
#   with clay + silt. If it is only a shape parameter, there is no reason it
#   should.
#
#   ANCHOR 2 -- Jobbagy & Jackson depth distribution.
#   Jobbagy & Jackson (2000) summarise the vertical distribution of soil carbon
#   by beta in Y(d) = 1 - beta^d, where Y is the cumulative fraction above
#   depth d. beta is a whole-profile shape statistic derived independently of
#   any of our parameters. Our fitted depth function implies a beta; if the fit
#   is describing the same object the depth-function literature describes, the
#   implied beta should be a plausible soil value rather than an arbitrary one,
#   and it should shift with vegetation cover.
#
# WHAT THE COVARIATES ARE. Clay, sand and tree cover come from SoilGrids and
# Copernicus via inst/extdata/causal_cerrado_real_v2.rds, matched to the
# nearest profile. They are PREDICTIONS, not measurements, and SoilGrids is
# itself trained partly on WoSIS -- so a relation found here is weaker evidence
# than one found against measured texture. It is stated as such rather than
# quietly treated as ground truth.
#
# Output: inst/extdata/piml_external_anchors.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
set.seed(11)

D <- readRDS("inst/extdata/piml_wosis_cerrado.rds")
H <- D$horizons

message("fitting the depth function at every profile ...")
fits <- lapply(split(H, H$profile_id), function(s) {
  s <- s[order(s$top), ]
  a <- tryCatch(piml_profile_fit(s$depth_mid, s$soc_g_kg,
                                 top = s$top, bottom = s$bottom),
                error = function(e) NULL)
  m <- tryCatch(piml_profile_fit_mechanistic(s$depth_mid, s$soc_g_kg,
                                             top = s$top, bottom = s$bottom),
                error = function(e) NULL)
  if (is.null(a) || is.null(m)) return(NULL)
  data.frame(profile_id = s$profile_id[1], x = s$x[1], y = s$y[1],
             n_hor = nrow(s), z_max = max(s$bottom),
             monotone = all(diff(s$soc_g_kg) <= 0),
             # attenuating-rate form
             y0 = a$params$y0, y_asym = .piml_asymptote(a$params),
             # derived form: A is the mineral-associated floor by construction,
             # z_r the rooting depth scale
             A = m$params$A, B = m$params$B, z_r = m$params$z_r,
             lambda = m$params$lambda,
             stringsAsFactors = FALSE)
})
FP <- do.call(rbind, fits[!vapply(fits, is.null, TRUE)])
FP <- FP[stats::complete.cases(FP), ]
message(sprintf("  %d profiles fitted", nrow(FP)))

# --- the implied Jobbagy-Jackson beta --------------------------------------
#
# Y(d) = cumulative carbon above d, normalised at 100 cm; fit 1 - beta^d by
# least squares on d = 1..100 cm.
#
# CAVEAT, stated because it matters: Jobbagy & Jackson work in carbon CONTENT,
# which needs bulk density. WoSIS serves bulk density for only 8 of these 1,105
# profiles, so the cumulative here is of CONCENTRATION, i.e. it assumes density
# constant with depth. Density generally rises with depth, so this
# under-weights deep carbon and biases the implied beta DOWNWARD (a shallower
# apparent distribution). The size of that bias is measured below on the eight
# profiles that carry density.
implied_beta <- function(pars, d_max = 100, rho = NULL) {
  d <- seq_len(d_max)
  conc <- .piml_solution(d - 0.5, pars)              # mid-point of each cm
  w <- if (is.null(rho)) rep(1, d_max) else rho(d - 0.5)
  cum <- cumsum(conc * w)
  Y <- cum / cum[d_max]
  obj <- function(lb) {
    beta <- stats::plogis(lb)                        # keep beta in (0, 1)
    sum((Y - (1 - beta^d))^2)
  }
  o <- stats::optimize(obj, c(-10, 10))
  stats::plogis(o$minimum)
}

message("computing the implied Jobbagy-Jackson beta ...")
FP$beta <- vapply(seq_len(nrow(FP)), function(i) {
  p <- list(lambda0 = NA, mu = NA, y_inf = NA, y0 = FP$y0[i])
  # rebuild the attenuating-rate parameters for .piml_solution
  s <- H[H$profile_id == FP$profile_id[i], ]; s <- s[order(s$top), ]
  f <- piml_profile_fit(s$depth_mid, s$soc_g_kg, top = s$top, bottom = s$bottom)
  implied_beta(f$params)
}, numeric(1))

# How much does the constant-density assumption cost? Measure it where density
# is available rather than asserting the direction.
bd_ok <- D$profiles$profile_id[D$profiles$has_bd]
bd_cmp <- NULL
if (length(bd_ok) >= 3L) {
  bd_cmp <- do.call(rbind, lapply(intersect(bd_ok, FP$profile_id), function(pid) {
    s <- H[H$profile_id == pid, ]; s <- s[order(s$top), ]
    f <- piml_profile_fit(s$depth_mid, s$soc_g_kg, top = s$top, bottom = s$bottom)
    # step density from the horizons, held constant within each
    rho_fun <- function(z) {
      i <- findInterval(z, s$top, rightmost.closed = TRUE)
      i[i < 1] <- 1; i[i > nrow(s)] <- nrow(s)
      s$bd_g_cm3[i]
    }
    data.frame(profile_id = pid,
               beta_conc = implied_beta(f$params),
               beta_mass = implied_beta(f$params, rho = rho_fun),
               stringsAsFactors = FALSE)
  }))
}

# --- join the covariates ---------------------------------------------------
CAU <- readRDS("inst/extdata/causal_cerrado_real_v2.rds")$profiles
nn <- vapply(seq_len(nrow(FP)), function(i)
  which.min((CAU$lon - FP$x[i])^2 + (CAU$lat - FP$y[i])^2), integer(1))
FP$clay  <- CAU$clay[nn]
FP$sand  <- CAU$sand[nn]
FP$trees <- CAU$trees[nn]
FP$map   <- CAU$map[nn]
FP$fines <- pmax(0, 100 - FP$sand)     # clay + silt, the Hassink fraction
# .gc_km() is the package's single great-circle formula; using sp here
# instead would reintroduce the two-implementations problem that helper
# exists to remove.
FP$nn_km <- vapply(seq_len(nrow(FP)), function(i)
  .gc_km(cbind(FP$x[i], FP$y[i]),
         cbind(CAU$lon[nn[i]], CAU$lat[nn[i]]))[1, 1], numeric(1))

# Only trust a covariate match that is actually near the profile.
FP$cov_ok <- FP$nn_km <= 5
message(sprintf("  covariate match within 5 km: %d of %d profiles",
                sum(FP$cov_ok), nrow(FP)))

# --- ANCHOR 1: does the deep floor rise with the fine fraction? -------------
A1 <- FP[FP$cov_ok & FP$monotone & is.finite(FP$A) & FP$A > 0, ]
m1 <- stats::lm(log(A) ~ fines, data = A1)
ct1 <- summary(m1)$coefficients
sp1 <- suppressWarnings(stats::cor.test(A1$fines, A1$A, method = "spearman"))
# The same test on the attenuating-rate model's attained value, which carries
# the same interpretation.
m1b <- stats::lm(log(y_asym) ~ fines, data = A1[A1$y_asym > 0, ])

cat("\n=== ANCHOR 1: Hassink -- does the mineral-associated floor rise with clay+silt? ===\n")
cat(sprintf("n = %d monotone profiles with a covariate match within 5 km\n", nrow(A1)))
cat(sprintf("  log(A) ~ clay+silt : slope %+.5f per %% (SE %.5f), t = %+.2f, p = %.3g\n",
            ct1[2, 1], ct1[2, 2], ct1[2, 3], ct1[2, 4]))
cat(sprintf("  Spearman rho       : %+.3f (p = %.3g)\n", sp1$estimate, sp1$p.value))
cat(sprintf("  same test on y(Inf): slope %+.5f, p = %.3g\n",
            summary(m1b)$coefficients[2, 1], summary(m1b)$coefficients[2, 4]))
cat(sprintf("  R-squared          : %.4f\n", summary(m1)$r.squared))
cat(sprintf("  >> Hassink predicts a POSITIVE slope. Observed: %s (%s)\n",
            if (ct1[2, 1] > 0) "positive" else "NEGATIVE",
            if (ct1[2, 4] < 0.05) "significant" else "not significant"))

# --- ANCHOR 2: is the implied beta a plausible soil value, and does it move? -
A2 <- FP[FP$monotone & is.finite(FP$beta), ]
qb <- stats::quantile(A2$beta, c(0.05, 0.25, 0.5, 0.75, 0.95))
A2c <- A2[A2$cov_ok, ]
m2 <- stats::lm(beta ~ trees, data = A2c)
ct2 <- summary(m2)$coefficients

cat("\n=== ANCHOR 2: Jobbagy-Jackson -- the implied depth-distribution beta ===\n")
cat(sprintf("n = %d monotone profiles\n", nrow(A2)))
cat(sprintf("  beta quantiles 5/25/50/75/95: %s\n",
            paste(sprintf("%.4f", qb), collapse = "  ")))
cat(sprintf("  beta ~ tree cover: slope %+.5f (p = %.3g), n = %d\n",
            ct2[2, 1], ct2[2, 4], nrow(A2c)))
if (!is.null(bd_cmp)) {
  cat(sprintf("\n  constant-density assumption, measured on %d profiles with density:\n",
              nrow(bd_cmp)))
  cat(sprintf("    beta from concentration %.4f vs from mass %.4f (median diff %+.4f)\n",
              stats::median(bd_cmp$beta_conc), stats::median(bd_cmp$beta_mass),
              stats::median(bd_cmp$beta_mass - bd_cmp$beta_conc)))
}

saveRDS(list(profiles = FP, hassink = list(model = m1, model_yasym = m1b,
                                           spearman = sp1, n = nrow(A1)),
             beta = list(quantiles = qb, model_trees = m2, n = nrow(A2)),
             bd_check = bd_cmp,
             built_by = "data-raw/piml_external_anchors.R"),
        "inst/extdata/piml_external_anchors.rds")
message("\nwrote inst/extdata/piml_external_anchors.rds")
