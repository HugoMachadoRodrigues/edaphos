## The Pillar-1 real-data causal claims in the README and the pilar1-causal /
## capstone vignettes must be DERIVABLE from the shipped bundle, not typed by
## hand. This test re-fits the backdoor models from the bundle's own profiles
## and checks the shipped effect table matches -- so a drifted or fabricated
## number cannot pass review. (Guards against a recurrence of finding F862881,
## where the published betas matched nothing in the shipped artefact.)

bpath <- system.file("extdata", "causal_cerrado_real_v2.rds", package = "edaphos")

test_that("the real causal bundle is present and well-formed", {
  skip_if(bpath == "", "causal_cerrado_real_v2.rds not installed")
  b <- readRDS(bpath)
  expect_identical(b$schema_version, 2L)
  expect_equal(b$n_profiles, nrow(b$profiles))
  expect_gt(b$n_profiles, 3000L)                       # real WoSIS Cerrado sample
  expect_true(all(c("lon","lat","soc","mat","map","elev","slope",
                    "clay","sand","bdod","trees") %in% names(b$profiles)))
  expect_true(all(is.finite(b$profiles$soc)) &&
              min(b$profiles$soc) >= 0 && max(b$profiles$soc) < 500)
})

test_that("shipped backdoor betas are reproduced from the shipped profiles", {
  skip_if(bpath == "", "bundle not installed")
  b <- readRDS(bpath)
  d <- b$profiles
  # align to the DAG node names the effects table records
  d$soc_topsoil_gkg <- d$soc; d$wc_bio_01 <- d$mat; d$wc_bio_12 <- d$map
  d$wc_landcover_trees <- d$trees
  d$soilgrids_clay <- d$clay; d$soilgrids_sand <- d$sand; d$soilgrids_bdod <- d$bdod

  for (i in seq_len(nrow(b$effects))) {
    ex   <- b$effects$exposure[i]
    aset <- trimws(strsplit(b$effects$adjustment[i], ",")[[1]])
    fit  <- stats::lm(stats::reformulate(c(ex, aset), "soc_topsoil_gkg"), data = d)
    # point estimate must match the shipped table to 4 dp (deterministic)
    expect_equal(unname(coef(fit)[ex]), b$effects$beta_adj[i], tolerance = 1e-4,
                 info = sprintf("adjusted beta for %s", ex))
    # and its robustness value must match causal_sensitivity_from_lm()
    rv <- causal_sensitivity_from_lm(fit, ex)$rv
    expect_equal(rv, b$effects$RV[i], tolerance = 1e-3,
                 info = sprintf("robustness value for %s", ex))
  }
})

test_that("MAP and clay are the significant, robust associations; tree cover collapses", {
  skip_if(bpath == "", "bundle not installed")
  e <- readRDS(bpath)$effects
  sig <- e$exposure[e$signif]
  expect_setequal(sig, c("wc_bio_12", "soilgrids_clay"))
  tc <- e[e$exposure == "wc_landcover_trees", ]
  expect_gt(tc$beta_naive, 2)          # large naive association ...
  expect_lt(abs(tc$beta_adj), 1)       # ... collapses once climate is adjusted
  expect_true(tc$ci_lo < 0 && tc$ci_hi > 0)   # CI spans zero
})

test_that("the IV negative result holds: strong but invalid instruments", {
  skip_if(bpath == "", "bundle not installed")
  iv <- readRDS(bpath)$iv
  skip_if(is.null(iv), "IV slot absent (torch not available at build time)")
  expect_gt(iv$first_stage_F, 100)     # instruments very relevant
  expect_lt(iv$sargan_p, 1e-6)         # but decisively fail over-identification
})
