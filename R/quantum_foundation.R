# Pillar 4 x Pillar 6 bridge -- Quantum kernel over foundation embeddings
# (v2.0.0).
#
# The idea: a MoCo v2 encoder (Pillar 4) compresses ~31-channel
# landscape patches into D = 64-dim feature vectors.  A quantum-kernel
# estimator (Pillar 6) lifts its inputs into a Hilbert space of
# dimension 2^n via the ZZFeatureMap [Havlicek et al. 2019].  For
# n <= 8 qubits this lift is classically simulable (our pure-R
# `quantum_kernel()` already computes the Gram matrix).
#
# Composing the two -- PCA the 64-dim foundation embeddings down to
# n = 6-8 principal components, then feed those PCs to the quantum
# kernel -- yields a non-linear kernel over the encoder's
# representation space.  This tests whether the expressive power of
# the quantum kernel carries **downstream prediction gains** that the
# classical RBF kernel over the same PCs does not.
#
# Exports
#   qf_embed_reduce()     : embeddings -> top-n PCs (normalised).
#   qf_kernel_compare()   : Quantum vs RBF vs Linear kernel on the
#                            same PCA-reduced embeddings; reports
#                            Frobenius distance between Gram matrices
#                            and the spectrum divergence.
#   qf_krr_fit()          : quantum KRR over foundation embeddings
#                            (wraps `quantum_krr_fit()` after PCA).
#   qf_krr_benchmark()    : head-to-head of four regressors on SOC
#                            prediction: ranger baseline, RBF-KRR,
#                            quantum-KRR over raw covariates (Pillar 6
#                            original), and quantum-KRR over
#                            foundation embeddings.

# ---------------------------------------------------------------------------
# Embedding -> PCs with automatic scaling to [-pi, pi]
# ---------------------------------------------------------------------------

