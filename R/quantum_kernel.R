# Pillar 6 — Quantum ML.
#
# Pure-R state-vector simulator + ZZFeatureMap (Havlicek et al. 2019)
# + quantum kernel Gram matrix + Kernel Ridge Regression wrapper.
#
# No external dependencies are pulled in: for up to ~8 features
# (n_qubits <= 8, state-vector length <= 256) the simulator runs in
# milliseconds per sample. Each gate is applied by a bit-level
# permutation of the state vector, which is exactly O(2^n) per gate
# and avoids explicit 2^n x 2^n Kronecker-product expansion.

# ----- Low-level state-vector simulator --------------------------------------

# 2 x 2 gate primitives (little-endian: qubit 0 is the least significant bit
# of the basis-state index i in [0, 2^n - 1]).
.qc_H  <- matrix(c(1,  1,  1, -1), 2L, 2L) / sqrt(2)
.qc_X  <- matrix(c(0,  1,  1,  0), 2L, 2L)

.qc_rz <- function(theta) {
  matrix(
    c(exp(-1i * theta / 2), 0 + 0i,
      0 + 0i,               exp( 1i * theta / 2)),
    2L, 2L, byrow = TRUE
  )
}

# Apply a 2 x 2 gate `G` on qubit `q` (0-based, little-endian) of an
# n-qubit state. Runs in O(2^n) — iterates over index pairs (i, j)
# that differ only in the q-th bit.
.qc_apply_single <- function(state, G, q, n) {
  dim  <- length(state)
  out  <- state
  mask <- bitwShiftL(1L, as.integer(q))
  pairs <- which(bitwAnd(seq.int(0L, dim - 1L), mask) == 0L) - 1L
  for (i in pairs) {
    j <- bitwOr(i, mask)
    a <- state[i + 1L]
    b <- state[j + 1L]
    out[i + 1L] <- G[1L, 1L] * a + G[1L, 2L] * b
    out[j + 1L] <- G[2L, 1L] * a + G[2L, 2L] * b
  }
  out
}

# Apply a CNOT with the given control and target qubits. Again
# little-endian, O(2^n): for every index i whose control bit is 1, the
# target bit is flipped.
.qc_apply_cnot <- function(state, control, target, n) {
  dim   <- length(state)
  out   <- state
  cmask <- bitwShiftL(1L, as.integer(control))
  tmask <- bitwShiftL(1L, as.integer(target))
  flip <- which(bitwAnd(seq.int(0L, dim - 1L), cmask) != 0L) - 1L
  for (i in flip) {
    j <- bitwXor(i, tmask)
    if (j > i) {
      tmp <- out[i + 1L]
      out[i + 1L] <- out[j + 1L]
      out[j + 1L] <- tmp
    }
  }
  out
}

# ----- ZZFeatureMap (Havlicek et al. 2019) -----------------------------------

# Internal: build the quantum state |phi(x)> by applying the data-encoding
# circuit U_phi(x) * H^{otimes n} to |0...0>. `reps` stacks the whole
# encoding `reps` times, increasing kernel expressivity.
.quantum_zz_feature_map <- function(x, reps = 2L) {
  x <- as.numeric(x)
  n <- length(x)
  stopifnot(n >= 1L, is.finite(sum(x)))
  state <- complex(2L^n); state[1L] <- 1 + 0i

  for (r in seq_len(as.integer(reps))) {
    # Hadamard layer -> uniform superposition
    for (q in 0:(n - 1L)) {
      state <- .qc_apply_single(state, .qc_H, q, n)
    }
    # First-order phase rotations: Rz(2 x_i) on qubit i
    for (q in 0:(n - 1L)) {
      state <- .qc_apply_single(state, .qc_rz(2 * x[q + 1L]), q, n)
    }
    # Second-order entangling rotations for all pairs i < j
    if (n >= 2L) {
      for (i in 0:(n - 2L)) {
        for (j in (i + 1L):(n - 1L)) {
          state   <- .qc_apply_cnot(state, i, j, n)
          phi_ij  <- 2 * (pi - x[i + 1L]) * (pi - x[j + 1L])
          state   <- .qc_apply_single(state, .qc_rz(phi_ij), j, n)
          state   <- .qc_apply_cnot(state, i, j, n)
        }
      }
    }
  }
  state
}

