#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_stock_validation.R
#
# Scoring Pillar 2 in the units that matter.
#
# Carbon STOCK, not concentration, is the quantity that is conserved, mapped
# and reported to inventories. Every number this package reports for Pillar 2
# is a concentration in g/kg, and the manuscript has said it cannot do better
# because WoSIS bulk density covers 3.9% of these horizons.
#
# That is true of the archive as a whole and too pessimistic as a statement
# about what can be TESTED -- but only just, and not on the task the
# concentration benchmark uses.
#
# WHICH TASK, AND WHY NOT THE OTHER ONE. The headline depth comparison holds
# out the DEEPEST horizon. Repeating it in stock units needs a measured
# density on that horizon, and exactly 2 profiles in this archive have one:
# not a test. So this uses the other pre-declared task, holding out an
# INTERIOR horizon, where 35 profiles qualify. That is interpolation rather
# than extrapolation and therefore an easier problem than the one Table 6
# reports; the numbers here are not comparable to it and are not presented as
# though they were.
#
# The conversion is deliberately minimal: the model's predicted CONCENTRATION
# is turned into a stock with the held-out horizon's own MEASURED density and
# thickness -- the same arithmetic the observation went through. So the only
# thing being scored is the depth function. No pedotransfer function is
# involved, which is the whole reason this is worth running: a stock error
# that came from a predicted density would be scoring the pedotransfer, not
# the pillar.
#
# Point fits only (piml_profile_fit), not the Bayesian path. A stock point
# error needs a point prediction, and the MCMC sweep this was originally part
# of turned out to cost hours; that question is being pursued separately.
#
# One held-out horizon per profile, so the test points are independent.
# Several profiles carry density on more than one horizon and holding out each
# in turn would inflate n without adding information about new soil. Of the 35
# profiles that qualify, 24 also have monotone training horizons -- the
# model's declared domain -- and those 24 are what is reported.
#
# Output: inst/extdata/piml_stock_validation.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
set.seed(11L)

D <- readRDS("inst/extdata/piml_wosis_cerrado.rds")
H <- D$horizons

# Hold out the INTERIOR horizon carrying a measured density that sits closest
# to the profile's mid-depth. Deterministic, so the choice is not a degree of
# freedom, and interior so the fit is never asked to extrapolate.
split_at <- function(s, i) {
  s <- s[order(s$top), ]
  list(train = s[-i, , drop = FALSE], test = s[i, , drop = FALSE])
}
pick_row <- function(s) {
  s <- s[order(s$top), ]
  if (nrow(s) < 4L) return(NA_integer_)
  cand <- seq(2L, nrow(s) - 1L)
  cand <- cand[!is.na(s$bd_g_cm3[cand]) & !is.na(s$stock_mg_ha[cand]) &
                 !is.na(s$soc_g_kg[cand])]
  if (!length(cand)) return(NA_integer_)
  mid <- (min(s$top) + max(s$bottom)) / 2
  cand[which.min(abs(s$depth_mid[cand] - mid))]
}

profs <- split(H, H$profile_id)
profs <- profs[vapply(profs, nrow, 0L) >= 4L]
HOLD <- vapply(profs, pick_row, integer(1))
have <- !is.na(HOLD)

# Domain: training horizons monotone, judged WITHOUT reading the held-out
# value. Same criterion the depth benchmark uses, for the same reason.
mono <- vapply(seq_along(profs), function(k) {
  if (!have[k]) return(FALSE)
  tr <- split_at(profs[[k]], HOLD[k])$train
  tr <- tr[!is.na(tr$soc_g_kg), ]
  nrow(tr) >= 3L && all(diff(tr$soc_g_kg) <= 0)
}, TRUE)

message(sprintf("%d profiles with >= 4 horizons; %d carry a measured density on an interior horizon; %d of those have monotone training horizons",
                length(profs), sum(have), sum(mono)))
ST_IN <- profs[mono]
HOLD  <- HOLD[mono]

rows <- lapply(seq_along(ST_IN), function(k) {
  pid <- names(ST_IN)[k]
  p  <- split_at(ST_IN[[k]], HOLD[k])
  tr <- p$train[!is.na(p$train$soc_g_kg), ]
  te <- p$test
  f <- tryCatch(piml_profile_fit(tr$depth_mid, tr$soc_g_kg,
                                 top = tr$top, bottom = tr$bottom),
                error = function(e) NULL)
  if (is.null(f)) return(NULL)

  thick <- te$bottom - te$top
  # Horizon-average of the fitted solution over the held-out horizon, which is
  # what a laboratory value for that horizon is.
  conc_hat <- .piml_layer_mean(te$top, te$bottom, f$params)

  data.frame(
    profile_id = pid, depth = te$depth_mid, thickness = thick,
    bd = te$bd_g_cm3, n_train = nrow(tr),
    conc_obs = te$soc_g_kg, conc_hat = conc_hat,
    stock_obs   = te$stock_mg_ha,
    stock_ode   = conc_hat * te$bd_g_cm3 * thick * 0.1,
    # Two zero-parameter baselines, the same ones the concentration benchmark
    # uses, converted identically.
    stock_last  = tr$soc_g_kg[which.min(abs(tr$depth_mid - te$depth_mid))] *
                    te$bd_g_cm3 * thick * 0.1,
    stock_mean  = mean(tr$soc_g_kg)     * te$bd_g_cm3 * thick * 0.1,
    stringsAsFactors = FALSE)
})
ST <- do.call(rbind, rows[!vapply(rows, is.null, TRUE)])