#' Reduce foundation-model embeddings to PCs and scale to quantum range
#'
#' Takes a matrix of per-observation foundation embeddings and returns
#' the top-`n_pcs` principal components rescaled into `[-pi, pi]`.
#' Zero-variance columns are dropped before PCA.  The rotation and
#' scaling are stored on the return object so new observations can be
#' projected identically.
#'
#' Note that `[-pi, pi]` is twice the `[0, pi]` interval that
#' [`quantum_scale()`] produces and that [`quantum_feature_map()`] and
#' [`quantum_krr_fit()`] document as the ZZFeatureMap's input range.
#' The wider interval doubles the entangling phase
#' \eqn{2(\pi - x_i)(\pi - x_j)}, pushing it several times past the
#' `4 * pi` period of the `Rz` gate; the examples measure what that
#' costs.
#'
#' @param embeddings Numeric matrix (obs x embedding-dim).
#' @param n_pcs Integer; number of PCs to retain.  Default `8L`
#'   (the largest `n` for which `quantum_kernel()` stays classically
#'   simulable on a laptop).
#' @return A list with components `X_q` (the PCs in `[-pi, pi]`,
#'   ready for `quantum_krr_fit()`), `rotation`, `variance_explained`,
#'   `pca_center`, `pca_scale`, and `range_min`/`range_max` used for
#'   the pi-rescale.
#' @examples
#' # A stand-in for a MoCo v2 patch encoder: 64 columns built by a
#' # fixed random projection of five Cerrado covariates through a
#' # tanh, plus noise.  Wide but low-rank, like a real encoder's
#' # output -- and cheap enough to run here.
#' set.seed(42)
#' covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' sub  <- br_cerrado[sample(nrow(br_cerrado), 200L), ]
#' Z    <- scale(as.matrix(sub[, covs]))
#' W    <- matrix(rnorm(5L * 64L), 5L, 64L)
#' emb  <- tanh(Z %*% W) + matrix(rnorm(200L * 64L, 0, 0.1), 200L, 64L)
#'
#' red <- qf_embed_reduce(emb, n_pcs = 6L)
#' dim(red$X_q)                       # 200 x 6: one column per qubit
#' round(red$variance_explained, 3)   # .358 .269 .183 .060 .041 .015
#'
#' # Trap: every PC is stretched to the SAME [-pi, pi] range, so
#' # QPC_6 -- 1.5% of the variance, mostly noise -- reaches the
#' # feature map at the amplitude QPC_1 gets for its 36%.  The PCA
#' # ordering does not survive the rescale:
#' round(apply(red$X_q, 2, sd), 2)    # 1.79 1.67 1.47 1.13 1.27 1.38
#'
#' # n_pcs IS the qubit count, and the simulator carries one state
#' # vector of length 2^n_pcs per sample, so the work behind every
#' # Gram entry doubles with each extra PC.
#' length(quantum_feature_map(rep(0, 6)))    # 64
#' length(quantum_feature_map(rep(0, 12)))   # 4096
#'
#' # The interval is not cosmetic.  Mapping the same PCs onto
#' # [0, pi] -- what quantum_scale() would have produced -- halves
#' # the ZZ phase and leaves visibly more off-diagonal kernel mass,
#' # i.e. a Gram matrix less collapsed onto the identity.
#' Kw <- quantum_kernel(red$X_q[1:60, ], reps = 2L)
#' Kn <- quantum_kernel((red$X_q[1:60, ] + pi) / 2, reps = 2L)
#' c(range_2pi = mean(Kw[upper.tri(Kw)]),
#'   range_pi  = mean(Kn[upper.tri(Kn)]))    # 0.0153 vs 0.0189
#' @export
qf_embed_reduce <- function(embeddings, n_pcs = 8L) {
  stopifnot(is.matrix(embeddings) || is.data.frame(embeddings),
            n_pcs >= 1L)
  emb <- as.matrix(embeddings)
  # Ensure stable column naming so predict() can align newdata
  if (is.null(colnames(emb)))
    colnames(emb) <- sprintf("emb_%03d", seq_len(ncol(emb)))
  vv      <- apply(emb, 2, stats::var, na.rm = TRUE)
  kept    <- which(vv > 1e-12)
  emb_k   <- emb[, kept, drop = FALSE]
  if (ncol(emb_k) < n_pcs) {
    stop(sprintf(
      "Only %d non-constant embedding columns; n_pcs=%d requested.",
      ncol(emb_k), n_pcs
    ), call. = FALSE)
  }
  pr  <- stats::prcomp(emb_k, center = TRUE, scale. = TRUE,
                         rank. = n_pcs)
  pcs <- pr$x[, seq_len(n_pcs), drop = FALSE]

  # Rescale each PC to [-pi, pi]
  rmin <- apply(pcs, 2, min)
  rmax <- apply(pcs, 2, max)
  X_q <- sweep(pcs, 2, rmin, "-")
  X_q <- sweep(X_q,  2, rmax - rmin + 1e-9, "/")
  X_q <- X_q * 2 * pi - pi
  colnames(X_q) <- paste0("QPC_", seq_len(n_pcs))

  list(
    X_q                = X_q,
    rotation           = pr$rotation[, seq_len(n_pcs), drop = FALSE],
    variance_explained = summary(pr)$importance[2, seq_len(n_pcs)],
    pca_center         = pr$center,
    pca_scale          = pr$scale %||% rep(1, ncol(emb_k)),
    kept_columns       = colnames(emb_k),
    range_min          = rmin,
    range_max          = rmax,
    n_pcs              = n_pcs
  )
}

# ---------------------------------------------------------------------------
# Kernel comparison
# ---------------------------------------------------------------------------