#' Quantum feature map (Pillar 6)
#'
#' Returns the complex amplitude vector of the ZZFeatureMap quantum
#' state \eqn{\lvert\phi(\mathbf{x})\rangle} produced by the data-
#' encoding circuit of Havlicek et al. (2019). The feature vector
#' `x` should already be normalised into the range `[0, pi]` — see
#' [quantum_scale()].
#'
#' @param x Numeric vector of features (one qubit per feature).
#' @param reps Integer, number of times the encoding circuit is
#'   repeated (`>= 1`). Higher values give more expressive kernels at
#'   a per-sample simulation cost of `O(reps * 2^n)`.
#'
#' @return Complex vector of length `2^length(x)` — the state-vector
#'   amplitudes of \eqn{\lvert\phi(\mathbf{x})\rangle} in the
#'   computational basis.
#' @export
#' @examples
#' psi <- quantum_feature_map(c(pi/4, pi/3, pi/2), reps = 2L)
#' sum(Mod(psi)^2)  # 1 — quantum state is normalised
quantum_feature_map <- function(x, reps = 2L) {
  .quantum_zz_feature_map(x, reps = reps)
}

# ----- Quantum kernel --------------------------------------------------------

#' Quantum kernel Gram matrix via ZZFeatureMap overlap
#'
#' Computes the Havlicek-et-al. quantum kernel
#' \deqn{K(\mathbf{x}_i, \mathbf{x}_j) \;=\;
#'        \bigl|\langle \phi(\mathbf{x}_j) \mid \phi(\mathbf{x}_i)\rangle\bigr|^2}
#' over one or two datasets whose rows are feature vectors in
#' `[0, pi]` (see [quantum_scale()]). The result is a positive
#' semi-definite matrix with ones on the diagonal.
#'
#' @param X Numeric matrix or data frame (rows = samples, columns =
#'   features). Features are mapped 1-1 to qubits; the number of
#'   qubits equals `ncol(X)`. The current pure-R simulator scales to
#'   about 8 qubits comfortably.
#' @param Y Optional numeric matrix / data frame with the same number
#'   of columns as `X`. When `NULL` (default), the symmetric Gram
#'   matrix `K(X, X)` is returned.
#' @param reps Integer encoding depth — forwarded to
#'   [quantum_feature_map()].
#' @param backend One of `"rcpp"` (default, 10-50x faster; requires
#'   the package to be properly installed so the compiled code is
#'   available) or `"r"` (pure-R reference implementation, kept for
#'   audit and fallback).
#'
#' @return Numeric matrix with `nrow(X)` rows and `nrow(Y %||% X)`
#'   columns; all values lie in `[0, 1]`.
#'
#' @references Havlicek, V. et al. (2019). Supervised learning with
#' quantum-enhanced feature spaces. *Nature* **567**, 209-212.
#'
#' @export
#' @examples
#' set.seed(1)
#' X <- matrix(runif(20, 0, pi), nrow = 5)
#' K <- quantum_kernel(X, reps = 2L)
#' stopifnot(isSymmetric(K))
#' stopifnot(all(abs(diag(K) - 1) < 1e-8))
quantum_kernel <- function(X, Y = NULL, reps = 2L,
                             backend = c("rcpp", "r")) {
  backend <- match.arg(backend)
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  same <- is.null(Y)
  if (same) Y_mat <- X
  else {
    Y_mat <- as.matrix(Y)
    storage.mode(Y_mat) <- "double"
  }
  stopifnot(
    ncol(X) == ncol(Y_mat),
    is.numeric(X), is.numeric(Y_mat),
    all(is.finite(X)), all(is.finite(Y_mat))
  )
  n  <- ncol(X)
  dim_state <- 2L^n
  if (n > 12L && backend == "r") {
    warning("Pure-R state-vector simulation with n_qubits > 12 is slow. ",
            "Consider reducing the feature count.", call. = FALSE)
  }

  # v2.1.3 fast path: Rcpp state-vector simulator (10-50x speedup).
  if (backend == "rcpp") {
    return(quantum_kernel_rcpp(
      X    = X,
      Y_opt = if (same) NULL else Y_mat,
      reps = as.integer(reps)
    ))
  }

  encode <- function(M) {
    out <- matrix(0 + 0i, nrow(M), dim_state)
    for (i in seq_len(nrow(M))) {
      out[i, ] <- .quantum_zz_feature_map(M[i, ], reps = reps)
    }
    out
  }
  states_X <- encode(X)
  states_Y <- if (same) states_X else encode(Y_mat)

  # K[i, j] = |<Y_j | X_i>|^2 = |sum_k states_X[i,k] * Conj(states_Y[j,k])|^2
  K <- Mod(states_X %*% Conj(t(states_Y)))^2
  # Clamp tiny numerical drift.
  if (same) {
    K <- (K + t(K)) / 2
    diag(K) <- 1
  }
  K[K < 0] <- 0
  K
}

