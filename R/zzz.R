# `self` is a magic binding inside torch::nn_module() / R6 methods.
# `..` is torch's multi-axis ellipsis used in tensor slicing.
# R CMD check does not understand R6-style method scoping nor torch's
# ellipsis marker, so we declare them as known globals to silence NOTEs.
utils::globalVariables(c("self", ".."))
