# `self` is a magic binding inside torch::nn_module() / R6 methods.
# R CMD check does not understand R6-style method scoping, so we declare
# it as a known global to silence the NOTE.
utils::globalVariables("self")
