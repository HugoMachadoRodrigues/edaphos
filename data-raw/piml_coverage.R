#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_coverage.R
#
# Does Pillar 2's predictive interval mean anything?
#
# This paper argues that coverage belongs beside accuracy, and that a method
# can be simultaneously more confident and less correct. Pillar 2 is the
# pillar it spends most of its pages on, and every number reported for it is
# an error statistic: RMSE, MAE, ME, CCC. Nothing has ever said whether its
# interval covers.
#
# WHY THIS IS ONLY NOW AFFORDABLE. Three earlier attempts were abandoned on
# cost, and the cause was not the sampler. `.piml_rhat_ess()` recomputed
# stats::acf() inside the Geyer loop at a growing lag.max, so the DIAGNOSTIC
# cost 197 s of a 202 s fit -- quadratic in exactly the quantity that signals
# failure. With acf() hoisted out, the worst profile went from 199 s to 7 s.
#
# WHAT IS SCORED, AND ON WHAT. The interval is scored where the benchmark
# scores the point prediction: on the held-out deepest horizon, over profiles
# whose TRAINING horizons are monotone -- the declared domain, judged without
# reading the horizon being predicted. It is the predictive interval for a
# future OBSERVATION, which is what a held-out laboratory value is, not the
# interval for the mean function.
#
# MCMC, not Laplace, because the Laplace path was measured to be too
# light-tailed on this model (five of seven intervals narrower, the
# observation noise by 1.8x); scoring its coverage would measure the
# approximation rather than the pillar.
#
# AND THE HALF THAT MATTERS MOST. On a 60-profile sample, only 25% of these
# fits genuinely converge, and the failures concentrate in profiles with three
# or four horizons against four free parameters -- 71% of the eligible
# archive. A coverage rate computed over all of them would average a
# meaningful interval with a meaningless one. So coverage is reported BOTH
# ways: over every fit, and over the converged subset, with the fraction
# stated. Neither number is the whole answer and presenting either alone
# would be a choice about which story to tell.
#
# Output: inst/extdata/piml_coverage.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
set.seed(11L)

NOMINAL <- 0.90
N_COV   <- 150L

D <- readRDS("inst/extdata/piml_wosis_cerrado.rds")
H <- D$horizons

split_profile <- function(s) {
  s <- s[order(s$top), ]
  list(train = s[-nrow(s), , drop = FALSE], test = s[nrow(s), , drop = FALSE])
}
profs <- split(H, H$profile_id)
profs <- profs[vapply(profs, nrow, 0L) >= 4L]
dom <- profs[vapply(profs, function(s)
  all(diff(split_profile(s)$train$soc_g_kg) <= 0), TRUE)]
message(sprintf("%d profiles with >= 4 horizons, %d in the declared domain",
                length(profs), length(dom)))

sel <- sample(names(dom), min(N_COV, length(dom)))
message(sprintf("scoring the %.0f%% predictive interval on %d of them ...",
                100 * NOMINAL, length(sel)))