#' Compare quantum, RBF, and linear kernels on the same feature set
#'
#' Computes three Gram matrices on the same PCA-reduced embeddings
#' and reports their pairwise Frobenius distance and eigenvalue
#' divergence.  Useful for understanding whether the quantum kernel
#' is materially different from the classical RBF at the same
#' feature space (if not, the quantum lift is cosmetic).
#'
#' @param X_q PCA-reduced, pi-scaled feature matrix (the `X_q`
#'   element of [`qf_embed_reduce()`]).
#' @param reps Integer; ZZFeatureMap repetitions.  Default `2L`.
#' @param rbf_sigma Numeric; RBF kernel bandwidth.  If `NULL`,
#'   uses the median heuristic
#'   `median( || x_i - x_j || )` over the training set.
#' @return Named list with `K_quantum`, `K_rbf`, `K_linear`, and a
#'   `diagnostics` data frame summarising pairwise distances +
#'   effective rank.
#' @examples
#' # Same stand-in MoCo encoder output as in qf_embed_reduce(), on
#' # 60 Cerrado pixels so the three Gram matrices stay 60 x 60.
#' set.seed(42)
#' covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' sub  <- br_cerrado[sample(nrow(br_cerrado), 60L), ]
#' Z    <- scale(as.matrix(sub[, covs]))
#' W    <- matrix(rnorm(5L * 64L), 5L, 64L)
#' emb  <- tanh(Z %*% W) + matrix(rnorm(60L * 64L, 0, 0.1), 60L, 64L)
#'
#' cmp <- qf_kernel_compare(qf_embed_reduce(emb, n_pcs = 6L)$X_q)
#' names(cmp)          # K_quantum, K_rbf, K_linear, rbf_sigma, ...
#' cmp$diagnostics
#'
#' # Read that table carefully.  Only `pair` and `frob` vary by row;
#' # the three effrank_* columns are per-KERNEL and are repeated
#' # identically on all three rows.
#' nrow(unique(cmp$diagnostics[, c("effrank_quantum", "effrank_rbf")]))
#'
#' # And effrank_quantum ~ 59 out of n = 60 is not evidence that the
#' # quantum kernel is richer than the RBF's ~ 4.6.  It is evidence
#' # that it is nearly the IDENTITY: at 6 qubits the ZZFeatureMap
#' # states are close to mutually orthogonal, so K -> I, whose
#' # entropy-based effective rank is exactly n.
#' frob <- function(A, B) sqrt(sum((A - B)^2))
#' c(to_identity = frob(cmp$K_quantum, diag(60)),   # 1.33
#'   to_rbf      = frob(cmp$K_quantum, cmp$K_rbf))  # 37.16
#'
#' # The collapse is driven by the qubit count, not by `reps`.  Off-
#' # diagonal kernel mass roughly halves per PC added, while the RBF
#' # on the identical features holds at 0.61-0.63 throughout.
#' off <- function(K) mean(K[upper.tri(K)])
#' t(vapply(2:6, function(p) {
#'   k <- qf_kernel_compare(qf_embed_reduce(emb, n_pcs = p)$X_q)
#'   c(n_pcs = p, quantum = off(k$K_quantum), rbf = off(k$K_rbf))
#' }, numeric(3)))                  # quantum .314 .137 .065 .032 .016
#'
#' # Deepening the circuit does not undo it -- `reps` leaves the
#' # off-diagonal mass where 6 qubits put it:
#' X6 <- qf_embed_reduce(emb, n_pcs = 6L)$X_q
#' vapply(c(1L, 2L, 4L), function(r)
#'   off(qf_kernel_compare(X6, reps = r)$K_quantum), numeric(1))
#'
#' # A kernel that close to the identity gives kernel ridge nothing
#' # to interpolate with: see the qf_krr_fit() example, where the
#' # 6-PC fit reproduces its training set and then predicts the
#' # training mean everywhere else.
#' @export
qf_kernel_compare <- function(X_q, reps = 2L, rbf_sigma = NULL) {
  stopifnot(is.matrix(X_q))
  K_q <- quantum_kernel(X_q, reps = reps)
  if (is.null(rbf_sigma)) {
    d <- as.matrix(stats::dist(X_q))
    rbf_sigma <- stats::median(d[upper.tri(d)])
  }
  K_r <- exp(- as.matrix(stats::dist(X_q))^2 / (2 * rbf_sigma^2))
  K_l <- tcrossprod(X_q) / ncol(X_q)
  frob <- function(A, B) sqrt(sum((A - B)^2))
  eff_rank <- function(K) {
    ev  <- eigen(K, symmetric = TRUE, only.values = TRUE)$values
    ev  <- pmax(ev, 0)
    p   <- ev / sum(ev)
    p   <- p[p > 0]
    exp(-sum(p * log(p)))   # entropy-based effective rank
  }
  diagnostics <- data.frame(
    pair        = c("quantum_vs_rbf", "quantum_vs_linear",
                     "rbf_vs_linear"),
    frob        = c(frob(K_q, K_r), frob(K_q, K_l), frob(K_r, K_l)),
    stringsAsFactors = FALSE
  )
  diagnostics$frob <- round(diagnostics$frob, 3)
  diagnostics$effrank_quantum <- round(eff_rank(K_q), 2)
  diagnostics$effrank_rbf     <- round(eff_rank(K_r), 2)
  diagnostics$effrank_linear  <- round(eff_rank(K_l), 2)
  list(K_quantum = K_q, K_rbf = K_r, K_linear = K_l,
        rbf_sigma = rbf_sigma,
        diagnostics = diagnostics)
}

