#' Build a physics gate from a PIML profile fit
#'
#' Convenience helper for constructing the `physics_gate` argument of
#' [al_query()] and [al_loop()] from an existing PIML fit — either the
#' parametric profile ([piml_profile_fit()]) or the Neural ODE variant
#' ([piml_neural_ode_fit()]).
#'
#' The gate rejects any candidate whose model-predicted target value falls
#' outside a physically plausible envelope derived from the PIML fit. For
#' the parametric ODE the envelope is the range the solution actually spans,
#' `[min(y0, y(Inf)), max(y0, y(Inf))]`; for the Neural ODE it is the
#' range of predictions between `z = 0` and the deepest training depth
#' (extrapolated to `2 * max(depth)` as a conservative floor). Both are
#' widened by `safety_factor`.
#'
#' The envelope used to be built from `y_inf`, the equilibrium coordinate of
#' the differential equation. That is not a value any profile reaches, and on
#' real fits it is routinely negative, so the gate certified impossible states
#' as plausible — on the bundled pedon it accepted an SOC of -10 g/kg — while
#' rejecting far more of the legitimate pool than it needed to.
#'
#' @param profile_fit A `edaphos_piml_profile` or
#'   `edaphos_piml_neural_ode` object.
#' @param safety_factor Numeric (>= 1). 1 = strict envelope; 1.2 = allow
#'   20 % slack on each side.
#' @param lower Optional hard lower bound in the target units
#'   (e.g. `0` for mass fractions). Applied as `max(lo_env, lower)`, so
#'   it can only raise the floor, never widen the envelope downwards.
#' @param upper Optional hard upper bound, applied as
#'   `min(hi_env, upper)`: likewise it can only lower the ceiling. Both
#'   clamp inwards; use `safety_factor` to widen.
#'
#' @return A function `function(candidates, predicted_mean)` suitable for
#'   `al_query(..., physics_gate = <this>)`.
#'
#' @examples
#' # One described pedon from a deep Cerrado Latossolo. The auger log
#' # starts at 30 cm, so the surface value is never observed: the ODE
#' # extrapolates it, and the gate's ceiling inherits that extrapolation.
#' depths <- c(30, 50, 80, 120, 200)
#' values <- c(11.5, 9.2, 7.4, 6.1, 5.2)          # SOC, g/kg
#' pf     <- piml_profile_fit(depths, values)
#' y0     <- unname(pf$params$y0)
#' y_asym <- unname(edaphos:::.piml_asymptote(pf$params))
#' round(c(y0 = y0, y_asym = y_asym, y_inf = unname(pf$params$y_inf),
#'         shallowest_observed = values[1], fit_rmse = pf$rmse), 2)
#'
#' # y0 = 18.61 g/kg is 62 % above the shallowest measurement -- the auger
#' # log starts at 30 cm, so the surface is extrapolated. The envelope is
#' # [y_asym, y0] widened by (safety_factor - 1) * (y0 - y_asym) on each
#' # side, so here [1.92, 21.39]. y_inf = 2.69 sits well below y_asym = 4.70:
#' # the profile stops less than a fifth of the way to it.
#' gate <- al_physics_gate_piml(pf, safety_factor = 1.2)
#' span <- y0 - y_asym
#' round(c(lo = y_asym - 0.2 * span, hi = y0 + 0.2 * span), 2)
#'
#' # The gate reads the PREDICTION only and never looks at the candidate
#' # covariates, so `candidates` can be anything at all.
#' gate(candidates = NULL, predicted_mean = c(2, 3, 10, 18, 19, 25))  # only 25 fails
#'
#' # Point it at a real pool and COUNT: a gate that returns a mask has
#' # not necessarily rejected anything.
#' covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' set.seed(42)
#' i_lab <- sample(nrow(br_cerrado), 30)
#' set.seed(1)
#' m <- al_fit(br_cerrado[i_lab, ], target = "soc", covariates = covs,
#'             coords = c("x", "y"), seed = 1)
#' pool <- br_cerrado[-i_lab, ][seq(1, 1995, by = 5), ]
#' pm   <- stats::predict(m$model, data = pool[, covs])$predictions
#' keep <- gate(pool, pm)
#' c(rejected = sum(!keep), n = length(keep))             # 89 of 399
#' round(rbind(rejected = range(pm[!keep]), kept = range(pm[keep])), 2)
#'
#' # A named casualty: pool row 22, predicted 27.34 g/kg, true SOC
#' # 26.37 -- an ordinary Cerrado topsoil, refused because one pedon
#' # described from 30 cm down says no profile may exceed 21.39.
#' j <- which(!keep)[which.max(pm[!keep])]
#' round(c(row = j, predicted = pm[j], true_soc = pool$soc[j]), 2)
#'
#' # 72 % of the 89 refusals really are above the ceiling, so the gate
#' # is not firing at random -- it is mis-scaled. It promotes ONE
#' # pedon's dynamics into a constraint on every cell of a 0-5 cm map,
#' # and the cells it removes are the carbon-rich ones. Building the
#' # envelope from the attained value rather than y_inf cut the refusals
#' # from 178 to 89, but did not make the extrapolation legitimate.
#' round(c(share_truly_above  = mean(pool$soc[!keep] > y0 + 0.2 * span),
#'         mean_true_rejected = mean(pool$soc[!keep]),
#'         mean_true_kept     = mean(pool$soc[keep])), 2)
#'
#' # It changes the batch, not just the mask: the batch ceiling drops
#' # from 21.83 to 19.15 g/kg.
#' b_gate <- al_query(m, pool, n = 8, strategy = "hybrid",
#'                    physics_gate = gate)
#' b_open <- al_query(m, pool, n = 8, strategy = "hybrid")
#' rbind(gated = b_gate, open = b_open)
#' round(c(max_pred_gated = max(pm[b_gate]),
#'         max_pred_open  = max(pm[b_open])), 2)
#'
#' # `lower` and `upper` clamp inwards only. lower = 0, intended to
#' # "allow zero SOC", cannot widen anything; upper = 12 does bite.
#' identical(al_physics_gate_piml(pf, 1.2, lower = 0)(pool, pm), keep)
#' sum(!al_physics_gate_piml(pf, 1.2, upper = 12)(pool, pm))      # 338
#'
#' # A gate nobody can pass is an error, not an empty batch.
#' try(al_query(m, pool, n = 3,
#'              physics_gate = al_physics_gate_piml(pf, 1.2, upper = 1)))
#' @export
al_physics_gate_piml <- function(profile_fit, safety_factor = 1.2,
                                 lower = NULL, upper = NULL) {
  stopifnot(is.numeric(safety_factor), length(safety_factor) == 1L,
            safety_factor >= 1)

  if (inherits(profile_fit, "edaphos_piml_profile")) {
    # The envelope is the range the SOLUTION spans, which is [y0, y(Inf)] --
    # the solution is monotone in z, so it never leaves that interval. It is
    # NOT [y0, y_inf]: y_inf is a coordinate of the differential equation that
    # the profile only approaches by a fraction 1 - e^{-kappa}, and on real
    # fits it is routinely far outside the attainable range (on the bundled
    # pedon, -5.88 g/kg). Using it certified negative carbon as plausible.
    y_end <- .piml_asymptote(profile_fit$params)
    lo <- min(profile_fit$params$y0, y_end)
    hi <- max(profile_fit$params$y0, y_end)
    # piml_profile_fit() refuses a non-positive observation, so this branch is
    # by construction a fit to a positive property and zero is a hard floor.
    lower_default <- 0
  } else if (inherits(profile_fit, "edaphos_piml_neural_ode")) {
    ref_z <- c(0, profile_fit$depths, max(profile_fit$depths) * 2)
    ref_y <- piml_neural_ode_predict(profile_fit, ref_z)
    lo <- min(ref_y, na.rm = TRUE)
    hi <- max(ref_y, na.rm = TRUE)
    # The Neural ODE has no positivity restriction and may legitimately be
    # fitted to a signed property, so only floor at zero when the training
    # values themselves were positive.
    lower_default <- if (all(profile_fit$values > 0, na.rm = TRUE)) 0 else NULL
  } else {
    stop("`profile_fit` must be a edaphos_piml_profile or ",
         "edaphos_piml_neural_ode.", call. = FALSE)
  }

  slack  <- safety_factor - 1
  span   <- max(abs(hi - lo), 1e-9)
  lo_env <- lo - slack * span
  hi_env <- hi + slack * span
  # The widening is what drives the floor negative, and it did so on 82% of a
  # 300-pedon sample of the shipped WoSIS profiles -- the gate passed an SOC of
  # -5 g/kg on 73 of them. Rebuilding the envelope from the attained value
  # closed one route to a negative floor; `slack * span` is the other. Floor at
  # zero unless the caller explicitly overrides.
  if (is.null(lower)) lower <- lower_default
  if (!is.null(lower)) lo_env <- max(lo_env, lower)
  if (!is.null(upper)) hi_env <- min(hi_env, upper)

  function(candidates, predicted_mean, ...) {
    predicted_mean >= lo_env & predicted_mean <= hi_env
  }
}
