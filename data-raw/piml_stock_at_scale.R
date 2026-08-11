#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_stock_at_scale.R
#
# What a pedotransfer function does and does not buy.
#
# The manuscript owed a stock validation at scale and said it would need a PTF
# it had not built. data-raw/piml_ptf_bulk_density.R now builds one, on 166
# Cerrado horizons with measured density. This script spends it, and is
# careful about what the spending yields.
#
# WHAT A PTF CANNOT DO, stated first because it is the part most easily
# fudged. Validating an absolute stock needs a MEASURED stock to compare
# against. Where density is unmeasured, a PTF supplies it for the prediction
# AND would have to supply it for the "observation" too -- at which point the
# observation is a model output and the comparison validates nothing. So this
# script does not claim a stock validation over 935 profiles.
#
# WHAT IT CAN DO, in two parts:
#
#   PART 1 -- THE PRICE. On the 24 profiles that carry a measured density on
#   the held-out horizon, compute the stock error twice: once with the
#   measured density (the honest number, already reported in Table 8) and once
#   with the PTF's. The difference is what substituting the PTF costs, and it
#   is measured rather than assumed.
#
#   PART 2 -- THE COMPARISON AT SCALE. Over all domain profiles, score the
#   competing depth models in Mg/ha with the PTF supplying density to BOTH
#   sides. The absolute numbers are not validated stocks. What IS informative
#   is whether the RANKING survives the change of units at scale, because the
#   density error is common to every method and largely cancels in a paired
#   comparison. A ranking that flips here would mean the concentration result
#   does not carry to the quantity anyone maps.
#
# Output: inst/extdata/piml_stock_at_scale.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
set.seed(29L)

P <- readRDS("inst/extdata/piml_ptf_bulk_density.rds")
D <- readRDS("inst/extdata/piml_wosis_cerrado.rds")
H <- D$horizons
message(sprintf("PTF: %s, blocked RMSE %.4f g/cm3 (%.1f%% relative)",
                P$best, P$blocked_rmse, 100 * P$blocked_rel_rmse))

split_deepest <- function(s) {
  s <- s[order(s$top), ]
  list(train = s[-nrow(s), , drop = FALSE], test = s[nrow(s), , drop = FALSE])
}
profs <- split(H, H$profile_id)
profs <- profs[vapply(profs, nrow, 0L) >= 4L]
dom <- profs[vapply(profs, function(s)
  all(diff(split_deepest(s)$train$soc_g_kg) <= 0), TRUE)]
message(sprintf("%d profiles in the declared domain", length(dom)))

# ---------------------------------------------------------------------------
# PART 1 -- what does swapping the measured density for the PTF's cost?
# ---------------------------------------------------------------------------
SV <- readRDS("inst/extdata/piml_stock_validation.rds")
S <- SV$stock
S$bd_ptf <- P$predict(data.frame(soc_g_kg = S$conc_obs, depth_mid = S$depth,
                                 clay = NA_real_, sand = NA_real_))
# Where the fitted PTF needs texture the WoSIS horizon does not carry, the
# carbon-only form is what was selected, so this is not a gap being papered
# over -- it is the model that won the blocked comparison.
S$stock_obs_ptf <- S$conc_obs * S$bd_ptf * S$thickness * 0.1
S$stock_ode_ptf <- S$conc_hat * S$bd_ptf * S$thickness * 0.1

cat("\n=== PART 1: the price of the PTF, on the 24 profiles that can pay it ===\n")
cat(sprintf("measured density %.2f-%.2f g/cm3 | PTF density %.2f-%.2f\n",
            min(S$bd), max(S$bd), min(S$bd_ptf), max(S$bd_ptf)))
cat(sprintf("density error: RMSE %.4f g/cm3, MAE %.4f, bias %+.4f (%.1f%% relative)\n",
            sqrt(mean((S$bd_ptf - S$bd)^2)), mean(abs(S$bd_ptf - S$bd)),
            mean(S$bd_ptf - S$bd), 100 * sqrt(mean((S$bd_ptf - S$bd)^2)) / mean(S$bd)))
e_meas <- abs(S$stock_ode - S$stock_obs)
e_ptf  <- abs(S$stock_ode_ptf - S$stock_obs_ptf)
cat(sprintf("\nstock MAE with MEASURED density: %.3f Mg/ha\n", mean(e_meas)))
cat(sprintf("stock MAE with PTF density:      %.3f Mg/ha  (%+.1f%%)\n",
            mean(e_ptf), 100 * (mean(e_ptf) / mean(e_meas) - 1)))
cat(sprintf("correlation of the two error series: %.3f\n", stats::cor(e_meas, e_ptf)))