#' Rescale a covariate matrix into `[lower, upper]` column-wise
#'
#' Utility for preparing a feature matrix for quantum encoding. The
#' ZZFeatureMap is only expressive when features are on a compact
#' range — the de-facto convention is `[0, pi]`.
#'
#' @param X Numeric matrix / data frame.
#' @param lower,upper Target interval bounds (default `0` and `pi`).
#' @return Numeric matrix with the same dimensions as `X`, rescaled
#'   column-wise -- except for a single-row `X`, which the underlying
#'   `apply()` hands back as a plain named vector.
#' @export
#' @examples
#' ## A clay sweep at constant pH, in field units. Holding pH fixed
#' ## isolates one covariate, and shows the constant-column rule: a
#' ## column with no spread is sent to the midpoint (lower + upper) / 2.
#' clay <- seq(12, 58, by = 2)                      # % clay
#' raw  <- cbind(clay = clay, ph = rep(6.0, length(clay)))
#' X    <- quantum_scale(raw)
#' round(apply(X, 2L, range), 4)   # clay -> [0, pi]; pH -> 1.5708 twice
#'
#' ## Why the rescaling is not cosmetic: the ZZFeatureMap encodes
#' ## covariate i as Rz(2 x_i), so the kernel is PERIODIC in the
#' ## covariate. With a single column the period is exactly pi, and two
#' ## sites pi apart encode to the same state.
#' quantum_kernel(matrix(c(0.7, 0.7 + pi), ncol = 1L), reps = 2L)[1, 2]
#' #  1 -- not "similar", indistinguishable
#'
#' ## Fed raw, clay spans 46 units = 14.6 periods, and kernel similarity
#' ## stops tracking soil similarity. Row 1 is the 12% clay site;
#' ## columns 2, 12 and 23 are the 14%, 34% and 56% sites.
#' k_raw <- quantum_kernel(raw, reps = 2L)[1, ]
#' k_sc  <- quantum_kernel(X,   reps = 2L)[1, ]
#' rbind(raw    = round(k_raw[c(2, 12, 23)], 4),   # 0.2974 0.9967 0.9871
#'       scaled = round(k_sc[ c(2, 12, 23)], 4))   # 0.9368 0.0005 0.0033
#'
#' ## Raw, it is the 34% and 56% sites that come back near-identical to
#' ## the 12% site while its actual neighbour at 14% does not. Over the
#' ## whole sweep the raw encoding carries no distance information:
#' c(raw    = round(cor(k_raw, -(clay - 12)), 4),   # 0.0223
#'   scaled = round(cor(k_sc,  -(clay - 12)), 4))   # 0.5382
#'
#' ## Read 0.5382 as "some", not "all". The ZZ kernel is not a distance
#' ## kernel even on [0, pi] -- it revives at large gaps. Rescaling
#' ## removes the exact aliasing; it does not buy monotonicity.
#'
#' ## TRAP -- the map is refitted from whatever you pass, so scaling a
#' ## validation set on its own puts the same soil at a different angle.
#' ## Carry the CALIBRATION range across instead of calling
#' ## quantum_scale() a second time.
#' val <- cbind(clay = c(20, 34, 40), ph = rep(6.0, 3))
#' rng <- range(raw[, "clay"])
#' round(c(own_map   = unname(quantum_scale(val)[2L, "clay"]),   # 2.1991
#'         train_map = (34 - rng[1L]) * pi / diff(rng)), 4)      # 1.5025
#'
#' ## One site scaled on its own is doubly broken: range() has no spread
#' ## so every covariate collapses to pi/2, and apply() drops the result
#' ## to a vector rather than the 1-row matrix.
#' quantum_scale(val[1L, , drop = FALSE])
quantum_scale <- function(X, lower = 0, upper = pi) {
  X <- as.matrix(X)
  stopifnot(is.numeric(X), upper > lower)
  apply(X, 2L, function(col) {
    r <- range(col, na.rm = TRUE)
    if (diff(r) == 0) return(rep((lower + upper) / 2, length(col)))
    lower + (col - r[1L]) * (upper - lower) / diff(r)
  })
}

# ----- Kernel Ridge Regression wrapper ---------------------------------------

