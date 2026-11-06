## Every torch entry point goes through .require_torch(). The guards it
## replaced checked only requireNamespace("torch"), which is TRUE as soon as
## the R package is installed -- with or without libtorch -- so a machine
## without libtorch got past them and failed later with "Lantern is not
## loaded". This simulates exactly that machine: package present, libtorch
## absent.

test_that("torch entry points refuse cleanly when libtorch is missing", {
  skip_if_not_installed("torch")
  local_mocked_bindings(.torch_usable = function() FALSE)
  msg <- "needs the `torch` package with a working libtorch"
  expect_error(piml_neural_ode_fit(c(5, 15, 30), c(20, 12, 8)), msg)
  expect_error(temporal_convlstm_fit(array(0, c(1, 2, 1, 4, 4)),
                                     array(0, c(1, 4, 4))), msg)
  expect_error(foundation_simclr_pretrain(array(0, c(4, 1, 8, 8))), msg)
  expect_error(edaphos:::.moco_require_torch(), msg)
  expect_error(edaphos:::.ft_require_torch(), msg)
})

test_that("the guard passes when torch works", {
  skip_if_no_torch()
  expect_true(edaphos:::.require_torch("x"))
})
