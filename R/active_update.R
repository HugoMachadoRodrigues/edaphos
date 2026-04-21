#' Append newly labeled samples and refit the model
#'
#' Manual one-shot companion to [al_loop()]: takes a model, some freshly
#' labeled samples (for instance returned from the lab), refits the QRF,
#' and appends a history entry. Use this when you are driving the loop
#' yourself instead of letting [al_loop()] orchestrate it.
#'
#' @param model A `edaphos_al_model`.
#' @param new_samples Data frame with the same columns as
#'   `model$labeled` (i.e. target, covariates, and optional coords).
#' @param ... Extra arguments forwarded to [al_fit()].
#' @return An updated `edaphos_al_model`.
#' @export
al_update <- function(model, new_samples, ...) {
  if (!inherits(model, "edaphos_al_model")) {
    stop("`model` must be a edaphos_al_model.", call. = FALSE)
  }
  cols <- c(model$target, model$covariates, model$coords)
  missing <- setdiff(cols, names(new_samples))
  if (length(missing) > 0L) {
    stop("`new_samples` is missing columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  # Uncertainty at the new samples under the pre-update model.
  qp <- stats::predict(
    model$model,
    data      = new_samples[, model$covariates, drop = FALSE],
    type      = "quantiles",
    quantiles = c(0.1, 0.9)
  )$predictions
  mean_unc <- mean(qp[, 2L] - qp[, 1L], na.rm = TRUE)

  labeled2 <- rbind(model$labeled[cols], new_samples[cols])
  refit <- al_fit(
    labeled    = labeled2,
    target     = model$target,
    covariates = model$covariates,
    coords     = model$coords,
    num.trees  = model$config$num.trees %||% 500L,
    ...
  )
  next_iter <- length(model$history)
  refit$history <- c(model$history, list(list(
    iter             = next_iter,
    n_labeled        = nrow(labeled2),
    queried          = integer(0),
    rmse_oob         = refit$history[[1L]]$rmse_oob,
    mean_uncertainty = mean_unc
  )))
  refit
}
