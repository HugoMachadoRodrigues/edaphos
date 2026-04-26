# Skip helper for tests that require both the R `torch` package AND
# its libtorch (Lantern) backend.  CI environments routinely install
# the R package but skip the ~1 GB Lantern download, so a plain
# `skip_if_not_installed("torch")` is NOT enough -- those tests fail
# with `Error: Lantern is not loaded` when they actually try to
# allocate a tensor.
.skip_if_no_torch <- function() {
  testthat::skip_if_not_installed("torch")
  if (!isTRUE(torch::torch_is_installed())) {
    testthat::skip("Lantern (libtorch) backend is not installed.")
  }
}