#' Fit a Quantum Kernel Ridge Regression (Pillar 6)
#'
#' Closed-form dual solution
#' \deqn{\boldsymbol{\alpha} = (K + \lambda I)^{-1}\mathbf{y}}
#' using the quantum Gram matrix from [quantum_kernel()]. Works both
#' for regression (`y` numeric) and binary classification (encode
#' `y \in \{-1, +1\}` and threshold the prediction at zero).
#'
#' @param X Feature matrix already rescaled to `[0, pi]` —
#'   [quantum_scale()] is the recommended preprocessor.
#' @param y Numeric response vector (or `\pm 1` for classification).
#' @param reps Integer, encoding depth of the ZZFeatureMap.
#' @param lambda Numeric ridge regulariser (`> 0`).
#'
#' @return An `edaphos_quantum_krr` object.
#' @export
#' @examples
#' \donttest{
#'   ## The target is the sign of an interaction between two covariates -- a
#'   ## checkerboard. In the population neither a linear rule nor a threshold
#'   ## on a single column beats chance on it, so a score here reflects the
#'   ## kernel and not the task. (A target such as y = sign(x1 - mean(x1))
#'   ## is instead solved exactly by the one-line rule that defines it, and a
#'   ## perfect score on it would say nothing about any estimator.)
#'   set.seed(1)
#'   u <- matrix(runif(2 * 400L), ncol = 2L)
#'   y <- sign((u[, 1L] - 0.5) * (u[, 2L] - 0.5))
#'   X <- quantum_scale(u)          # ZZFeatureMap needs features in [0, pi]
#'   tr <- 1:200; te <- 201:400     # fit on 200 points, score on 200 unseen
#'
#'   fit <- quantum_krr_fit(X[tr, ], y[tr], reps = 2L, lambda = 0.1)
#'   mean(predict(fit, X[te, ], type = "class") == y[te])   # 0.75, held out
#'
#'   ## The two numbers 0.75 has to beat before it means anything:
#'   max(table(y[te])) / length(te)                         # 0.53, majority class
#'
#'   ## A fitted linear rule has no signal to latch onto here, so its held-out
#'   ## accuracy is chance in expectation and swings widely from split to
#'   ## split; on this split it happens to land above the majority class.
#'   lin <- lm(y[tr] ~ X[tr, ])
#'   mean(sign(cbind(1, X[te, ]) %*% coef(lin)) == y[te])   # 0.6
#'
#'   ## The same fit scored in sample instead -- optimistic, which is why the
#'   ## held-out number above is the one to read:
#'   mean(predict(fit, X[tr, ], type = "class") == y[tr])   # 0.78, in sample
#'
#'   ## This is a demonstration on two simulated covariates, not a benchmark:
#'   ## it shows the quantum kernel picks up an interaction a linear model
#'   ## cannot, on data with no noise in the labels. Claiming it beats a
#'   ## classical kernel would need the same held-out protocol run against,
#'   ## say, an RBF-kernel ridge fit, repeated over splits, on real data.
#' }
quantum_krr_fit <- function(X, y, reps = 2L, lambda = 0.1) {
  X <- as.matrix(X)
  y <- as.numeric(y)
  stopifnot(nrow(X) == length(y), lambda > 0)
  K <- quantum_kernel(X, reps = reps)
  # Centre the response and carry the offset as an explicit intercept.
  #
  # Kernel ridge regression has no intercept term: solving
  # alpha = (K + lambda I)^-1 y shrinks predictions towards ZERO, not towards
  # the mean of y.  For a response with a large offset relative to its spread
  # -- soil organic carbon on any scale -- the kernel expansion then has to
  # reproduce the mean from scratch, and with a bounded kernel and a non-tiny
  # lambda it cannot.  The model is penalised for the location of the response
  # rather than for its inability to explain the variation, and predictions
  # collapse towards zero.  Centring is the standard remedy and is what makes
  # the ridge penalty act on the signal instead of on the offset.
  y_mean <- mean(y)
  alpha  <- solve(K + lambda * diag(nrow(K)), y - y_mean)
  fitted <- as.vector(K %*% alpha) + y_mean
  rmse   <- sqrt(mean((fitted - y)^2))

  structure(
    list(
      X_train  = X,
      y_train  = y,
      y_mean   = y_mean,
      alpha    = as.numeric(alpha),
      K_train  = K,
      reps     = as.integer(reps),
      lambda   = lambda,
      n_qubits = ncol(X),
      fitted   = fitted,
      rmse     = rmse
    ),
    class = "edaphos_quantum_krr"
  )
}

#' @export
predict.edaphos_quantum_krr <- function(object, newdata,
                                        type = c("numeric", "class"), ...) {
  type <- match.arg(type)
  newdata <- as.matrix(newdata)
  stopifnot(ncol(newdata) == object$n_qubits)
  K_new <- quantum_kernel(newdata, object$X_train, reps = object$reps)
  # `y_mean` is absent from fits produced before the intercept was added;
  # treat those as centred at zero so old objects still predict.
  y_mean <- if (is.null(object$y_mean)) 0 else object$y_mean
  scores <- as.vector(K_new %*% object$alpha) + y_mean
  if (type == "class") {
    # for the classification path the offset is not meaningful
    scores <- scores - y_mean
    labs <- sign(scores)
    labs[labs == 0] <- 1
    as.integer(labs)
  } else {
    scores
  }
}

#' @export
print.edaphos_quantum_krr <- function(x, ...) {
  cat("<edaphos_quantum_krr>\n")
  cat(sprintf("  n_qubits = %d   reps = %d   lambda = %.3g\n",
              x$n_qubits, x$reps, x$lambda))
  cat(sprintf("  n_train  = %d   training RMSE = %.4g\n",
              length(x$y_train), x$rmse))
  invisible(x)
}
