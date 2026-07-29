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
#' @examples
#' # 400 Cerrado cells: 120 already sampled, 280 candidates the loop
#' # may request. `al_loop()` never forwards a seed to ranger, so
#' # set.seed() outside it is what makes this table reproducible.
#' set.seed(7)
#' cells <- br_cerrado[sample(nrow(br_cerrado), 400L), ]
#' covs  <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' m <- al_loop(labeled = cells[1:120, ], candidates = cells[121:400, ],
#'              target = "soc", covariates = covs,
#'              coords = c("x", "y"), budget = 30L, batch = 10L,
#'              strategy = "hybrid", verbose = FALSE)
#' h <- al_history(m)
#' h
#'
#' # Row `iter = 0` is the initial fit, before any query, so its
#' # `mean_uncertainty` is NA by construction and any column summary
#' # needs na.rm = TRUE.
#' c(raw = mean(h$mean_uncertainty),
#'   na_rm = mean(h$mean_uncertainty, na.rm = TRUE))
#'
#' # `rmse_oob` is out-of-bag on the labeled set of its own row, so
#' # every row changes both the training data and the evaluation data.
#' # It is a progress log, not a held-out learning curve, and the
#' # 0.25 g/kg drop only means something next to a baseline: predicting
#' # the mean of the same 150 points scores 6.94 g/kg.
#' round(c(oob_final = h$rmse_oob[nrow(h)],
#'         mean_only = sqrt(mean((m$labeled$soc -
#'                                  mean(m$labeled$soc))^2))), 3)
#'
#' # Nor is the curve monotone. Same seed, same 120 starting points,
#' # diversity-only queries: rmse_oob rises on the last iteration
#' # (+0.0261) after falling twice.
#' set.seed(7)
#' cells2 <- br_cerrado[sample(nrow(br_cerrado), 400L), ]
#' h2 <- al_history(al_loop(labeled = cells2[1:120, ],
#'                          candidates = cells2[121:400, ],
#'                          target = "soc", covariates = covs,
#'                          coords = c("x", "y"), budget = 30L,
#'                          batch = 10L, strategy = "diverse",
#'                          verbose = FALSE))
#' round(diff(h2$rmse_oob), 4)
#'
#' # Both runs share the iter-0 forest -- identical rmse_oob there --
#' # so the two `mean_uncertainty` columns are directly comparable:
#' # the hybrid batch averages 24.64 g/kg of 80% interval width where
#' # the diversity-only batch averages 12.66. The column describes the
#' # batch the strategy picked, not the uncertainty of the map.
#' identical(h$rmse_oob[1], h2$rmse_oob[1])
#' cbind(iter = h$iter, hybrid = h$mean_uncertainty,
#'       diverse = h2$mean_uncertainty)
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
