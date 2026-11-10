#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data-raw/paper_record_aggregates.R
#
# The aggregates the manuscript states that the 2026-08-28 strip left without
# a shipped source.
#
# The strip kept each bundle's scored tables and removed its records. Some of
# the manuscript's numbers had been computed at render time from those
# records -- a coverage rate over 150 fits, the depth range of 24 held-out
# horizons, a DAG falsification test over 3,077 profiles -- so after the strip
# the manuscript no longer rendered. This script computes exactly those
# numbers, from the pre-strip records in the local cache, and ships them as
# aggregates. Nothing in the output identifies a profile or carries a
# measured value of one.
#
# Each block first checks that the cached records reproduce the aggregate the
# shipped bundle already holds. That check is what makes the new numbers
# trustworthy: they come from the same records as the published ones, not
# from a re-fetch that may have moved.
#
# Input:  data-raw/build/records/*.rds   (Rscript data-raw/restore_records.R)
# Output: inst/extdata/paper_record_aggregates.rds
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all(".", quiet = TRUE))
source("data-raw/records.R")

shipped <- function(n) readRDS(file.path("inst", "extdata", paste0(n, ".rds")))
same <- function(a, b, what, tol = 1e-12) {
  if (!isTRUE(all.equal(a, b, tolerance = tol, check.attributes = FALSE)))
    stop("cached records do not reproduce the shipped ", what, call. = FALSE)
  message("  reproduces shipped ", what)
}

# -- 1. Pillar-2 interval coverage (piml_coverage.R) -------------------------
message("coverage")
cv <- read_records("piml_coverage")$coverage
same(cv$covered[cv$band == "100-200"] |> mean(),
     with(shipped("piml_coverage")$by_depth, picp[band == "100-200"]),
     "piml_coverage$by_depth")
ok <- cv$converged
coverage <- data.frame(
  subset    = c("all fits", "converged fits only"),
  n         = c(nrow(cv), sum(ok)),
  picp      = c(mean(cv$covered), mean(cv$covered[ok])),
  mpiw      = c(mean(cv$width), mean(cv$width[ok])),
  int_score = c(stats::median(cv$int_score), stats::median(cv$int_score[ok])),
  stringsAsFactors = FALSE)

# -- 2. Stock on measured density (piml_stock_validation.R) ------------------
message("stock validation")
sv <- read_records("piml_stock_validation")$stock
SVs <- shipped("piml_stock_validation")
same(mean(abs(sv$stock_ode - sv$stock_obs)),
     SVs$table$MAE[SVs$table$method == "ode"], "piml_stock_validation$table")
stock_validation <- list(
  n            = nrow(sv),
  depth_range  = range(sv$depth),
  stock_obs_range = range(sv$stock_obs))

# -- 3. Bulk-density pedotransfer function (piml_ptf_bulk_density.R) ---------
# The bundle was deleted whole because it carried its calibration set three
# times over. Its cross-validated summary table is a statement about four
# models, not about any horizon, and is what Table 9 prints.
message("pedotransfer function")
pt <- read_records("piml_ptf_bulk_density")
same(pt$aggregate$skill_vs_constant[1],
     shipped("piml_stock_at_scale")$ptf$skill_vs_constant,
     "piml_stock_at_scale$ptf")
ptf_cv <- pt$aggregate
rownames(ptf_cv) <- NULL

# -- 4. The PTF applied off its basin (piml_stock_at_scale.R) ---------------
message("pedotransfer function in application")
pr <- read_records("piml_stock_at_scale")$price
ptf_in_application <- list(
  n                  = nrow(pr),
  rel_rmse           = sqrt(mean((pr$bd_ptf - pr$bd)^2)) / mean(pr$bd),
  bd_range           = range(pr$bd),
  bd_ptf_min         = min(pr$bd_ptf),
  stock_mae_measured = mean(abs(pr$stock_ode - pr$stock_obs)),
  stock_mae_ptf      = mean(abs(pr$stock_ode_ptf - pr$stock_obs_ptf)))

