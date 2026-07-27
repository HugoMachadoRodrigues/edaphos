# Smallest `num.trees` that makes out-of-bag quantile regression reliable.
#
# `ranger` requires every observation to be out-of-bag in at least 10 trees
# (it errors with "Too few trees for out-of-bag quantile regression" when
# `min(rowSums(inbag.counts == 0)) < 10`).  Under bootstrap sampling of n
# from n with replacement an observation is out-of-bag in a given tree with
# probability `(1 - 1/n)^n`, so the per-observation out-of-bag count is
# Binomial(num.trees, p).  Return the smallest number of trees for which the
# chance that ANY of the n observations falls short is at most `tol`.
#
# The threshold is computed rather than hard-coded because it grows with n:
# 88 trees at n = 30, 103 at n = 10 000.
.al_min_trees_for_quantreg <- function(n, tol = 1e-6, cap = 5000L) {
  if (!is.finite(n) || n < 2L) return(10L)
  p <- (1 - 1 / n)^n
  n_trees <- 10L
  while (n_trees < cap && n * stats::pbinom(9L, n_trees, p) > tol)
    n_trees <- n_trees + 1L
  n_trees
}

.assert_num_trees <- function(num.trees, n, call = sys.call(-1L)) {
  .assert_type(is.numeric(num.trees) && length(num.trees) == 1L &&
                 !is.na(num.trees) && num.trees >= 1,
               "num.trees", "a single positive integer",
               sprintf("%s of length %d", class(num.trees)[1L],
                       length(num.trees)),
               call = call)
  need <- .al_min_trees_for_quantreg(n)
  if (num.trees < need)
    .stopf(paste("num.trees = %d is too small for out-of-bag quantile",
                 "regression on %d labeled rows: ranger needs every",
                 "observation to be out-of-bag in at least 10 trees, which",
                 "requires at least %d trees here."),
           as.integer(num.trees), as.integer(n), as.integer(need),
           hint = sprintf("Use num.trees >= %d (the al_fit() default is 500).",
                          need),
           call = call)
  invisible(TRUE)
}

.fit_core <- function(labeled, target, covariates, num.trees, ...) {
  form <- stats::reformulate(covariates, response = target)
  fit <- ranger::ranger(
    formula    = form,
    data       = labeled,
    num.trees  = num.trees,
    quantreg   = TRUE,
    keep.inbag = TRUE,
    ...
  )
  rmse_oob <- .rmse(labeled[[target]], fit$predictions)
  list(fit = fit, rmse_oob = rmse_oob)
}

#' Fit a Quantile Regression Forest for Active Learning
#'
#' Fits a Quantile Regression Forest (Meinshausen 2006) on the currently
#' labeled soil dataset, using `ranger::ranger(..., quantreg = TRUE)`. The
#' resulting object carries the data, model, and an initial history entry
#' and is the value on which [al_query()], [al_update()] and
#' [al_loop()] operate.
#'
#' @param labeled Data frame with observed target + covariates
#'   (+ optional coordinates).
#' @param target Character, name of the target column.
#' @param covariates Character vector of covariate column names.
#' @param coords Optional length-2 character vector naming the x/y
#'   coordinate columns. Required by the `"cost"` query strategy.
#' @param num.trees Integer, number of trees (default 500). Because the
#'   forest is fit with `quantreg = TRUE`, `ranger` requires every
#'   observation to be out-of-bag in at least 10 trees; `al_fit()`
#'   rejects a value too small to make that reliable for
#'   `nrow(labeled)` rows (about 88 trees for 30 rows, rising slowly
#'   with n) rather than letting `ranger` fail on some random seeds.
#' @param ... Additional arguments forwarded to `ranger::ranger()`. Note
#'   `seed`: `ranger` draws its own random seed when none is given, so
#'   without it every call grows a different forest and reports a
#'   different out-of-bag RMSE.
#'
#' @return A `edaphos_al_model` object.
#'
#' @references
#' Meinshausen N (2006). Quantile Regression Forests. *Journal of Machine
#' Learning Research* 7, 983-999.
#'
#' @examples
#' \donttest{
#'   if (requireNamespace("sp", quietly = TRUE)) {
#'     data(meuse, package = "sp")
#'     d <- stats::na.omit(meuse[1:30, ])   # 29 rows survive na.omit()
#'
#'     # `seed` is forwarded to ranger::ranger(). Without it the 500-tree
#'     # forest -- and the "last RMSE" printed below -- differs on every
#'     # run; with it, repeated calls print the same number.
#'     m <- al_fit(
#'       labeled    = d,
#'       target     = "lead",
#'       covariates = c("dist", "elev"),
#'       coords     = c("x", "y"),
#'       seed       = 42
#'     )
#'     print(m)
#'
#'     # That RMSE is not evidence of a useful model: it is an out-of-bag
#'     # estimate from 29 points and 2 covariates. Compare it with the RMSE
#'     # of simply predicting the mean of the 29 labeled values.
#'     print(c(oob       = m$history[[1]]$rmse_oob,
#'             mean_only = sqrt(mean((d$lead - mean(d$lead))^2))))
#'     # A model worth acting on needs hundreds of labeled sites and
#'     # spatially blocked validation -- run al_loop() to add points.
#'   }
#' }
#' @export
al_fit <- function(labeled, target, covariates, coords = NULL,
                   num.trees = 500L, ...) {
  .assert_covariates(labeled, c(target, covariates))
  .assert_coords(labeled, coords)
  .assert_num_trees(num.trees, nrow(labeled))
  core <- .fit_core(labeled, target, covariates, num.trees, ...)
  new_active_soil_model(
    labeled    = labeled,
    model      = core$fit,
    config     = list(num.trees = num.trees),
    history    = list(list(
      iter             = 0L,
      n_labeled        = nrow(labeled),
      queried          = integer(0),
      rmse_oob         = core$rmse_oob,
      mean_uncertainty = NA_real_
    )),
    target     = target,
    covariates = covariates,
    coords     = coords
  )
}
