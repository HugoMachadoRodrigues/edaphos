#' Closed-loop Autonomous Active Learning for soil mapping
#'
#' Runs the full Pillar 5 closed loop:
#' \enumerate{
#'   \item fit a Quantile Regression Forest on the current labeled set;
#'   \item query the next batch of candidates via [al_query()];
#'   \item label them through a user-supplied `oracle` (or a simulation
#'         oracle, when the reference values are already in `candidates`);
#'   \item append + refit;
#'   \item repeat until the sampling budget is exhausted or the OOB RMSE
#'         falls below `stop_rmse`.
#' }
#'
#' The `oracle` argument is the extension point that lets the same code
#' drive simulation, lab-pipeline integration, or on-board Edge-AI
#' decision making on a drone/rover (the Pillar-5 endgame).
#'
#' @param labeled Data frame with the initial labeled sample.
#' @param candidates Data frame of unlabeled candidate locations. When
#'   `oracle` is `NULL`, `candidates[[target]]` must already contain the
#'   true values (simulation mode).
#' @param target Character, name of the target column.
#' @param covariates Character vector of covariate column names.
#' @param coords Optional length-2 character vector naming x/y columns.
#' @param budget Integer, total number of samples the loop is allowed to
#'   query (in addition to the initial set).
#' @param batch Integer, number of samples to query per iteration.
#' @param strategy Query strategy — see [al_query()].
#' @param alpha,quantiles,base,cost_weight,physics_gate Forwarded to
#'   [al_query()]. See [al_physics_gate_piml()] for a PIML-backed
#'   physics gate that couples this Pillar 5 loop to a Pillar 2 fit.
#' @param oracle Optional labelling function
#'   `function(samples) -> numeric`. When `NULL`, a simulation oracle
#'   reads the true target from `candidates`.
#' @param stop_rmse Optional early-stop threshold on OOB RMSE.
#' @param num.trees Integer, forest size used at every refit.
#' @param verbose Logical; print per-iteration diagnostics.
#'
#' @return A `edaphos_al_model` whose `$history` contains one entry per
#'   iteration (iter 0 is the initial fit).
#'
#' @examples
#' \donttest{
#'   if (requireNamespace("sp", quietly = TRUE)) {
#'     data(meuse, package = "sp")
#'     d <- stats::na.omit(meuse[, c("x", "y", "dist", "elev",
#'                                   "ffreq", "soil", "lead")])
#'     d$ffreq <- as.numeric(d$ffreq)
#'     d$soil  <- as.numeric(d$soil)
#'     set.seed(1)
#'     seed_idx  <- al_initial_design(d, c("dist", "elev", "ffreq", "soil"),
#'                                    n = 15, iter = 500)
#'     m <- al_loop(
#'       labeled    = d[seed_idx, ],
#'       candidates = d[-seed_idx, ],
#'       target     = "lead",
#'       covariates = c("dist", "elev", "ffreq", "soil"),
#'       coords     = c("x", "y"),
#'       budget     = 20, batch = 5,
#'       strategy   = "hybrid", verbose = FALSE
#'     )
#'     al_history(m)
#'   }
#' }
#' @export
al_loop <- function(labeled, candidates, target, covariates, coords = NULL,
                    budget = 30L, batch = 5L,
                    strategy = c("hybrid", "uncertainty", "diverse", "cost"),
                    alpha = 0.7, quantiles = c(0.1, 0.9),
                    base = NULL, cost_weight = 0.3,
                    physics_gate = NULL,
                    oracle = NULL, stop_rmse = NULL,
                    num.trees = 500L, verbose = TRUE) {
  strategy <- match.arg(strategy)
  .assert_covariates(labeled,    c(target, covariates))
  .assert_covariates(candidates, covariates)
  .assert_coords(labeled, coords)

  if (is.null(oracle)) {
    if (!target %in% names(candidates) ||
        all(is.na(candidates[[target]]))) {
      stop("No `oracle` supplied and `candidates` has no observed ",
           "target to simulate from. Provide `oracle(samples)` or ",
           "pre-fill candidates[[target]].", call. = FALSE)
    }
    oracle <- function(samples) samples[[target]]
  }

  model   <- al_fit(labeled, target = target, covariates = covariates,
                    coords = coords, num.trees = num.trees)
  history <- model$history

  if (verbose) {
    message(sprintf("[iter 0] n=%d  rmse_oob=%.4f",
                    nrow(labeled), history[[1L]]$rmse_oob))
  }

  cand          <- candidates
  queried_total <- 0L
  iter          <- 0L

  while (queried_total < budget && nrow(cand) >= 1L) {
    iter       <- iter + 1L
    this_batch <- min(batch, budget - queried_total, nrow(cand))

    idx <- al_query(
      model, cand, n = this_batch,
      strategy = strategy, alpha = alpha,
      quantiles = quantiles, base = base, cost_weight = cost_weight,
      physics_gate = physics_gate
    )
    new_samples <- cand[idx, , drop = FALSE]
    new_samples[[target]] <- oracle(new_samples)

    # Uncertainty at the queried points, measured on the pre-update model.
    qp <- stats::predict(
      model$model,
      data      = new_samples[, covariates, drop = FALSE],
      type      = "quantiles", quantiles = quantiles
    )$predictions
    mean_unc <- mean(qp[, 2L] - qp[, 1L], na.rm = TRUE)

    cand <- cand[-idx, , drop = FALSE]
    cols <- c(target, covariates, coords)
    labeled <- rbind(model$labeled[cols], new_samples[cols])
    model   <- al_fit(labeled, target = target, covariates = covariates,
                      coords = coords, num.trees = num.trees)

    history <- c(history, list(list(
      iter             = iter,
      n_labeled        = nrow(labeled),
      queried          = idx,
      rmse_oob         = model$history[[1L]]$rmse_oob,
      mean_uncertainty = mean_unc
    )))
    queried_total <- queried_total + this_batch

    if (verbose) {
      message(sprintf(
        "[iter %d] n=%d  +%d queried  rmse_oob=%.4f  mean_unc=%.4f",
        iter, nrow(labeled), this_batch,
        model$history[[1L]]$rmse_oob, mean_unc
      ))
    }
    if (!is.null(stop_rmse) &&
        is.finite(model$history[[1L]]$rmse_oob) &&
        model$history[[1L]]$rmse_oob <= stop_rmse) {
      if (verbose) message("Stop: rmse_oob <= ", stop_rmse)
      break
    }
  }

  model$history <- history
  model
}
