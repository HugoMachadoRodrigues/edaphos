#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/piml_depth_benchmark.R
#
# Does the pedogenetic mechanism buy anything?
#
# The specialist panel's sharpest criticism of Pillar 2 was not that the model
# is wrong but that it was never tested against the alternatives a pedometrician
# would reach for first. One reviewer ran the test himself on 400 real profiles
# and reported the ODE LOSING to its own nested special case and to copying the
# last observed horizon. This script runs that comparison properly, on all
# 1,105 real multi-horizon WoSIS Cerrado profiles, and reports whatever it says.
#
# Two pre-declared tasks, because they ask different questions and the methods
# do not all answer both.
#
#   A. INTERPOLATION -- hold out one interior horizon, predict it from the rest.
#      Every method applies. This is what an equal-area spline is designed for.
#   B. EXTRAPOLATION -- hold out the DEEPEST horizon, predict it from the ones
#      above. This is what a parametric depth function is FOR, and it is the
#      task one panel reviewer used to report the ODE losing.
#
# The equal-area spline does not extrapolate: mpspline2 returns estimates only
# within the observed depth range, so on task B it has nothing to say below the
# deepest training horizon. That is reported as an abstention rather than
# papered over by clamping it to the last value (which would silently turn it
# into the copy-last baseline).
#
# Competitors
#   1. edaphos ODE, attenuating rate   4 par (y0, y_asym, kappa, mu)
#   2. derived advection-reaction      5 par (y0, A, B, z_r, lambda) -- the
#      mechanistically derivable alternative, piml_profile_fit_mechanistic()
#   3. nested exponential              3 par (mu = 0): the ODE's own special case
#   4. equal-area spline               mpspline2 (Bishop 1999; Malone 2009)
#   5. depth-as-covariate random forest, fitted pooled across profiles
#   6. copy nearest training horizon   0 par
#   7. profile mean                    0 par
#
# The random forest is the incumbent DSM approach and is fitted pooled, so it
# sees other profiles' data -- an advantage the per-profile methods do not have.
# It is included because it is what a referee will ask about, and the advantage
# is stated rather than hidden.
#
# Output: inst/extdata/piml_depth_benchmark.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))

set.seed(11)
D <- readRDS("inst/extdata/piml_wosis_cerrado.rds")
h <- D$horizons

split_profile <- function(s) {
  s <- s[order(s$top), ]
  list(train = s[-nrow(s), , drop = FALSE], test = s[nrow(s), , drop = FALSE])
}

# --- competitor 2: the ODE's own nested mu = 0 special case ----------------
# y(z) = A + (y0 - A) exp(-lambda z), fitted on the same positive coordinates
# as the full model so the comparison is like-for-like.
fit_nested <- function(z, y) {
  obj <- function(th) {
    p <- exp(th)
    sum((y - (p[1] + (p[2] - p[1]) * exp(-p[3] * z)))^2)
  }
  best <- NULL
  for (l0 in log(c(0.005, 0.02, 0.08))) {
    st <- c(log(max(min(y), 1e-3)), log(max(y)), l0)
    o <- tryCatch(stats::optim(st, obj, control = list(maxit = 2000, reltol = 1e-10)),
                  error = function(e) NULL)
    if (!is.null(o) && (is.null(best) || o$value < best$value)) best <- o
  }
  best
}
pred_nested <- function(o, z) {
  p <- exp(o$par); p[1] + (p[2] - p[1]) * exp(-p[3] * z)
}

# --- competitor 5: equal-area / mass-preserving spline ---------------------
pred_spline <- function(tr, z_new) {
  if (!requireNamespace("mpspline2", quietly = TRUE)) return(NA_real_)
  # mpspline refuses profiles whose horizons overlap, and it warns rather than
  # erroring on some of them, so guard both. Profiles it will not take are
  # counted and reported below rather than silently dropped -- a baseline that
  # quietly skips the hard cases is not a baseline.
  if (any(diff(tr$top) <= 0) || any(tr$bottom[-nrow(tr)] > tr$top[-1])) return(NA_real_)
  df <- data.frame(SID = "p", UD = tr$top, LD = tr$bottom, VAL = tr$soc_g_kg)
  s <- tryCatch(
    suppressWarnings(
      mpspline2::mpspline(df, var_name = "VAL", d = c(0, ceiling(max(z_new)) + 1L),
                          vlow = 0, vhigh = max(tr$soc_g_kg) * 5)),
    error = function(e) NULL)
  if (is.null(s) || !length(s) || is.null(s[[1]])) return(NA_real_)
  v <- s[[1]]$est_1cm
  if (is.null(v) || !length(v)) return(NA_real_)
  i <- max(1L, min(length(v), round(z_new)))
  out <- suppressWarnings(as.numeric(v[i]))
  if (!is.finite(out)) NA_real_ else out
}