# -- 5. Distance to the nearest training profile (interval_width_...R) ------
message("extrapolation distance")
pp <- read_records("interval_width_vs_extrapolation")$per_profile
same(stats::cor(pp$w_p7, pp$d_km, method = "spearman"),
     with(shipped("interval_width_vs_extrapolation")$summary, width_rho[method == "P7"]),
     "interval_width_vs_extrapolation$summary")
extrapolation_distance <- list(
  n = nrow(pp), min_km = min(pp$d_km), max_km = max(pp$d_km),
  median_km = stats::median(pp$d_km))

# -- 6. Is the pedogenetic DAG compatible with the data? ---------------------
# causal_dag_test() on the causal extract. The manuscript ran this at render
# time on $profiles, which the strip removed; it now runs here.
message("DAG falsification test (thin-plate residualisation, ~1 min)")
dd <- read_records("causal_cerrado_real_v2")$profiles
same(nrow(dd), shipped("causal_cerrado_real_v2")$n_profiles,
     "causal_cerrado_real_v2$n_profiles")
dd$soc_topsoil_gkg <- dd$soc; dd$wc_bio_01 <- dd$mat; dd$wc_bio_12 <- dd$map
dd$wc_landcover_trees <- dd$trees; dd$soilgrids_clay <- dd$clay
dd$soilgrids_sand <- dd$sand; dd$soilgrids_bdod <- dd$bdod
dag <- causal_cerrado_real_dag()
DT <- causal_dag_test(dag, dd, coords = c("lon", "lat"))
dag_test <- list(
  n_nodes            = length(names(dagitty::coordinates(dag)$x)),
  nodes_tested       = DT$nodes_tested,
  nodes_without_data = DT$nodes_without_data,
  n                  = DT$n,
  n_tests            = DT$n_tests,
  n_rejected         = DT$n_rejected,
  n_rejected_spatial = DT$n_rejected_spatial,
  n_rejected_holm    = DT$n_rejected_holm,
  n_rejected_spatial_holm = DT$n_rejected_spatial_holm,
  max_abs_r          = DT$max_abs_r,
  max_abs_r_test     = rownames(DT$pooled)[which.max(abs(DT$pooled$estimate))],
  # independencies whose verdict at 5% differs between the two tests
  n_verdict_changes  = sum((DT$pooled$p.value < 0.05) != (DT$spatial$p.value < 0.05)),
  pooled             = DT$pooled,
  spatial            = DT$spatial)

# -- 7. Are the fitted depth-function parameters mappable? -------------------
# piml_parameter_variograms.rds was deleted on 2026-08-27 (d8c1998) because
# $params carried real profile ids and coordinates. Its $table is a statement
# about four variograms, and is what the "Can the fitted profile be mapped?"
# paragraph and Fig 4 report.
message("parameter variograms")
V <- read_records("piml_parameter_variograms")
stopifnot(nrow(V$table) == 4L)
variograms <- list(
  table       = V$table,
  n_profiles  = V$n_profiles,
  n_fitted    = nrow(V$params),
  n_pairs     = sum(V$raw[[1]]$vg$np),
  first_lag_km = V$raw[[1]]$lag1,
  cutoff_km   = V$cutoff)

out <- list(
  provenance = edaphos_provenance(
    records_manifest = utils::read.csv(file.path(records_dir(), "MANIFEST.csv"),
                                       stringsAsFactors = FALSE)[, c("bundle", "git_blob", "sha256")]),
  coverage = coverage,
  stock_validation = stock_validation,
  ptf_cv = ptf_cv,
  ptf_in_application = ptf_in_application,
  extrapolation_distance = extrapolation_distance,
  dag_test = dag_test,
  variograms = variograms,
  built_by = "data-raw/paper_record_aggregates.R")

saveRDS(out, "inst/extdata/paper_record_aggregates.rds", version = 3, compress = "xz")
message("wrote inst/extdata/paper_record_aggregates.rds")
str(out[setdiff(names(out), c("provenance", "dag_test"))], vec.len = 3)
str(dag_test[setdiff(names(dag_test), c("pooled", "spatial"))])
