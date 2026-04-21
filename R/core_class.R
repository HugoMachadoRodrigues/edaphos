# S3 class holding the state of an Active-Learning soil model.

new_active_soil_model <- function(labeled, model, config, history,
                                  target, covariates, coords) {
  structure(
    list(
      labeled    = labeled,
      model      = model,
      config     = config,
      history    = history,
      target     = target,
      covariates = covariates,
      coords     = coords
    ),
    class = "edaphos_al_model"
  )
}

#' @export
print.edaphos_al_model <- function(x, ...) {
  cat("<edaphos_al_model>\n")
  cat("  target     :", x$target, "\n")
  cat("  covariates :", paste(x$covariates, collapse = ", "), "\n")
  cat("  coords     :", if (is.null(x$coords)) "<none>"
                         else paste(x$coords, collapse = ", "), "\n")
  cat("  n labeled  :", nrow(x$labeled), "\n")
  cat("  iterations :", max(0L, length(x$history) - 1L), "\n")
  if (length(x$history) > 0L) {
    last <- x$history[[length(x$history)]]
    if (is.finite(last$rmse_oob)) {
      cat("  last RMSE  :", format(last$rmse_oob, digits = 4), "\n")
    }
  }
  invisible(x)
}

#' @export
summary.edaphos_al_model <- function(object, ...) {
  h <- object$history
  if (length(h) == 0L) {
    cat("No iterations recorded.\n")
    return(invisible(NULL))
  }
  df <- do.call(rbind, lapply(h, function(r) {
    data.frame(
      iter             = r$iter,
      n_labeled        = r$n_labeled,
      rmse_oob         = r$rmse_oob,
      mean_uncertainty = r$mean_uncertainty
    )
  }))
  print(df, row.names = FALSE)
  invisible(df)
}

#' Extract the learning curve from a fitted Active-Learning model
#'
#' Returns the iteration-by-iteration diagnostics (sample size, OOB RMSE,
#' mean queried-point uncertainty) as a tidy data frame, ready for
#' plotting with ggplot2 or base graphics.
#'
#' @param model A `edaphos_al_model` returned by [al_fit()] or [al_loop()].
#' @return A data frame with columns `iter`, `n_labeled`, `rmse_oob`,
#'   `mean_uncertainty`.
#' @export
al_history <- function(model) {
  stopifnot(inherits(model, "edaphos_al_model"))
  do.call(rbind, lapply(model$history, function(r) {
    data.frame(
      iter             = r$iter,
      n_labeled        = r$n_labeled,
      rmse_oob         = r$rmse_oob,
      mean_uncertainty = r$mean_uncertainty
    )
  }))
}
