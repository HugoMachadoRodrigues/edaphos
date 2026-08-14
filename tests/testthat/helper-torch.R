# Skip helper for tests that require both the R `torch` package AND
# its libtorch (Lantern) backend.  CI environments routinely install
# the R package but skip the ~1 GB Lantern download, so a plain
# `skip_if_not_installed("torch")` is NOT enough -- those tests fail
# with `Error: Lantern is not loaded` when they actually try to
# allocate a tensor.
.skip_if_no_torch <- function() {
  testthat::skip_if_not_installed("torch")
  if (!isTRUE(tryCatch(torch::torch_is_installed(), error = function(e) FALSE)))
    testthat::skip("Lantern (libtorch) backend is not installed.")
  # AND IT MUST ACTUALLY ALLOCATE. torch_is_installed() reports on the
  # presence of the runtime, not on whether it works: a partial or
  # architecture-mismatched Lantern answers TRUE and then dies on the first
  # tensor. Thirteen test files had grown their own copy of this helper and
  # the strongest of them probed with a real allocation, which is why the
  # consolidation adopted that version rather than the shortest one.
  if (inherits(tryCatch(torch::torch_tensor(1), error = function(e) e),
               "error"))
    testthat::skip("torch runtime present but cannot allocate a tensor.")
}

# Non-dotted alias. Thirteen files called `skip_if_no_torch()` and each
# defined its own, in three flavours that were not equivalent: some checked
# only torch_is_installed(), some wrapped it in tryCatch, some allocated. The
# copies are gone; this name resolves to the one definition above so those
# call sites keep working and cannot drift apart again.
skip_if_no_torch <- .skip_if_no_torch
