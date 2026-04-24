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
#' the top-`n_pcs` principal components rescaled into `[-pi, pi]`,
#' the natural input range of the ZZFeatureMap.  Zero-variance columns
#' are dropped before PCA.  The rotation and scaling are stored on the
#' return object so new observations can be projected identically.
#'
#' @param embeddings Numeric matrix (obs x embedding-dim).
#' @param n_pcs Integer; number of PCs to retain.  Default `8L`
#'   (the largest `n` for which `quantum_kernel()` stays classically
#'   simulable on a laptop).
#' @return A list with components `X_q` (the PCs in `[-pi, pi]`,
#'   ready for `quantum_krr_fit()`), `rotation`, `variance_explained`,
#'   `pca_center`, `pca_scale`, and `range_min`/`range_max` used for
#'   the pi-rescale.
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

  metrics <- function(name, pred, truth) {
    err <- pred - truth
    data.frame(
      method = name,
      rmse   = sqrt(mean(err^2, na.rm = TRUE)),
      mae    = mean(abs(err), na.rm = TRUE),
      r2     = max(0, 1 - sum(err^2, na.rm = TRUE) /
                          sum((truth - mean(truth, na.rm = TRUE))^2)),
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
