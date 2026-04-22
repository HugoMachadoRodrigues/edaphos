# Pillar 4 v1.2.0 tests: pretrained weights distribution.

skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  if (!torch::torch_is_installed()) {
    skip("torch backend not installed")
  }
}

test_that("foundation_weights_list returns a data frame with required columns", {
  reg <- foundation_weights_list()
  expect_s3_class(reg, "data.frame")
  for (col in c("name", "description", "n_channels", "feature_dim",
                 "proj_dim", "patch_size", "url", "sha256", "doi",
                 "license", "edaphos_version")) {
    expect_true(col %in% names(reg),
                 info = paste("missing column:", col))
  }
  expect_gte(nrow(reg), 1L)
})

test_that("foundation_weights_download rejects an unknown name", {
  expect_error(
    foundation_weights_download("definitely-not-a-real-encoder"),
    regexp = "Unknown pretrained encoder"
  )
})

test_that("foundation_weights_load rejects a local path without shape metadata", {
  f <- tempfile(fileext = ".pt")
  on.exit(unlink(f), add = TRUE)
  writeLines("stub", f)
  expect_error(
    foundation_weights_load(f),
    regexp = "requires.*n_channels"
  )
})

test_that("foundation_weights_load roundtrips a locally saved encoder", {
  skip_if_no_torch()
  # Train a tiny MoCo encoder and persist its state dict.
  set.seed(1)
  C <- 4L; P <- 16L; N <- 32L
  patches <- array(rnorm(N * C * P * P), dim = c(N, C, P, P))
  ds <- structure(
    list(stack = NULL, patch_size = P, n_patches = N, n_channels = C,
         means = rep(0, C), sds = rep(1, C),
         valid_cells = seq_len(N),
         sample = function(b) patches[sample(N, b), , , ,
                                         drop = FALSE]),
    class = "edaphos_tile_dataset"
  )
  moco <- foundation_moco_pretrain_tiles(
    ds, feature_dim = 16L, proj_dim = 8L,
    queue_size = 16L, batch_size = 8L, epochs = 3L,
    device = "cpu", seed = 1L
  )
  f <- tempfile(fileext = ".pt")
  on.exit(unlink(f), add = TRUE)
  torch::torch_save(moco$encoder_q$state_dict(), f)

  restored <- foundation_weights_load(
    f,
    n_channels  = C,
    feature_dim = 16L,
    proj_dim    = 8L
  )
  expect_s3_class(restored, "edaphos_foundation_moco")
  expect_equal(restored$n_channels, C)
  expect_equal(restored$feature_dim, 16L)

  # Round-tripped encoder should embed to the same vectors.
  emb_original <- foundation_moco_embed(moco, patches[1:4, , , ,
                                                        drop = FALSE])
  emb_restored <- foundation_moco_embed(restored, patches[1:4, , , ,
                                                            drop = FALSE])
  expect_equal(emb_original, emb_restored, tolerance = 1e-5)
})

test_that("foundation_weights_download surfaces a clear 'no URL yet' error when URL missing", {
  # Every row in the registry at release time may have NA urls (the
  # Zenodo upload happens once per release). Ensure we fail gracefully
  # instead of attempting an empty GET.
  reg <- foundation_weights_list()
  any_missing <- any(is.na(reg$url) | !nzchar(as.character(reg$url)))
  if (!any_missing) skip("registry has no missing-URL entries")
  first_missing <- reg$name[which(
    is.na(reg$url) | !nzchar(as.character(reg$url))
  )[1L]]
  expect_error(
    foundation_weights_download(first_missing),
    regexp = "no published URL yet"
  )
})