# ---------------------------------------------------------------------------
# KRR: quantum over foundation embeddings
# ---------------------------------------------------------------------------

#' Quantum Kernel Ridge Regression on foundation embeddings
#'
#' Fits `quantum_krr_fit()` on the top-n PCs of foundation-model
#' embeddings (rescaled to `[-pi, pi]`).  Returns an object that
#' wraps both the PCA reduction and the quantum KRR fit so `predict()`
#' handles the full forward pipeline.
#'
#' @param embeddings Per-observation embedding matrix.
#' @param y Response vector (regression target).
#' @param n_pcs,reps,lambda See [`qf_embed_reduce()`] and
#'   [`quantum_krr_fit()`].
#' @return An `edaphos_qf_krr` object.
#' @examples
#' # Stand-in MoCo encoder output over 200 Cerrado pixels; the
#' # target is the bundled SOC column (g/kg, 0-5 cm).
#' set.seed(42)
#' covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' sub  <- br_cerrado[sample(nrow(br_cerrado), 200L), ]
#' Z    <- scale(as.matrix(sub[, covs]))
#' W    <- matrix(rnorm(5L * 64L), 5L, 64L)
#' emb  <- tanh(Z %*% W) + matrix(rnorm(200L * 64L, 0, 0.1), 200L, 64L)
#' y    <- sub$soc
#' tr   <- 1:140; te <- 141:200
#'
#' fit <- qf_krr_fit(emb[tr, ], y[tr], n_pcs = 6L, reps = 2L,
#'                   lambda = 0.1)
#' fit
#' pred <- predict(fit, emb[te, ])
#'
#' # The only number that matters is next to the achievable null --
#' # predicting the training mean at every unseen pixel.
#' c(qf_krr = edaphos_rmse(y[te], pred),
#'   train_mean = edaphos_rmse(y[te], rep(mean(y[tr]), length(te))))
#' # 7.45 vs 7.21 g/kg: the fit is WORSE than the mean, and
#' edaphos_r2(y[te], pred)                       # -0.074, i.e. < 0
#'
#' # Two diagnostics that have to be read side by side to see why.
#' # In sample the fit is near-perfect; out of sample its predictions
#' # barely move off the training mean.  With a 6-qubit Gram matrix
#' # this close to the identity (see qf_kernel_compare()), KRR can
#' # only memorise: every test pixel is near-orthogonal to every
#' # training pixel, so the kernel expansion contributes ~ nothing
#' # and prediction falls back on the intercept.
#' c(rmse_in_sample = fit$fit$rmse,              # 0.63
#'   rmse_held_out  = edaphos_rmse(y[te], pred)) # 7.45
#' c(sd_pred = sd(pred), sd_truth = sd(y[te]))   # 1.11 vs 7.25
#'
#' # Fewer qubits concentrate less, but do not rescue it: over
#' # n_pcs 3-6, reps 1-2 and lambda 1e-3..1 the best held-out R2
#' # this fixture produced was 0.012 -- the training mean, again.
#' fit4 <- qf_krr_fit(emb[tr, ], y[tr], n_pcs = 4L, reps = 2L,
#'                    lambda = 1)
#' edaphos_r2(y[te], predict(fit4, emb[te, ]))   # 0.012
#'
#' # Trap in predict(): the PCA centre, rotation and pi-rescale all
#' # come from the TRAINING rows, so a held-out pixel can encode
#' # outside the [-pi, pi] the feature map was scaled for.  Nothing
#' # errors and nothing warns -- the encoding just extrapolates, and
#' # the stored bounds are the only way to notice:
#' rng <- range(fit$reduction$range_min, fit$reduction$range_max)
#' rng                              # training PC span, pre-rescale
#'
#' # Keep column names on newdata as well: an unnamed matrix against
#' # a named training embedding falls back to positional alignment
#' # and warns "NAs introduced by coercion".
#' @export
qf_krr_fit <- function(embeddings, y, n_pcs = 8L,
                         reps = 2L, lambda = 0.1) {
  red <- qf_embed_reduce(embeddings, n_pcs = n_pcs)
  fit <- quantum_krr_fit(red$X_q, as.numeric(y),
                           reps = reps, lambda = lambda)
  structure(list(
    reduction = red, fit = fit,
    n_pcs = n_pcs, reps = reps, lambda = lambda,
    n_train = length(y)
  ), class = "edaphos_qf_krr")
}

