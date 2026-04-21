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
#' @param num.trees Integer, number of trees (default 500).
#' @param ... Additional arguments forwarded to `ranger::ranger()`.
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
#'     m <- al_fit(
#'       labeled    = stats::na.omit(meuse[1:30, ]),
#'       target     = "lead",
#'       covariates = c("dist", "elev"),
#'       coords     = c("x", "y")
#'     )
#'     m
#'   }
#' }
#' @export
al_fit <- function(labeled, target, covariates, coords = NULL,
                   num.trees = 500L, ...) {
  .assert_covariates(labeled, c(target, covariates))
  .assert_coords(labeled, coords)
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
