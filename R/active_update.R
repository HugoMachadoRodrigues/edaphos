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
#'
#' @examples
#' covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' set.seed(42)
#' i_lab <- sample(nrow(br_cerrado), 30)
#' lab   <- br_cerrado[i_lab, ]
#' pool  <- br_cerrado[-i_lab, ][seq(1, 1995, by = 5), ]
#' set.seed(1)
#' m <- al_fit(lab, target = "soc", covariates = covs,
#'             coords = c("x", "y"), seed = 1)
#'
#' # One turn of the loop by hand: query 8 cells, send them to the lab
#' # (br_cerrado already carries the truth), append them.
#' idx <- al_query(m, pool, n = 8, strategy = "hybrid")
#' new <- pool[idx, ]
#'
#' # `...` reaches ranger::ranger() through al_fit(). Without `seed` the
#' # refit grows a different forest on every call and the OOB RMSE moves.
#' identical(al_update(m, new)$history[[2]]$rmse_oob,
#'           al_update(m, new)$history[[2]]$rmse_oob)             # FALSE
#' set.seed(2); m2 <- al_update(m, new, seed = 1)
#' set.seed(2); m3 <- al_update(m, new, seed = 1)
#' identical(m2$history[[2]]$rmse_oob, m3$history[[2]]$rmse_oob)  # TRUE
#'
#' # The OOB RMSE went UP, 4.659 -> 4.677, on 8 extra samples. That is
#' # the expected first move, not a failure: an uncertainty batch is by
#' # construction the part of the landscape the forest handles worst, so
#' # it enters the OOB average as 8 hard rows. Both are still well below
#' # predicting the labeled mean everywhere. Judge the loop on a
#' # held-out set, never on this column.
#' round(c(before    = m$history[[1]]$rmse_oob,
#'         after     = m2$history[[2]]$rmse_oob,
#'         mean_only = sqrt(mean((lab$soc - mean(lab$soc))^2))), 3)
#'
#' # `mean_uncertainty` is recorded under the PRE-update model: it is
#' # the width al_query() acted on, not the width the refit now reports
#' # at those eight cells -- they are labeled, so the forest has
#' # collapsed them from 18.54 to 11.43 g/kg.
#' wid <- function(mod) {
#'   qq <- stats::predict(mod$model, data = new[, covs],
#'                        type = "quantiles",
#'                        quantiles = c(0.1, 0.9))$predictions
#'   mean(qq[, 2] - qq[, 1])
#' }
#' round(c(recorded = m2$history[[2]]$mean_uncertainty,
#'         pre_update = wid(m), post_update = wid(m2)), 2)
#'
#' # history[[1]] stays frozen at iteration 0; read the LAST entry for
#' # the current state. `queried` is empty because al_update() is handed
#' # rows, not pool positions -- only al_loop() can record which.
#' str(m2$history[[2]])
#' c(history_1 = m2$history[[1]]$n_labeled, rows_now = nrow(m2$labeled))
#'
#' # $labeled is rebuilt as target + covariates + coords, in that order.
#' # Anything else carried on `new_samples` -- a lab id, a sampling date
#' # -- is dropped, and the column order is not the one you passed in.
#' new$lab_id <- sprintf("BR-%02d", seq_len(nrow(new)))
#' set.seed(2); m4 <- al_update(m, new, seed = 1)
#' "lab_id" %in% names(m4$labeled)                                # FALSE
#' rbind(before = names(m$labeled), after = names(m4$labeled))
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