#' @export
predict.edaphos_qf_krr <- function(object, newdata, type = "numeric", ...) {
  emb_new <- as.matrix(newdata)
  kept    <- object$reduction$kept_columns
  # Assign default colnames if missing, then align by position
  if (is.null(colnames(emb_new))) {
    if (ncol(emb_new) < length(kept)) {
      stop(sprintf(
        "newdata has %d columns; training used %d non-constant columns.",
        ncol(emb_new), length(kept)
      ), call. = FALSE)
    }
    # Assume first ncol(original training embedding) columns -- after
    # training dropped zero-variance ones.  Align by position of kept.
    pos <- as.integer(sub("^emb_", "", kept))
    if (any(is.na(pos))) {
      # Custom naming in training; fall back to first-N
      pos <- seq_along(kept)
    }
    if (max(pos) > ncol(emb_new))
      stop("newdata has fewer columns than training embedding space.",
            call. = FALSE)
    emb_new <- emb_new[, pos, drop = FALSE]
    colnames(emb_new) <- kept
  } else {
    missing_cols <- setdiff(kept, colnames(emb_new))
    if (length(missing_cols) > 0L)
      stop(sprintf("newdata is missing training columns: %s",
                     paste(utils::head(missing_cols, 5), collapse = ", ")),
            call. = FALSE)
    emb_new <- emb_new[, kept, drop = FALSE]
  }
  X_cs <- sweep(emb_new, 2, object$reduction$pca_center, "-")
  X_cs <- sweep(X_cs, 2, object$reduction$pca_scale, "/")
  pcs  <- X_cs %*% object$reduction$rotation
  X_q  <- sweep(pcs, 2, object$reduction$range_min, "-")
  X_q  <- sweep(X_q, 2,
                  object$reduction$range_max - object$reduction$range_min + 1e-9,
                  "/")
  X_q  <- X_q * 2 * pi - pi
  stats::predict(object$fit, X_q, type = type, ...)
}

# Local helper
`%||%` <- function(a, b) if (is.null(a)) b else a

#' @export
print.edaphos_qf_krr <- function(x, ...) {
  cat("<edaphos_qf_krr>  (Pillar 4 x Pillar 6 bridge)\n")
  cat(sprintf("  n_pcs  = %d  (qubits = %d)\n", x$n_pcs, x$n_pcs))
  cat(sprintf("  reps   = %d\n", x$reps))
  cat(sprintf("  lambda = %.3f\n", x$lambda))
  cat(sprintf("  n_train = %d\n", x$n_train))
  invisible(x)
}

# ---------------------------------------------------------------------------
# Head-to-head benchmark
# ---------------------------------------------------------------------------

