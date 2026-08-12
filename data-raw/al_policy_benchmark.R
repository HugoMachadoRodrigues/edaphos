#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/al_policy_benchmark.R
#
# Does the active-learning machinery beat picking at random?
#
# Pillar 5 ships four acquisition strategies plus a BatchBALD implementation,
# and until now the only comparison in the package was three variants of the
# same heuristic against each other -- uncertainty, diverse, hybrid -- with no
# random arm and no design arm. BatchBALD appeared in a demonstration chunk
# that printed the selected rows and evaluated nothing.
#
# A strategy that cannot beat random selection is not worth its complexity,
# and the only way to know is to run the loop with a random arm in it. The
# comparison is the point; that some arms may lose is not a reason to omit
# them.
#
# PROTOCOL. Real WoSIS Cerrado profiles. A held-out test set is fixed once and
# never touched by any policy. Every arm starts from the SAME seed design so
# the curves differ in acquisition and nothing else, then acquires in rounds
# of `BATCH`, refitting a quantile regression forest each round and scoring on
# the test set. Repeated over `N_REP` seeds because a single AL run is noisy.
#
# Arms:
#   random      -- uniform draw from the pool. The bar every other arm must clear.
#   clhs        -- conditioned Latin hypercube over the covariate space, which
#                  is a design, not a model-driven policy; it sees no labels.
#   uncertainty -- widest predictive interval.
#   hybrid      -- uncertainty traded against covariate diversity.
#   batchbald   -- the batch-aware mutual-information criterion.
#
# Output: inst/extdata/al_policy_benchmark.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))
set.seed(4L)

COVS  <- c("map", "mat", "slope", "elev", "clay", "sand", "bd")
SEED_N <- 40L      # initial design, identical across arms within a repeat
BATCH  <- 20L      # acquired per round
ROUNDS <- 6L
N_REP  <- 5L
N_TEST <- 300L

P <- readRDS("inst/extdata/causal_cerrado_real.rds")$profiles |>
  filter(!is.na(soc_topsoil_gkg), !is.na(lon), !is.na(lat)) |>
  mutate(soc = log1p(soc_topsoil_gkg), map = wc_bio_12, mat = wc_bio_01 / 10,
         clay = soilgrids_clay, sand = soilgrids_sand, bd = soilgrids_bdod)
P <- P[stats::complete.cases(P[, c("soc", COVS, "lon", "lat")]), ]
P <- P[, c("lon", "lat", "soc", COVS)]
message(sprintf("%d profiles; seed %d, batch %d, %d rounds, %d repeats",
                nrow(P), SEED_N, BATCH, ROUNDS, N_REP))

score_on <- function(train, test) {
  fit <- ranger::ranger(
    stats::as.formula(paste("soc ~", paste(COVS, collapse = " + "))),
    data = train, num.trees = 500L, quantreg = TRUE, seed = 1L)
  p <- stats::predict(fit, data = test)$predictions
  c(rmse = sqrt(mean((p - test$soc)^2)),
    nse  = edaphos_nse(test$soc, p, null_prediction = mean(train$soc)))
}

# Every fallback to random is COUNTED. A policy that silently degrades to
# random selection when it errors would score like random and be reported as
# itself, which is the one way this benchmark could lie.
FELL_BACK <- new.env(parent = emptyenv())
FELL_BACK$n <- 0L
FELL_BACK$why <- character(0)

acquire <- function(arm, model, pool, n, rep_seed, round) {
  if (arm == "random") {
    set.seed(rep_seed * 100L + round)
    return(sample.int(nrow(pool), n))
  }
  if (arm == "clhs") {
    return(al_initial_design(pool, COVS, n = n, seed = rep_seed * 100L + round))
  }
  q <- tryCatch(
    if (arm == "batchbald") al_query_batchbald(model, pool, n = n)
    else al_query(model, pool, n = n, strategy = arm),
    error = function(e) {
      FELL_BACK$n <- FELL_BACK$n + 1L
      FELL_BACK$why <- c(FELL_BACK$why,
                         sprintf("%s r%d: %s", arm, round, conditionMessage(e)))
      NULL
    })
  if (is.null(q)) return(sample.int(nrow(pool), n))
  if (is.list(q)) q$index else q
}

ARMS <- c("random", "clhs", "uncertainty", "hybrid", "batchbald")
rows <- list()