profs <- split(h, h$profile_id)
profs <- lapply(profs, function(s) s[order(s$top), ])
message(sprintf("perfis: %d", length(profs)))

# --- one evaluation of every competitor on one (train, test) split ----------
one_split <- function(tr, te, task) {
  if (nrow(tr) < 3) return(NULL)
  zt <- te$depth_mid

  ode <- tryCatch(piml_profile_fit(tr$depth_mid, tr$soc_g_kg,
                                   top = tr$top, bottom = tr$bottom),
                  error = function(e) NULL)
  p_ode <- if (is.null(ode)) NA_real_ else
    tryCatch(as.numeric(.piml_layer_mean(te$top, te$bottom, ode$params)),
             error = function(e) NA_real_)

  mech <- tryCatch(piml_profile_fit_mechanistic(tr$depth_mid, tr$soc_g_kg,
                                                top = tr$top, bottom = tr$bottom),
                   error = function(e) NULL)
  p_mech <- if (is.null(mech)) NA_real_ else
    tryCatch(as.numeric(.pmech_layer_mean(te$top, te$bottom, mech$params)),
             error = function(e) NA_real_)

  nb <- fit_nested(tr$depth_mid, tr$soc_g_kg)
  p_nest <- if (is.null(nb)) NA_real_ else pred_nested(nb, zt)

  # "copy nearest": for extrapolation this is the deepest training horizon;
  # for interpolation it is the training horizon closest in depth.
  j <- which.min(abs(tr$depth_mid - zt))

  data.frame(
    task       = task,
    profile_id = te$profile_id,
    n_train    = nrow(tr),
    z_test     = zt,
    obs        = te$soc_g_kg,
    ode        = p_ode,
    mech       = p_mech,
    nested     = p_nest,
    copy_near  = tr$soc_g_kg[j],
    prof_mean  = mean(tr$soc_g_kg),
    spline     = pred_spline(tr, zt),
    progress   = if (is.null(ode)) NA_real_ else ode$progress,
    stringsAsFactors = FALSE
  )
}

message("task A: interpolacao (deixa um horizonte interior de fora)")
rows_A <- do.call(rbind, lapply(seq_along(profs), function(k) {
  if (k %% 300 == 0) message("  ", k, "/", length(profs))
  s <- profs[[k]]
  if (nrow(s) < 4) return(NULL)
  i <- ceiling(nrow(s) / 2)          # a middle horizon, deterministic
  one_split(s[-i, , drop = FALSE], s[i, , drop = FALSE], "interpolation")
}))

message("task B: extrapolacao (deixa o horizonte mais profundo de fora)")
rows_B <- do.call(rbind, lapply(seq_along(profs), function(k) {
  if (k %% 300 == 0) message("  ", k, "/", length(profs))
  s <- profs[[k]]
  one_split(s[-nrow(s), , drop = FALSE], s[nrow(s), , drop = FALSE], "extrapolation")
}))

rows <- rbind(rows_A, rows_B)
mono <- vapply(profs, function(s) all(diff(s$soc_g_kg) <= 0), logical(1))
rows$monotone <- unname(mono[rows$profile_id])