#' Benchmark quantum-foundation KRR against classical baselines
#'
#' Runs four regressors on the same train/test split:
#'   1. `ranger` (QRF)  over the RAW covariates (our established
#'      plain-ML baseline from the v1.3 `case-cerrado-end-to-end`).
#'   2. RBF Kernel Ridge Regression over the foundation-embedding PCs.
#'   3. Quantum Kernel Ridge Regression over the RAW covariates
#'      (Pillar 6 original).
#'   4. Quantum Kernel Ridge Regression over the foundation-embedding
#'      PCs (the v2.0.0 contribution).
#'
#' Returns the test-set RMSE, MAE and R^2 for each setup so the
#' question "does the quantum lift on foundation embeddings beat
#' either its quantum-only or foundation-only ancestor?" gets an
#' empirical answer.
#'
#' @param embeddings Foundation-model embedding matrix (n_obs x D).
#' @param covariates Raw-covariate matrix or data frame (n_obs x C).
#' @param y Numeric response.
#' @param train_ix,test_ix Integer index vectors selecting rows for
#'   train/test.  If `NULL`, a 70/30 random split is drawn.
#' @param n_pcs,reps,lambda Passed to [`qf_krr_fit()`].
#' @return A data frame with columns `method`, `rmse`, `mae`, `r2`,
#'   `n_train`, `n_test`.
#' @examples
#' # Stand-in MoCo encoder output plus the five raw covariates it was
#' # built from, over 200 Cerrado pixels, predicting SOC (g/kg).
#' set.seed(42)
#' covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' sub  <- br_cerrado[sample(nrow(br_cerrado), 200L), ]
#' Z    <- scale(as.matrix(sub[, covs]))
#' W    <- matrix(rnorm(5L * 64L), 5L, 64L)
#' emb  <- tanh(Z %*% W) + matrix(rnorm(200L * 64L, 0, 0.1), 200L, 64L)
#' y    <- sub$soc
#' tr   <- 1:140; te <- 141:200
#'
#' # set.seed() even with a fixed split: arm 1 draws 500 ranger trees
#' # from the ambient RNG stream, so its RMSE moves without one.
#' set.seed(7)
#' bm <- qf_krr_benchmark(emb, as.matrix(sub[, covs]), y,
#'                        train_ix = tr, test_ix = te,
#'                        n_pcs = 5L, reps = 2L, lambda = 0.1)
#' bm[, c("method", "rmse", "r2")]
#' #   ranger (raw covariates)         5.02   0.513
#' #   RBF-KRR on foundation PCs       4.98   0.520
#' #   Quantum KRR on raw covariates   6.80   0.105
#' #   Quantum KRR on foundation PCs   7.39  -0.057
#'
#' # The bridge's own arm comes last, and it loses to the null the
#' # whole table has to clear first:
#' edaphos_rmse(y[te], rep(mean(y[tr]), length(te)))   # 7.21
#' # Only the two classical arms beat it.  The quantum lift over the
#' # foundation PCs is worse than predicting the training mean here,
#' # which is what a Gram matrix collapsed onto the identity looks
#' # like downstream -- see qf_kernel_compare().
#'
#' # Three things that make this table less of a head-to-head than
#' # it reads:
#' #  * arms 2 and 3 fit their preprocessing (the PCA, and
#' #    quantum_scale()'s column min/max) on ALL rows, test included;
#' #    arms 1 and 4 only ever see the training rows.
#' #  * arm 3 quantum-encodes the FIRST n_pcs covariate columns, in
#' #    whatever order the matrix happens to have -- not a selection.
#' colnames(as.matrix(sub[, covs]))[1:5]
#' #  * if ncol(covariates) < n_pcs, arm 3 is dropped in silence and
#' #    you get a three-row table with no warning:
#' set.seed(7)
#' nrow(qf_krr_benchmark(emb, as.matrix(sub[, covs[1:3]]), y,
#'                       train_ix = tr, test_ix = te,
#'                       n_pcs = 5L, reps = 2L, lambda = 0.1))   # 3
#' @export
qf_krr_benchmark <- function(embeddings, covariates, y,
                               train_ix = NULL, test_ix = NULL,
                               n_pcs = 8L, reps = 2L, lambda = 0.1) {
  n <- length(y)
  if (is.null(train_ix) || is.null(test_ix)) {
    idx <- sample.int(n)
    cut <- floor(0.7 * n)
    train_ix <- sort(idx[seq_len(cut)])
    test_ix  <- sort(idx[seq(cut + 1L, n)])
  }

  # Use the package's own metric definitions rather than a local copy.  The
  # previous inline version clamped R2 at zero, which silently converted
  # "worse than predicting the mean" into "explains none of the variance" --
  # two very different findings.  edaphos_r2() is deliberately unclamped
  # (it is the Nash-Sutcliffe efficiency), so a negative value now survives
  # into the benchmark table where it belongs.
  metrics <- function(name, pred, truth) {
    data.frame(
      method = name,
      rmse   = edaphos_rmse(truth, pred),
      mae    = edaphos_mae(truth, pred),
      r2     = edaphos_r2(truth, pred),
      n_train = length(train_ix),
      n_test  = length(test_ix),
      stringsAsFactors = FALSE
    )
  }
  cov_mat <- as.matrix(covariates)
  y_num   <- as.numeric(y)
  out     <- list()

  # 1. ranger baseline on raw covariates
  if (requireNamespace("ranger", quietly = TRUE)) {
    df_tr <- data.frame(y = y_num[train_ix],
                         as.data.frame(cov_mat[train_ix, , drop = FALSE]))
    rf <- ranger::ranger(y ~ ., data = df_tr, num.trees = 500L,
                          verbose = FALSE)
    pred_rf <- stats::predict(rf,
      data = as.data.frame(cov_mat[test_ix, , drop = FALSE]))$predictions
    out$rf <- metrics("ranger (raw covariates)",
                       pred_rf, y_num[test_ix])
  }

  # 2. RBF-KRR on foundation embedding PCs
  red <- qf_embed_reduce(embeddings, n_pcs = n_pcs)
  X_q_tr <- red$X_q[train_ix, , drop = FALSE]
  X_q_te <- red$X_q[test_ix,  , drop = FALSE]
  sigma <- stats::median(stats::dist(X_q_tr))
  K_tr  <- exp(- as.matrix(stats::dist(X_q_tr))^2 / (2 * sigma^2))
  n_tr <- nrow(X_q_tr)
  alpha_rbf <- solve(K_tr + lambda * diag(n_tr), y_num[train_ix])
  # Predict: K(te, tr). Manual cross-distance via block of
  # `stats::dist(rbind(te, tr))` to avoid a `proxy` Suggests.
  combo   <- rbind(X_q_te, X_q_tr)
  dcombo  <- as.matrix(stats::dist(combo))
  n_te    <- nrow(X_q_te)
  d_mat   <- dcombo[seq_len(n_te),
                      seq(n_te + 1L, n_te + nrow(X_q_tr)), drop = FALSE]
  K_te    <- exp(- d_mat^2 / (2 * sigma^2))
  pred_rbf <- as.numeric(K_te %*% alpha_rbf)
  out$rbf <- metrics("RBF-KRR on foundation PCs",
                      pred_rbf, y_num[test_ix])

  # 3. Quantum KRR on raw covariates (subset to n_pcs to keep qubits manageable)
  C <- ncol(cov_mat)
  if (C >= n_pcs) {
    X_raw_q <- quantum_scale(cov_mat[, seq_len(n_pcs), drop = FALSE])
    fit_raw <- quantum_krr_fit(X_raw_q[train_ix, , drop = FALSE],
                                  y_num[train_ix],
                                  reps = reps, lambda = lambda)
    pred_raw <- as.numeric(
      stats::predict(fit_raw, X_raw_q[test_ix, , drop = FALSE])
    )
    out$qraw <- metrics("Quantum KRR on raw covariates",
                         pred_raw, y_num[test_ix])
  }

  # 4. Quantum KRR on foundation embedding PCs  (v2.0.0 star)
  fit_qf <- qf_krr_fit(embeddings[train_ix, , drop = FALSE],
                         y_num[train_ix],
                         n_pcs = n_pcs, reps = reps, lambda = lambda)
  # For predict: supply the aligned new embedding matrix
  pred_qf <- as.numeric(
    stats::predict(fit_qf, embeddings[test_ix, , drop = FALSE])
  )
  out$qf <- metrics("Quantum KRR on foundation PCs",
                     pred_qf, y_num[test_ix])

  do.call(rbind, out)
}
