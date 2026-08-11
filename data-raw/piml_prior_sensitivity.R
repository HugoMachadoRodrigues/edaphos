#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_prior_sensitivity.R
#
# How much of the Pillar-2 posterior is the prior?
#
# The default prior is empirical Bayes and the source says so: three of its
# hyperparameters are functions of the response being fitted -- the deepest
# observation centres log y(Inf), the shallowest centres log y0, and sd(obs)
# scales sigma. That is circular, and a posterior built on it cannot be
# presented as though the data alone produced it.
#
# `piml_prior_literature()` is the non-circular alternative: its
# hyperparameters come from published depth-function work and it takes no
# data. Until now the comparison between the two was reported for ONE
# parameter, in a NEWS entry. This runs it for every parameter, on the pedon
# the manuscript reports, by MCMC on both sides so the comparison is not
# confounded with the Laplace approximation the paper has just stopped using.
#
# A third arm widens the literature prior by a factor of three on every scale,
# which answers a different question: if the non-circular prior is itself
# doing work, how much? A parameter whose posterior is stable across all three
# is one the nine horizons actually determine.
#
# Output: inst/extdata/piml_prior_sensitivity.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
set.seed(7L)

D <- readRDS("inst/extdata/piml_wosis_cerrado.rds")
src <- D$profiles[D$profiles$monotone_decreasing, ]
src <- src[order(-src$n_hor, -src$z_max), ]
PID <- src$profile_id[1]
ped <- D$horizons[D$horizons$profile_id == PID, ]
ped <- ped[order(ped$top), ]
message(sprintf("pedon %s: %d horizons to %g cm", PID, nrow(ped),
                max(ped$bottom)))

# The three priors. `NULL` means the package default, which is the
# empirical-Bayes one built from these very observations.
wide <- piml_prior_literature()
for (nm in grep("_sd$|_scale$", names(wide), value = TRUE)) wide[[nm]] <- wide[[nm]] * 3

ARMS <- list(
  `empirical Bayes (default)` = NULL,
  `literature`                = piml_prior_literature(),
  `literature, 3x wider`      = wide
)

fits <- lapply(names(ARMS), function(nm) {
  message("  fitting under: ", nm, " ...")
  # 60k rather than the 20k default: the widest arm mixes slowly (its first
  # run returned split-Rhat 1.035 and bulk ESS 177) and a comparison across
  # arms is only meaningful if all of them converged. Same budget for all
  # three so the arms differ in prior and nothing else.
  piml_profile_fit_bayesian(ped$depth_mid, ped$soc_g_kg,
                            top = ped$top, bottom = ped$bottom,
                            prior = ARMS[[nm]], method = "mcmc", seed = 7L,
                            n_iter = 60000L, n_burn = 20000L)
})
names(fits) <- names(ARMS)

conv <- do.call(rbind, lapply(names(fits), function(nm) {
  s <- fits[[nm]]$summary
  # NO na.rm: on an all-NA vector it returns -Inf / +Inf, which pass both
  # thresholds below. The diagnostics now encode failure as Inf / 0, so this
  # reduction fails safely -- but the na.rm has to go regardless, because it
  # would also silently drop a single degenerate coordinate.
  v <- piml_bayes_converged(fits[[nm]])
  data.frame(arm = nm, max_rhat = max(s$rhat), min_ess = min(s$ess),
             accept = mean(fits[[nm]]$accept_rate),
             converged = isTRUE(v$ok),
             reasons = paste(v$reasons, collapse = "; "),
             caveats = paste(v$caveats, collapse = "; "),
             stringsAsFactors = FALSE)
}))
message("\nconvergence:")
print(conv, row.names = FALSE, digits = 4)
# STOP, not warn. A warning in a batch script scrolls past, and this bundle
# feeds a published table. The earlier version of this check was also blind to
# a chain that never moved: it read max(rhat, na.rm = TRUE), which on all-NA
# diagnostics is -Inf, and -Inf > 1.01 is FALSE.
if (!all(conv$converged))
  stop("at least one arm did not converge, so the comparison is meaningless:\n  ",
       paste(sprintf("%s: %s", conv$arm[!conv$converged],
                     conv$reasons[!conv$converged]), collapse = "\n  "),
       call. = FALSE)

# --- the table --------------------------------------------------------------
params <- fits[[1]]$summary$parameter
tab <- do.call(rbind, lapply(params, function(p) {
  row <- data.frame(parameter = p, stringsAsFactors = FALSE)
  for (nm in names(fits)) {
    s <- fits[[nm]]$summary
    i <- which(s$parameter == p)
    row[[paste0("mean_", nm)]]  <- s$mean[i]
    row[[paste0("lo_", nm)]]    <- s$q2.5[i]
    row[[paste0("hi_", nm)]]    <- s$q97.5[i]
  }
  row
}))

