#' Initial sampling design via Conditioned Latin Hypercube (cLHS)
#'
#' Picks an initial labeled subset from a pool of candidate locations
#' using Conditioned Latin Hypercube Sampling (Minasny & McBratney 2006).
#' cLHS spreads the sample uniformly across the joint distribution of the
#' covariates, which is a strong starting point before any model is fit.
#'
#' This is the *seed* step of the Pillar 5 closed-loop Active Learning
#' workflow — the subsequent iterations replace random exploration by
#' uncertainty-guided exploitation (see [al_query()] / [al_loop()]).
#'
#' @param pool Data frame of candidate locations. Must contain the
#'   `covariates` columns; rows with any `NA` in those columns are dropped
#'   prior to optimisation.
#' @param covariates Character vector with covariate column names.
#' @param n Integer, number of initial samples to select.
#' @param seed Optional integer for reproducibility.
#' @param iter Integer, cLHS optimiser iterations (default 1e4 follows
#'   `clhs::clhs` default — use a smaller value for quick prototyping).
#'
#' @return Integer vector with row indices of `pool` that form the
#'   initial labeled set.
#'
#' @references
#' Minasny B, McBratney AB (2006). A conditioned Latin hypercube method
#' for sampling in the presence of ancillary information. *Computers &
#' Geosciences* 32, 1378-1388.
#'
#' @examples
#' \donttest{
#'   if (requireNamespace("sp", quietly = TRUE)) {
#'     data(meuse, package = "sp")
#'     idx <- al_initial_design(meuse, covariates = c("dist", "elev"),
#'                              n = 15, seed = 1, iter = 500)
#'     head(meuse[idx, ])
#'   }
#' }
#' @export
al_initial_design <- function(pool, covariates, n = 20L, seed = NULL,
                              iter = 10000L) {
  .assert_covariates(pool, covariates)
  if (!is.null(seed)) set.seed(seed)
  X <- pool[, covariates, drop = FALSE]
  keep <- stats::complete.cases(X)
  if (sum(keep) < n) {
    stop("Only ", sum(keep), " complete-covariate rows available; ",
         "cannot draw n = ", n, ".", call. = FALSE)
  }
  idx_ok <- which(keep)
  picked <- clhs::clhs(
    X[keep, , drop = FALSE],
    size     = n,
    iter     = iter,
    progress = FALSE,
    simple   = TRUE
  )
  idx_ok[picked]
}
