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
#'
#' @examples
#' covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
#'
#' # 30 labeled profiles; every 5th remaining grid cell (399 of them) is
#' # an unlabeled candidate a field crew could still be sent to.
#' set.seed(42)
#' i_lab <- sample(nrow(br_cerrado), 30)
#' lab   <- br_cerrado[i_lab, ]
#' pool  <- br_cerrado[-i_lab, ][seq(1, 1995, by = 5), ]
#'
#' # `seed` fixes the forest, set.seed() fixes ranger's quantile
#' # machinery. Both are needed -- see the reproducibility block below.
#' set.seed(1)
#' m <- al_fit(lab, target = "soc", covariates = covs,
#'             coords = c("x", "y"), seed = 1)
#'
#' # Three strategies plus a random baseline, 8 sites each.
#' b_hyb <- al_query(m, pool, n = 8, strategy = "hybrid")
#' b_unc <- al_query(m, pool, n = 8, strategy = "uncertainty")
#' b_div <- al_query(m, pool, n = 8, strategy = "diverse")
#' set.seed(7)
#' b_rnd <- sample(nrow(pool), 8)
#'
#' # Axis 1 -- how uncertain is the batch? (QRF 80 % interval width.)
#' q <- stats::predict(m$model, data = pool[, covs], type = "quantiles",
#'                     quantiles = c(0.1, 0.9))$predictions
#' w <- q[, 2] - q[, 1]
#' round(c(hybrid = mean(w[b_hyb]), uncertainty = mean(w[b_unc]),
#'         diverse = mean(w[b_div]), random = mean(w[b_rnd]),
#'         whole_pool = mean(w)), 2)
#'
#' # Axis 2 -- how spread out is it? Distance from each member to its
#' # nearest batch-mate, in standardised covariate units.
#' Z  <- scale(as.matrix(pool[, covs]))
#' nn <- function(ix) {
#'   D <- as.matrix(stats::dist(Z[ix, ])); diag(D) <- Inf
#'   mean(apply(D, 1, min))
#' }
#' round(c(hybrid = nn(b_hyb), uncertainty = nn(b_unc),
#'         diverse = nn(b_div), random = nn(b_rnd)), 2)
#'
#' # Read the two together, never one alone. "uncertainty" wins axis 1
#' # (18.75 g/kg) and loses axis 2 to coin-flipping (0.94 vs 1.69): its
#' # greedy top-8 are eight near-copies of one confusing hillslope, so
#' # seven of the eight lab analyses buy almost nothing. "diverse"
#' # inverts that -- widest spacing, but a mean width of 13.96, below
#' # the random batch's 14.47. "hybrid" pays about 1 % of the width for
#' # half again as much spacing, which is why it is the default.
#'
#' # "cost" bends the batch towards a base camp at the SW corner. A
#' # third axis, not a free lunch: the mean trip shortens from 0.283 to
#' # 0.078 degrees and the mean width falls to 17.47.
#' b_cost <- al_query(m, pool, n = 8, strategy = "cost",
#'                    base = c(-47.95, -16.0), cost_weight = 0.6)
#' trip <- function(ix) mean(sqrt((pool$x[ix] + 47.95)^2 +
#'                                (pool$y[ix] + 16)^2))
#' round(c(hybrid_trip = trip(b_hyb), cost_trip = trip(b_cost),
#'         cost_width  = mean(w[b_cost])), 3)
#'
#' # Reproducibility trap. `ranger` seeds the forest from `seed`, but
#' # builds its quantile lookup with R's own RNG at fit time. So the
#' # same `seed` under a different R seed reproduces the OOB RMSE and
#' # returns a DIFFERENT uncertainty batch -- while "diverse", which
#' # never reads a quantile, is untouched.
#' set.seed(2)
#' m2 <- al_fit(lab, target = "soc", covariates = covs,
#'              coords = c("x", "y"), seed = 1)
#' identical(m$history[[1]]$rmse_oob, m2$history[[1]]$rmse_oob)   # TRUE
#' length(intersect(b_hyb,
#'                  al_query(m2, pool, n = 8, strategy = "hybrid")))
#' identical(b_div, al_query(m2, pool, n = 8, strategy = "diverse"))
#'
#' # The return value indexes `candidates` by POSITION, not by row name.
#' identical(pool$soc[b_hyb], br_cerrado$soc[b_hyb])              # FALSE
#' rownames(pool)[b_hyb]        # the br_cerrado rows actually selected
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