# How far does the posterior mean move between the circular prior and the
# non-circular one, in units of the default posterior SD? Below ~0.25 the
# prior is not doing the work; above ~1 it is.
sd_def <- fits[[1]]$summary$sd[match(tab$parameter, fits[[1]]$summary$parameter)]
tab$shift_sd <- abs(tab$`mean_literature` -
                      tab$`mean_empirical Bayes (default)`) / sd_def
tab$width_ratio <- (tab$`hi_literature` - tab$`lo_literature`) /
  (tab$`hi_empirical Bayes (default)` - tab$`lo_empirical Bayes (default)`)

cat("\n=== prior sensitivity on the reported pedon (MCMC throughout) ===\n")
cat(sprintf("%-9s %26s %26s %8s %8s\n", "param",
            "empirical Bayes  mean [95%]", "literature  mean [95%]",
            "shift/sd", "width"))
for (i in seq_len(nrow(tab))) {
  cat(sprintf("%-9s %8.4f [%8.3f,%8.3f] %8.4f [%8.3f,%8.3f] %8.2f %8.2f\n",
              tab$parameter[i],
              tab$`mean_empirical Bayes (default)`[i],
              tab$`lo_empirical Bayes (default)`[i],
              tab$`hi_empirical Bayes (default)`[i],
              tab$`mean_literature`[i], tab$`lo_literature`[i],
              tab$`hi_literature`[i], tab$shift_sd[i], tab$width_ratio[i]))
}

moved <- tab$parameter[tab$shift_sd > 0.5]
cat(sprintf("\nparameters whose mean moves by more than half a posterior SD: %s\n",
            if (length(moved)) paste(moved, collapse = ", ") else "none"))
cat(sprintf("largest shift: %s at %.2f SD\n",
            tab$parameter[which.max(tab$shift_sd)], max(tab$shift_sd)))

# --- does y_inf have a posterior mean at all? -------------------------------
#
# "Unidentified" is usually shown by a wide interval. Something stronger is
# true here. y_inf = (A - y0 e^-kappa)/(1 - e^-kappa) has a pole at kappa -> 0,
# and the posterior puts mass arbitrarily close to it, so the further the
# sampler runs the further into that tail it reaches. If the mean existed, the
# estimate would settle as the budget grows. It does not.
#
# Reported as a budget sweep because that is the only honest way to say it: a
# single number for the posterior mean of y_inf is an artefact of how long we
# sampled, whereas the identified quantities settle by the second row.
message("\nsweeping the MCMC budget to test whether y_inf has a mean ...")
sweep <- do.call(rbind, lapply(c(20000L, 60000L, 120000L), function(n) {
  f <- piml_profile_fit_bayesian(ped$depth_mid, ped$soc_g_kg,
                                 top = ped$top, bottom = ped$bottom,
                                 method = "mcmc", seed = 7L,
                                 n_iter = n, n_burn = n %/% 3L)
  g <- function(p, c) f$summary[[c]][f$summary$parameter == p]
  data.frame(n_iter = n,
             y_inf_mean = g("y_inf", "mean"), y_inf_q2.5 = g("y_inf", "q2.5"),
             y_asym_mean = g("y_asym", "mean"), sigma_mean = g("sigma", "mean"),
             stringsAsFactors = FALSE)
}))
cat("\n=== does the posterior mean settle as the budget grows? ===\n")
print(sweep, row.names = FALSE, digits = 4)
cat(sprintf("\ny_inf mean moves %.1f%% from the first budget to the last;\n",
            100 * abs(sweep$y_inf_mean[3] / sweep$y_inf_mean[1] - 1)))
cat(sprintf("y(Inf) moves %.1f%% and sigma %.1f%% over the same sweep.\n",
            100 * abs(sweep$y_asym_mean[3] / sweep$y_asym_mean[1] - 1),
            100 * abs(sweep$sigma_mean[3] / sweep$sigma_mean[1] - 1)))

saveRDS(list(table = tab, convergence = conv, budget_sweep = sweep,
             profile_id = PID,
             n_horizons = nrow(ped), z_max = max(ped$bottom),
             arms = names(ARMS),
             built_by = "data-raw/piml_prior_sensitivity.R"),
        "inst/extdata/piml_prior_sensitivity.rds")
message("\nwrote inst/extdata/piml_prior_sensitivity.rds")