# ---------------------------------------------------------------------------
# PART 2 -- the method comparison in Mg/ha, at scale
# ---------------------------------------------------------------------------
message("\nscoring the depth models in stock units over the whole domain ...")
rows <- lapply(names(dom), function(pid) {
  s  <- split_deepest(dom[[pid]])
  tr <- s$train[!is.na(s$train$soc_g_kg), ]
  te <- s$test
  if (nrow(tr) < 3L || !is.finite(te$soc_g_kg) || !is.finite(te$bottom)) return(NULL)
  f <- tryCatch(piml_profile_fit(tr$depth_mid, tr$soc_g_kg,
                                 top = tr$top, bottom = tr$bottom),
                error = function(e) NULL)
  if (is.null(f)) return(NULL)
  conc_hat  <- .piml_layer_mean(te$top, te$bottom, f$params)
  conc_near <- tr$soc_g_kg[nrow(tr)]
  conc_mean <- mean(tr$soc_g_kg)
  thick <- te$bottom - te$top
  # ONE density per horizon, from the observed carbon, shared by every method.
  # Using each method's own predicted carbon to also predict its density would
  # let a method that under-predicts carbon be rewarded twice.
  bd <- P$predict(data.frame(soc_g_kg = te$soc_g_kg, depth_mid = te$depth_mid,
                             clay = NA_real_, sand = NA_real_))
  k <- bd * thick * 0.1
  data.frame(profile_id = pid, depth = te$depth_mid, thickness = thick, bd = bd,
             stock_obs  = te$soc_g_kg * k,
             stock_ode  = conc_hat  * k,
             stock_near = conc_near * k,
             stock_mean = conc_mean * k,
             stringsAsFactors = FALSE)
})
A <- do.call(rbind, rows[!vapply(rows, is.null, TRUE)])

sc <- function(p, o) c(RMSE = sqrt(mean((p - o)^2)), MAE = mean(abs(p - o)),
                       ME = mean(p - o))
M <- list(`edaphos ODE` = A$stock_ode,
          `copy nearest training horizon` = A$stock_near,
          `profile mean` = A$stock_mean)
tab <- do.call(rbind, lapply(names(M), function(nm) {
  v <- sc(M[[nm]], A$stock_obs)
  data.frame(method = nm, RMSE = v[["RMSE"]], MAE = v[["MAE"]], ME = v[["ME"]],
             stringsAsFactors = FALSE)
}))
tab <- tab[order(tab$MAE), ]

cat(sprintf("\n=== PART 2: %d profiles, held-out deepest horizon, Mg/ha ===\n", nrow(A)))
cat("(density is MODELLED on both sides, so these are not validated stocks --\n")
cat(" the ranking is what this tests)\n")
for (i in seq_len(nrow(tab)))
  cat(sprintf("  %-30s RMSE %8.3f  MAE %7.3f  ME %+8.3f\n",
              tab$method[i], tab$RMSE[i], tab$MAE[i], tab$ME[i]))

paired <- do.call(rbind, lapply(setdiff(names(M), "edaphos ODE"), function(nm) {
  a <- abs(A$stock_ode - A$stock_obs); b <- abs(M[[nm]] - A$stock_obs)
  w <- suppressWarnings(stats::wilcox.test(a, b, paired = TRUE))
  data.frame(vs = nm, ode_wins = sum(a < b), alt_wins = sum(b < a),
             p = w$p.value, stringsAsFactors = FALSE)
}))
cat("\npaired Wilcoxon on absolute error:\n")
for (i in seq_len(nrow(paired)))
  cat(sprintf("  vs %-30s ODE wins %3d, alt wins %3d, p = %.3g\n",
              paired$vs[i], paired$ode_wins[i], paired$alt_wins[i], paired$p[i]))

# Does the ranking match the concentration ranking on the SAME profiles?
B <- readRDS("inst/extdata/piml_depth_benchmark.rds")
ct <- B$extrapolation_monotone$table
ode_c  <- ct$MAE[grep("attenuating", ct$method)]
near_c <- ct$MAE[grep("copy nearest", ct$method)]
cat(sprintf("\nsame task in CONCENTRATION (Table 6): ODE MAE %.3f vs copy-nearest %.3f\n",
            ode_c, near_c))
cat(sprintf("ranking agrees across units: %s\n",
            (ode_c < near_c) == (tab$MAE[tab$method == "edaphos ODE"] <
                                 tab$MAE[tab$method == "copy nearest training horizon"])))

saveRDS(list(price = S, at_scale = A, table = tab, paired = paired,
             n_profiles = nrow(A),
             ptf = list(best = P$best, blocked_rmse = P$blocked_rmse,
                        blocked_rel_rmse = P$blocked_rel_rmse,
                        skill_vs_constant = P$aggregate$skill_vs_constant[1],
                        n_cal = P$calibration$n, n_prof = P$calibration$n_profiles,
                        n_latossolo = sum(grepl("^Latossolo",
                          readRDS("inst/extdata/soildata_uberaba_bd.rds")$horizons$soil_class))),
             built_by = "data-raw/piml_stock_at_scale.R"),
        "inst/extdata/piml_stock_at_scale.rds")
message("\nwrote inst/extdata/piml_stock_at_scale.rds")