t_start <- Sys.time()
rows <- lapply(seq_along(sel), function(k) {
  s  <- split_profile(dom[[sel[k]]])
  tr <- s$train; te <- s$test
  t0 <- Sys.time()
  f <- tryCatch(
    piml_profile_fit_bayesian(tr$depth_mid, tr$soc_g_kg,
                              top = tr$top, bottom = tr$bottom,
                              method = "mcmc", seed = 11L),
    error = function(e) NULL)
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (k %% 10 == 0 || k == length(sel))
    message(sprintf("  %d/%d  (%.1fs this one, %.1f min elapsed)",
                    k, length(sel), el,
                    as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
  if (is.null(f)) return(NULL)
  pp <- tryCatch(
    predict(f, newdepths = te$depth_mid, interval = NOMINAL,
            include_obs_noise = TRUE, seed = 11L),
    error = function(e) NULL)
  if (is.null(pp)) return(NULL)
  v <- piml_bayes_converged(f)
  data.frame(profile_id = sel[k], n_train = nrow(tr),
             depth = te$depth_mid, truth = te$soc_g_kg,
             mean = pp$mean, lo = pp$lower, hi = pp$upper,
             max_rhat = max(f$diagnostics$rhat),
             min_ess  = min(f$diagnostics$ess),
             accept   = mean(f$accept_rate),
             converged = isTRUE(v$ok),
             secs = el, stringsAsFactors = FALSE)
})
CV <- do.call(rbind, rows[!vapply(rows, is.null, TRUE)])

CV$covered <- CV$truth >= CV$lo & CV$truth <= CV$hi
CV$width   <- CV$hi - CV$lo
# Interval score (Gneiting & Raftery 2007): width plus a penalty per miss, so
# coverage cannot be bought with width alone. Lower is better.
alpha <- 1 - NOMINAL
CV$int_score <- CV$width +
  (2 / alpha) * (CV$lo - CV$truth) * (CV$truth < CV$lo) +
  (2 / alpha) * (CV$truth - CV$hi) * (CV$truth > CV$hi)

ok <- CV$converged
cat(sprintf("\n=== the %.0f%% predictive interval on the held-out deepest horizon ===\n",
            100 * NOMINAL))
cat(sprintf("%d profiles scored; %d converged (%.0f%%); total %.1f min, median %.1fs per fit\n",
            nrow(CV), sum(ok), 100 * mean(ok),
            as.numeric(difftime(Sys.time(), t_start, units = "mins")),
            stats::median(CV$secs)))
cat(sprintf("PICP  all fits %.3f   converged only %.3f   (nominal %.2f)\n",
            mean(CV$covered), mean(CV$covered[ok]), NOMINAL))
cat(sprintf("MPIW  all fits %.2f    converged only %.2f  g/kg\n",
            mean(CV$width), mean(CV$width[ok])))
cat(sprintf("median interval score  all %.2f   converged %.2f\n",
            stats::median(CV$int_score), stats::median(CV$int_score[ok])))

# By depth. A pooled rate can hide an interval that is right shallow and wrong
# deep, which is exactly how an extrapolating depth model would fail.
brk <- c(0, 50, 100, 200, Inf)
CV$band <- cut(CV$depth, brk, right = FALSE,
               labels = c("0-50", "50-100", "100-200", ">200"))
strat <- do.call(rbind, lapply(levels(CV$band), function(b) {
  x <- CV[CV$band == b, ]; xo <- x[x$converged, ]
  if (!nrow(x)) return(NULL)
  data.frame(band = b, n = nrow(x), n_conv = nrow(xo),
             picp = mean(x$covered),
             picp_conv = if (nrow(xo)) mean(xo$covered) else NA_real_,
             mpiw = mean(x$width),
             int_score = stats::median(x$int_score),
             stringsAsFactors = FALSE)
}))
cat("\nby depth of the held-out horizon:\n")
print(strat, row.names = FALSE, digits = 3)

# And by how much data the fit had, which is what decides convergence.
CV$nband <- ifelse(CV$n_train <= 4L, "3-4 horizons", "5+ horizons")
byn <- do.call(rbind, lapply(unique(CV$nband), function(b) {
  x <- CV[CV$nband == b, ]
  data.frame(horizons = b, n = nrow(x), conv_rate = mean(x$converged),
             picp = mean(x$covered), mpiw = mean(x$width),
             stringsAsFactors = FALSE)
}))
cat("\nby training-set size:\n")
print(byn[order(byn$horizons), ], row.names = FALSE, digits = 3)

saveRDS(list(
             # Binds this bundle to the script that made it: see R/provenance.R.
             provenance = edaphos_provenance(),
             coverage = CV, by_depth = strat, by_horizons = byn,
             nominal = NOMINAL, n_domain = length(dom),
             built_by = "data-raw/piml_coverage.R"),
        "inst/extdata/piml_coverage.rds")
message("\nwrote inst/extdata/piml_coverage.rds")
