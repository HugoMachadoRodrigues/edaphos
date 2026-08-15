# Pillar 1 x Pillar 5 bridge -- Causal Active Learning.
#
# Classical AL (Pillar 5) asks: "where is my outcome Y most uncertain?"
# and picks the next sample that maximally reduces predictive MSE.  In
# causal DSM we frequently care about a DIFFERENT quantity: the
# backdoor-adjusted direct effect beta(X->Y), whose CI width is what
# matters for decision-making (e.g. "does MAP really drive SOC?").
#
# `al_query_causal()` answers: "where is the next sample that most
# reduces the Var(beta_hat) estimated over a bootstrap?".  The
# heuristic used here -- the *leverage-aware* CRPS gain on the
# bootstrap posterior after hypothetically adding one more sample
# -- is derived in the accompanying vignette.
#
# Formal setup
# ------------
# Given a labelled pool D = {(X_i, Y_i, Z_i)}_{i=1}^n and a DAG G with
# exposure X and outcome Y, the backdoor-adjusted effect is
#
#   beta_hat = argmin_beta  sum_i ( Y_i - beta X_i - theta' Z_i )^2
#
# The sampling-variance of beta_hat under a block bootstrap is
# Var(beta_hat) = (X' P_Z X)^{-1} sigma^2  where P_Z projects out the
# adjustment set Z.  Adding a candidate (x*, z*) changes X' P_Z X by a
# rank-1 update; the *leverage* h(x*, z*) is the classical hat-matrix
# diagonal, and Var_new / Var_old shrinks most at candidates with
# highest h.
#
# For each candidate in `pool`, `al_query_causal()` computes h and
# returns the top-`n_select` points that most shrink Var(beta_hat).