# --- pooled depth-as-covariate random forest, per task ---------------------
# Fitted with the held-out horizons removed, so it never sees a test horizon.
# It does see OTHER profiles, which the per-profile methods do not.
message("random forest (profundidade como covariavel, pooled)")
rf_for <- function(task) {
  tr <- do.call(rbind, lapply(profs, function(s) {
    if (task == "extrapolation") s[-nrow(s), , drop = FALSE]
    else { if (nrow(s) < 4) return(NULL); s[-ceiling(nrow(s) / 2), , drop = FALSE] }
  }))
  te <- do.call(rbind, lapply(profs, function(s) {
    if (task == "extrapolation") s[nrow(s), , drop = FALSE]
    else { if (nrow(s) < 4) return(NULL); s[ceiling(nrow(s) / 2), , drop = FALSE] }
  }))
  m <- ranger::ranger(soc_g_kg ~ depth_mid + top + bottom + x + y,
                      data = tr, num.trees = 500L, seed = 11L)
  stats::setNames(stats::predict(m, data = te)$predictions, te$profile_id)
}
for (tk in c("interpolation", "extrapolation")) {
  pr <- rf_for(tk)
  i <- rows$task == tk
  rows$rf[i] <- unname(pr[rows$profile_id[i]])
}

METHODS <- c(ode = "edaphos ODE, attenuating rate (4 par)",
             mech = "derived advection-reaction (5 par)",
             nested = "nested exponential (3 par)",
             spline = "equal-area spline",
             rf = "RF, depth as covariate (pooled)",
             copy_near = "copy nearest training horizon",
             prof_mean = "profile mean")

score <- function(p, o) c(
  RMSE = sqrt(mean((p - o)^2)),
  MAE  = mean(abs(p - o)),
  ME   = mean(p - o),
  CCC  = 2 * stats::cov(p, o) / (stats::var(p) + stats::var(o) + (mean(p) - mean(o))^2)
)

report <- function(rr, label, methods) {
  # Abstentions are reported, never silently dropped.
  cat("\n=== ", label, " (n = ", nrow(rr), " perfis) ===\n", sep = "")
  for (m in methods) {
    na <- sum(!is.finite(rr[[m]]))
    if (na) cat(sprintf("  [abstencao] %-38s sem previsao em %d de %d\n",
                        METHODS[m], na, nrow(rr)))
  }
  ok <- stats::complete.cases(rr[, methods]) &
        apply(abs(rr[, methods, drop = FALSE]) < 1e4, 1, all)
  cat(sprintf("  pontuados em todos os metodos: %d (descartados %d)\n",
              sum(ok), sum(!ok)))
  r <- rr[ok, ]
  tab <- as.data.frame(t(vapply(methods, function(m) score(r[[m]], r$obs), numeric(4))))
  tab$method <- unname(METHODS[rownames(tab)])
  tab <- tab[order(tab$RMSE), c("method", "RMSE", "MAE", "ME", "CCC")]
  rownames(tab) <- NULL
  print(tab, row.names = FALSE, digits = 4)
  cmp <- do.call(rbind, lapply(setdiff(methods, "ode"), function(m) {
    eo <- abs(r$ode - r$obs); ea <- abs(r[[m]] - r$obs)
    w <- suppressWarnings(stats::wilcox.test(eo, ea, paired = TRUE))
    data.frame(vs = unname(METHODS[m]), ode_wins = sum(eo < ea),
               alt_wins = sum(ea < eo), p = w$p.value, stringsAsFactors = FALSE)
  }))
  cat("  -- ODE contra cada alternativa (|erro| pareado) --\n")
  print(cmp, row.names = FALSE, digits = 3)
  list(table = tab, paired = cmp, n = nrow(r))
}

ALL <- names(METHODS)
NOSPLINE <- setdiff(ALL, "spline")
rA <- rows[rows$task == "interpolation", ]
rB <- rows[rows$task == "extrapolation", ]

res_A     <- report(rA, "A. INTERPOLACAO -- horizonte interior retido", ALL)
res_B     <- report(rB, "B. EXTRAPOLACAO -- horizonte mais profundo retido (spline abstem)", NOSPLINE)
res_B_mon <- report(rB[rB$monotone, ],
                    "B'. EXTRAPOLACAO, apenas perfis monotonos -- o dominio declarado do modelo",
                    NOSPLINE)

saveRDS(list(rows = rows, interpolation = res_A, extrapolation = res_B,
             extrapolation_monotone = res_B_mon, methods = METHODS,
             n_profiles = length(profs),
             n_monotone = sum(mono),
             source = "inst/extdata/piml_wosis_cerrado.rds",
             built_by = "data-raw/piml_depth_benchmark.R"),
        "inst/extdata/piml_depth_benchmark.rds")
message("\nwrote inst/extdata/piml_depth_benchmark.rds")