cat("\n=== held-out INTERIOR horizon, scored as carbon stock (Mg/ha) ===\n")
if (is.null(ST) || nrow(ST) < 5L) {
  cat("too few profiles carry a usable density; nothing reported\n")
  ST <- NULL
} else {
  cat(sprintf("n = %d profiles; held-out depth %g to %g cm; observed stock %.2f to %.2f Mg/ha\n",
              nrow(ST), min(ST$depth), max(ST$depth),
              min(ST$stock_obs), max(ST$stock_obs)))

  sc <- function(p, o) c(RMSE = sqrt(mean((p - o)^2)), MAE = mean(abs(p - o)),
                         ME = mean(p - o))
  METH <- list(`edaphos ODE` = ST$stock_ode,
               `copy nearest training horizon` = ST$stock_last,
               `profile mean` = ST$stock_mean)
  tab <- do.call(rbind, lapply(names(METH), function(nm) {
    s <- sc(METH[[nm]], ST$stock_obs)
    data.frame(method = nm, RMSE = s[["RMSE"]], MAE = s[["MAE"]],
               ME = s[["ME"]], stringsAsFactors = FALSE)
  }))
  tab <- tab[order(tab$MAE), ]
  for (i in seq_len(nrow(tab)))
    cat(sprintf("  %-30s RMSE %7.3f  MAE %7.3f  ME %+7.3f\n",
                tab$method[i], tab$RMSE[i], tab$MAE[i], tab$ME[i]))

  paired <- do.call(rbind, lapply(setdiff(names(METH), "edaphos ODE"), function(nm) {
    a <- abs(ST$stock_ode - ST$stock_obs)
    b <- abs(METH[[nm]] - ST$stock_obs)
    w <- suppressWarnings(stats::wilcox.test(a, b, paired = TRUE))
    data.frame(vs = nm, ode_wins = sum(a < b), alt_wins = sum(b < a),
               p = w$p.value, stringsAsFactors = FALSE)
  }))
  cat("\npaired Wilcoxon on absolute error:\n")
  for (i in seq_len(nrow(paired)))
    cat(sprintf("  vs %-30s ODE wins %2d, alt wins %2d, p = %.3g\n",
                paired$vs[i], paired$ode_wins[i], paired$alt_wins[i],
                paired$p[i]))

  # Does the stock ranking agree with the concentration ranking? If the ODE
  # wins on g/kg and loses on Mg/ha, the concentration result would not carry
  # to the quantity anyone maps -- worth knowing either way.
  cc <- sc(ST$conc_hat, ST$conc_obs)
  cl <- sc(ST$stock_last / (ST$bd * ST$thickness * 0.1), ST$conc_obs)
  cat(sprintf("\nsame profiles scored as CONCENTRATION (g/kg):\n"))
  cat(sprintf("  %-30s MAE %7.3f\n", "edaphos ODE", cc[["MAE"]]))
  cat(sprintf("  %-30s MAE %7.3f\n", "copy nearest training horizon", cl[["MAE"]]))
  cat(sprintf("  ranking agrees across units: %s\n",
              (cc[["MAE"]] < cl[["MAE"]]) ==
                (tab$MAE[tab$method == "edaphos ODE"] <
                   tab$MAE[tab$method == "copy nearest training horizon"])))

  cat(sprintf("\nWith %d profiles this is an indication, not a validation, and\n",
              nrow(ST)))
  cat("it is reported as one. What it replaces is a declared impossibility.\n")
}

saveRDS(list(
             # Binds this bundle to the script that made it: see R/provenance.R.
             provenance = edaphos_provenance(),
             stock = ST,
             n_eligible = sum(have), n_usable = length(ST_IN),
             task = "hold out an interior horizon carrying a measured density",
             n_horizons_total = nrow(H),
             frac_with_bd = mean(!is.na(H$bd_g_cm3)),
             built_by = "data-raw/piml_stock_validation.R"),
        "inst/extdata/piml_stock_validation.rds")
message("\nwrote inst/extdata/piml_stock_validation.rds")