#' Causal Active Learning: query the next sample(s) that most reduce
#' the uncertainty of a targeted causal effect
#'
#' Closes the loop between Pillar 1 (causal identification via
#' backdoor adjustment) and Pillar 5 (autonomous active learning):
#' instead of choosing candidates by marginal-Y uncertainty (classical
#' AL), we choose by expected shrinkage of `Var(beta_hat_{X->Y})`.
#'
#' @param data Data frame with the exposure, outcome and adjustment
#'   columns (the current labelled set).
#' @param pool Data frame with the same columns as `data`; the
#'   unlabelled candidate pool to query.
#' @param dag A `dagitty` DAG.
#' @param exposure,outcome Character; column names of the causal query.
#' @param adjustment Optional character vector of adjustment-set
#'   columns.  Inferred from `dag` via [`causal_adjustment_set()`]
#'   when `NULL`.
#' @param n_select Integer; how many candidates to return.  Default
#'   `5L`.
#' @param strategy One of `"leverage"` (hat-matrix diagonal,
#'   closed-form, fast, deterministic) or `"bootstrap"` (re-bootstrap
#'   `Var(beta_hat)` once per candidate). `"bootstrap"` costs
#'   `B * (|pool| + 1)` OLS fits and its ranking is a Monte-Carlo
#'   estimate: at `B = 100` on 80 sites the ordering of five candidates
#'   changes with `seed` (see the examples), so raise `B` until the
#'   ordering stabilises before reading anything into it.
#' @param B Bootstrap replications when `strategy = "bootstrap"`.
#' @param seed RNG seed for bootstrap reproducibility.
#' @return A data frame with one row per candidate, columns
#'   `pool_index`, `leverage`, `expected_var_reduction`, sorted by
#'   descending expected reduction.  The top-`n_select` rows are the
#'   recommended next samples.
#'
#' @examples
#' if (requireNamespace("dagitty", quietly = TRUE)) {
#'   # 80 labelled sites, 200 unlabelled candidates. The question is not
#'   # "where is SOC uncertain?" but "how hard does rainfall push SOC?".
#'   set.seed(11)
#'   i_d  <- sample(nrow(br_cerrado), 80)
#'   cols <- c("map_mm", "elev", "twi", "ndvi", "soc")
#'   dat  <- br_cerrado[i_d, cols]
#'   pool <- br_cerrado[-i_d, cols][1:200, ]
#'
#'   # On 80 sites the effect is not distinguishable from zero (t = 0.79).
#'   # That is the situation this bridge exists for. (Inside a guarded
#'   # block nothing auto-prints, hence the explicit print() calls.)
#'   cf <- summary(stats::lm(soc ~ map_mm + elev + ndvi, dat))$coefficients
#'   print(round(cf["map_mm", c("Estimate", "Std. Error", "t value")], 5))
#'
#'   dag <- dagitty::dagitty(
#'     "dag { elev -> map_mm ; elev -> soc ; twi -> soc ;
#'            map_mm -> ndvi ; map_mm -> soc ; ndvi -> soc }")
#'   q <- al_query_causal(dat, pool, dag, exposure = "map_mm",
#'                        outcome = "soc", n_select = 5L)
#'   print(q)
#'
#'   # The set is inferred for the DIRECT effect, so the mediator ndvi is
#'   # in it while twi, which opens no backdoor path, is not.
#'   print(attr(q, "adjustment"))
#'
#'   # Row names are inherited from `pool`, `pool_index` is the position
#'   # in it. Use the column; as.integer(rownames(q)) is a different row.
#'   print(c(rowname     = rownames(q)[1],
#'           pool_index  = q$pool_index[1],
#'           resolves_to = rownames(pool)[q$pool_index[1]]))
#'
#'   # Leverage is a property of the design matrix alone: blank out every
#'   # outcome in the pool and the ranking does not move one place.
#'   pool_na <- pool; pool_na$soc <- NA_real_
#'   print(identical(q$pool_index,
#'                   al_query_causal(dat, pool_na, dag, exposure = "map_mm",
#'                                   outcome = "soc")$pool_index))   # TRUE
#'
#'   # And it is JOINT, not marginal. Row 187 sits at the 40th percentile
#'   # of the exposure yet ranks 4th, on the strength of being at the 6th
#'   # percentile of elev and the maximum of ndvi.
#'   top <- utils::head(q$pool_index, 5)
#'   pct <- function(cc, i) round(100 * mean(pool[[cc]] <= pool[[cc]][i]))
#'   print(t(sapply(top, function(i)
#'     c(row = i, map_mm = pct("map_mm", i), elev = pct("elev", i),
#'       ndvi = pct("ndvi", i)))))
#'
#'   # Classical Pillar 5 asks a different question of the same pool and
#'   # gets a disjoint answer: 0 of its 5 picks are in the causal top 5.
#'   set.seed(3)
#'   m <- al_fit(dat, target = "soc",
#'               covariates = c("map_mm", "elev", "twi", "ndvi"), seed = 3)
#'   print(length(intersect(top, al_query(m, pool, n = 5,
#'                                        strategy = "uncertainty"))))
#'
#'   # `expected_var_reduction` is h / (1 + h), a monotone relabelling of
#'   # `leverage`: under strategy = "leverage" the two columns always
#'   # rank identically, and neither is a variance in the units of beta.
#'   print(stats::cor(rank(q$leverage), rank(q$expected_var_reduction)))
#'
#'   # strategy = "bootstrap" re-bootstraps Var(beta_hat) once per
#'   # candidate. At B = 100 the answer is Monte-Carlo noise: three seeds
#'   # give three orderings of the same five candidates, none of them the
#'   # closed-form one. Raise B until the ordering stops moving.
#'   ord <- function(s) al_query_causal(dat, pool[1:5, ], dag,
#'                                      exposure = "map_mm",
#'                                      outcome  = "soc",
#'                                      strategy = "bootstrap",
#'                                      B = 100L, seed = s)$pool_index
#'   print(rbind(seed1 = ord(1), seed2 = ord(2), seed3 = ord(3),
#'               leverage = al_query_causal(dat, pool[1:5, ], dag,
#'                                          exposure = "map_mm",
#'                                          outcome  = "soc")$pool_index))
#' }
#' @export
al_query_causal <- function(data, pool, dag,
                              exposure, outcome,
                              adjustment = NULL,
                              n_select = 5L,
                              strategy = c("leverage", "bootstrap"),
                              B = 200L, seed = NULL) {
  strategy <- match.arg(strategy)
  stopifnot(is.data.frame(data), is.data.frame(pool),
            is.character(exposure), length(exposure) == 1L,
            is.character(outcome),  length(outcome)  == 1L)
  if (is.null(adjustment)) {
    adjustment <- causal_adjustment_set(dag, exposure, outcome,
                                           effect = "direct")
    if (is.null(adjustment)) {
      stop("Effect is not identifiable from the supplied DAG.",
            call. = FALSE)
    }
  }

  feat_cols <- unique(c(exposure, adjustment))
  X_train <- as.matrix(data[, feat_cols, drop = FALSE])
  X_train <- cbind(intercept = 1, X_train)
  X_pool  <- as.matrix(pool[, feat_cols, drop = FALSE])
  X_pool  <- cbind(intercept = 1, X_pool)

  # Hat-matrix diagonal of the combined design after pretending to add
  # one candidate at a time.
  XtX    <- crossprod(X_train)
  XtX_inv <- .safe_inverse(XtX, "training design X'X")
  # Leverage of each pool candidate under the CURRENT design
  # (h_i = x_i' (X'X)^{-1} x_i).  Higher h = more sensitive response
  # to adding that point.
  lev <- rowSums((X_pool %*% XtX_inv) * X_pool)

  # Var(beta_hat) shrinkage factor after adding candidate i is
  # approximately (1 - h_i / (1 + h_i)) for the linear hat-leverage.
  expected_red <- lev / (1 + lev)

  if (strategy == "bootstrap") {
    # O(B*|pool|) bootstrap: refit for each candidate, measure shrinkage
    # of Var(beta).  Used only when `n_select` is small and the leverage
    # approximation needs audit.
    #
    # `causal_effect_bootstrap()` always resamples clusters and validates
    # `cluster` with is.character(), so passing NULL for un-clustered data
    # aborted with "is.character(cluster) is not TRUE".  When the caller
    # has not clustered the data, every row is its own cluster, which is
    # exactly the ordinary nonparametric bootstrap.
    clus      <- "kmeans_cluster"
    boot_data <- data
    boot_pool <- pool
    if (!clus %in% names(boot_data)) {
      boot_data[[clus]] <- seq_len(nrow(boot_data))
      boot_pool[[clus]] <- nrow(boot_data) + seq_len(nrow(boot_pool))
    }
    if (!is.null(seed)) set.seed(seed)
    var_base <- stats::var(
      causal_effect_bootstrap(
        data = boot_data, dag = dag,
        exposure = exposure, outcome = outcome,
        adjustment = adjustment,
        cluster = clus,
        B = B
      )
    )
    var_new <- numeric(nrow(pool))
    for (i in seq_len(nrow(pool))) {
      d_plus <- rbind(boot_data,
                       boot_pool[i, names(boot_data), drop = FALSE])
      var_new[i] <- stats::var(
        causal_effect_bootstrap(
          data = d_plus, dag = dag,
          exposure = exposure, outcome = outcome,
          adjustment = adjustment,
          cluster = clus,
          B = B
        )
      )
    }
    expected_red <- pmax(var_base - var_new, 0) / var_base
  }

  out <- data.frame(
    pool_index             = seq_len(nrow(pool)),
    leverage               = lev,
    expected_var_reduction = expected_red,
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$expected_var_reduction), ]
  attr(out, "exposure")   <- exposure
  attr(out, "outcome")    <- outcome
  attr(out, "adjustment") <- adjustment
  attr(out, "strategy")   <- strategy
  attr(out, "n_select")   <- n_select
  structure(out, class = c("edaphos_causal_al_query", "data.frame"))
}

#' @export
print.edaphos_causal_al_query <- function(x, ...) {
  cat("<edaphos_causal_al_query>  (Pilar 1 x Pilar 5 bridge)\n")
  cat(sprintf("  target effect : %s -> %s\n",
               attr(x, "exposure"), attr(x, "outcome")))
  cat(sprintf("  adjustment    : %s\n",
               paste(attr(x, "adjustment"), collapse = ", ")))
  cat(sprintf("  strategy      : %s\n", attr(x, "strategy")))
  cat(sprintf("  n_select      : %d\n", attr(x, "n_select")))
  cat(sprintf("  top-%d candidates:\n", attr(x, "n_select")))
  print(as.data.frame(utils::head(x, attr(x, "n_select"))))
  invisible(x)
}
