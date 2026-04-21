#' Query the most informative unlabeled candidates
#'
#' Given a fitted Active-Learning model, picks the next `n` candidates to
#' sample according to a trade-off strategy. All strategies use a **greedy
#' batch-mode** selection: the second and later picks within the same call
#' see the previously picked points as if they were already labeled, so the
#' batch remains internally diverse.
#'
#' # Strategies
#' * `"uncertainty"` — highest QRF prediction-interval width (pure
#'   exploitation of model uncertainty).
#' * `"diverse"` — max-min distance in the *standardised* covariate space
#'   from both the current labeled set and the already-picked batch
#'   members (pure exploration).
#' * `"hybrid"` — convex combination
#'   `alpha * uncertainty + (1 - alpha) * diversity` on 0-1 scaled scores.
#'   The recommended default.
#' * `"cost"` — `"hybrid"` minus `cost_weight * cost`, where `cost` is the
#'   0-1 normalised Euclidean distance to a logistical `base` (x, y). Use
#'   this to steer an autonomous sampler (drone, rover) towards points it
#'   can physically reach with limited energy.
#'
#' @param model A `edaphos_al_model`.
#' @param candidates Data frame of unlabeled candidate locations. Must
#'   contain `model$covariates`. Rows with `NA` in any covariate are
#'   ignored.
#' @param n Integer, batch size.
#' @param strategy One of `"hybrid"`, `"uncertainty"`, `"diverse"`,
#'   `"cost"`.
#' @param alpha Numeric in `[0, 1]`, weight of uncertainty vs diversity in
#'   `hybrid` / `cost`.
#' @param quantiles Length-2 numeric with the lower/upper probabilities
#'   used to measure the QRF interval width. Defaults to `c(0.1, 0.9)`.
#' @param base Numeric length-2 vector `c(x, y)`; required by
#'   `strategy = "cost"`.
#' @param cost_weight Numeric, weight of the cost penalty in `"cost"`.
#' @param physics_gate Optional function
#'   `function(candidates, predicted_mean) -> logical` that returns
#'   `TRUE` for physically feasible candidates and `FALSE` for
#'   infeasible ones. Infeasible rows are excluded from the greedy
#'   selection, linking Pillar 5 to Pillar 2 — see
#'   [al_physics_gate_piml()] for a ready-made gate driven by a PIML
#'   profile fit.
#'
#' @return Integer vector of row indices in `candidates` that form the
#'   next batch, in selection order.
#' @export
al_query <- function(model, candidates, n = 5L,
                     strategy = c("hybrid", "uncertainty", "diverse", "cost"),
                     alpha = 0.7, quantiles = c(0.1, 0.9),
                     base = NULL, cost_weight = 0.3,
                     physics_gate = NULL) {
  strategy <- match.arg(strategy)
  if (!inherits(model, "edaphos_al_model")) {
    stop("`model` must be a `edaphos_al_model` (from al_fit / al_loop).",
         call. = FALSE)
  }
  if (!is.numeric(n) || length(n) != 1L || n < 1L) {
    stop("`n` must be a positive integer.", call. = FALSE)
  }
  if (!is.null(physics_gate) && !is.function(physics_gate)) {
    stop("`physics_gate` must be a function or NULL.", call. = FALSE)
  }
  covs <- model$covariates
  .assert_covariates(candidates, covs)

  ok <- stats::complete.cases(candidates[, covs, drop = FALSE])
  if (!any(ok)) {
    stop("No candidate row has complete covariates.", call. = FALSE)
  }
  cand_ok <- candidates[ok, , drop = FALSE]
  n <- min(n, nrow(cand_ok))

  # --- physics gate --------------------------------------------------------
  gate_mask <- rep(TRUE, nrow(cand_ok))
  if (!is.null(physics_gate)) {
    pred_mean <- stats::predict(
      model$model,
      data = cand_ok[, covs, drop = FALSE]
    )$predictions
    gate_mask <- physics_gate(cand_ok, pred_mean)
    if (!is.logical(gate_mask) || length(gate_mask) != nrow(cand_ok)) {
      stop("`physics_gate(candidates, predicted_mean)` must return a ",
           "logical vector of length nrow(candidates).", call. = FALSE)
    }
    if (!any(gate_mask)) {
      stop("`physics_gate` rejected every candidate; loosen the gate.",
           call. = FALSE)
    }
    n <- min(n, sum(gate_mask))
  }

  # --- uncertainty score ---------------------------------------------------
  if (strategy %in% c("uncertainty", "hybrid", "cost")) {
    q <- stats::predict(
      model$model,
      data      = cand_ok[, covs, drop = FALSE],
      type      = "quantiles",
      quantiles = quantiles
    )$predictions
    uncertainty <- q[, 2L] - q[, 1L]
    u_norm <- .norm01(uncertainty)
  } else {
    u_norm <- rep(0, nrow(cand_ok))
  }

  # --- standardised covariate space for diversity --------------------------
  X_cand    <- as.matrix(cand_ok[, covs, drop = FALSE])
  X_labeled <- as.matrix(model$labeled[, covs, drop = FALSE])
  cmb <- rbind(X_cand, X_labeled)
  mu  <- colMeans(cmb, na.rm = TRUE)
  sdv <- apply(cmb, 2L, stats::sd, na.rm = TRUE)
  sdv[!is.finite(sdv) | sdv == 0] <- 1
  Xcs <- sweep(sweep(X_cand,    2L, mu), 2L, sdv, "/")
  Xls <- sweep(sweep(X_labeled, 2L, mu), 2L, sdv, "/")

  # --- spatial cost --------------------------------------------------------
  cost <- rep(0, nrow(cand_ok))
  if (strategy == "cost") {
    if (is.null(model$coords)) {
      stop("Model was fit without `coords`; strategy='cost' requires ",
           "spatial coordinates.", call. = FALSE)
    }
    if (is.null(base) || length(base) != 2L) {
      stop("`base` must be a length-2 numeric vector c(x, y) for ",
           "strategy='cost'.", call. = FALSE)
    }
    xy <- as.matrix(cand_ok[, model$coords, drop = FALSE])
    d  <- sqrt((xy[, 1L] - base[1L])^2 + (xy[, 2L] - base[2L])^2)
    cost <- .norm01(d)
  }

  # --- greedy batch selection ---------------------------------------------
  picked <- integer(0)
  if (nrow(Xls) > 0L) {
    min_dist <- apply(Xcs, 1L, function(row) {
      sqrt(min(rowSums((sweep(Xls, 2L, row))^2)))
    })
  } else {
    min_dist <- rep(Inf, nrow(Xcs))
  }

  for (k in seq_len(n)) {
    d_norm <- if (strategy == "uncertainty") rep(0, nrow(cand_ok))
              else .norm01(min_dist)
    score <- switch(
      strategy,
      uncertainty = u_norm,
      diverse     = d_norm,
      hybrid      = alpha * u_norm + (1 - alpha) * d_norm,
      cost        = alpha * u_norm + (1 - alpha) * d_norm -
                    cost_weight * cost
    )
    score[!gate_mask] <- -Inf
    if (length(picked) > 0L) score[picked] <- -Inf
    pick <- which.max(score)
    picked <- c(picked, pick)
    if (strategy %in% c("diverse", "hybrid", "cost")) {
      newd <- sqrt(rowSums((sweep(Xcs, 2L, Xcs[pick, ]))^2))
      min_dist <- pmin(min_dist, newd)
    }
  }

  which(ok)[picked]
}