for (rep in seq_len(N_REP)) {
  message(sprintf("  repeat %d/%d ...", rep, N_REP))
  set.seed(1000L + rep)
  test_ix <- sample.int(nrow(P), N_TEST)
  test <- P[test_ix, ]; rest <- P[-test_ix, ]
  # One seed design per repeat, shared by every arm.
  seed_ix <- al_initial_design(rest, COVS, n = SEED_N, seed = rep)

  for (arm in ARMS) {
    lab <- rest[seed_ix, ]; pool <- rest[-seed_ix, ]
    s <- score_on(lab, test)
    rows[[length(rows) + 1L]] <- data.frame(
      rep = rep, arm = arm, round = 0L, n_labelled = nrow(lab),
      rmse = s[["rmse"]], nse = s[["nse"]], stringsAsFactors = FALSE)

    for (r in seq_len(ROUNDS)) {
      if (nrow(pool) < BATCH) break
      m <- al_fit(lab, "soc", COVS, coords = c("lon", "lat"))
      idx <- acquire(arm, m, pool, BATCH, rep, r)
      idx <- unique(as.integer(idx))
      idx <- idx[idx >= 1L & idx <= nrow(pool)]
      if (length(idx) < BATCH) {
        extra <- setdiff(seq_len(nrow(pool)), idx)
        idx <- c(idx, sample(extra, BATCH - length(idx)))
      }
      lab  <- rbind(lab, pool[idx, ])
      pool <- pool[-idx, ]
      s <- score_on(lab, test)
      rows[[length(rows) + 1L]] <- data.frame(
        rep = rep, arm = arm, round = r, n_labelled = nrow(lab),
        rmse = s[["rmse"]], nse = s[["nse"]], stringsAsFactors = FALSE)
    }
  }
}

R <- do.call(rbind, rows)

agg <- R |>
  group_by(arm, round, n_labelled) |>
  summarise(rmse = mean(rmse), rmse_sd = stats::sd(rmse), nse = mean(nse),
            .groups = "drop") |>
  as.data.frame()

cat("\n=== mean RMSE by round (log1p g/kg), averaged over",
    N_REP, "repeats ===\n")
wide <- stats::reshape(agg[, c("arm", "round", "rmse")],
                       idvar = "arm", timevar = "round", direction = "wide")
names(wide) <- sub("^rmse\\.", "round ", names(wide))
print(wide, row.names = FALSE, digits = 4)

# The comparison that matters: does any policy beat random at the last round?
final <- R[R$round == ROUNDS, ]
rnd <- final$rmse[final$arm == "random"]
cat(sprintf("\n=== final round (n = %d labelled), against the random arm ===\n",
            max(agg$n_labelled)))
for (a in setdiff(ARMS, "random")) {
  x <- final$rmse[final$arm == a]
  if (length(x) != length(rnd)) next
  w <- suppressWarnings(stats::wilcox.test(x, rnd, paired = TRUE))
  cat(sprintf("  %-12s mean RMSE %.4f vs %.4f random  (diff %+.4f, paired p = %.3f, wins %d/%d)\n",
              a, mean(x), mean(rnd), mean(x) - mean(rnd), w$p.value,
              sum(x < rnd), length(x)))
}

beat <- vapply(setdiff(ARMS, "random"), function(a) {
  x <- final$rmse[final$arm == a]
  length(x) == length(rnd) && mean(x) < mean(rnd)
}, TRUE)
cat(sprintf("\npolicies beating random on the mean at the final round: %s\n",
            if (any(beat)) paste(names(beat)[beat], collapse = ", ") else "none"))

if (FELL_BACK$n > 0L) {
  cat(sprintf("\nWARNING: %d acquisitions fell back to random selection:\n",
              FELL_BACK$n))
  cat(paste0("  ", unique(FELL_BACK$why), collapse = "\n"), "\n")
  cat("Those rounds are indistinguishable from the random arm and the\n")
  cat("affected policy's curve should be read with that in mind.\n")
} else {
  cat("\nNo acquisition fell back to random selection.\n")
}

saveRDS(list(
             # Binds this bundle to the script that made it: see R/provenance.R.
             provenance = edaphos_provenance(),
             runs = R, aggregate = agg, arms = ARMS, n_rep = N_REP,
             n_fallback = FELL_BACK$n, fallback_reasons = unique(FELL_BACK$why),
             seed_n = SEED_N, batch = BATCH, rounds = ROUNDS,
             n_test = N_TEST, covariates = COVS,
             built_by = "data-raw/al_policy_benchmark.R"),
        "inst/extdata/al_policy_benchmark.rds")
message("\nwrote inst/extdata/al_policy_benchmark.rds")
