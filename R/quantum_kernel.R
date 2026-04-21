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
quantum_kernel <- function(X, Y = NULL, reps = 2L) {
  X <- as.matrix(X)
  same <- is.null(Y)
  if (same) Y <- X else Y <- as.matrix(Y)
  stopifnot(
    ncol(X) == ncol(Y),
    is.numeric(X), is.numeric(Y),
    all(is.finite(X)), all(is.finite(Y))
  )
  n  <- ncol(X)
  dim_state <- 2L^n
  if (n > 12L) {
    warning("Pure-R state-vector simulation with n_qubits > 12 is slow. ",
            "Consider reducing the feature count.", call. = FALSE)
  }

  encode <- function(M) {
    out <- matrix(0 + 0i, nrow(M), dim_state)
    for (i in seq_len(nrow(M))) {
      out[i, ] <- .quantum_zz_feature_map(M[i, ], reps = reps)
    }
    out
  }
  states_X <- encode(X)
  states_Y <- if (same) states_X else encode(Y)

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
#'   column-wise.
#' @export
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
#'   set.seed(1)
#'   X <- quantum_scale(matrix(runif(60), ncol = 3L))
#'   y <- sign(X[, 1L] - mean(X[, 1L]))
#'   fit <- quantum_krr_fit(X, y, reps = 2L, lambda = 0.1)
#'   mean(predict(fit, X, type = "class") == y)  # training accuracy
#' }
quantum_krr_fit <- function(X, y, reps = 2L, lambda = 0.1) {
  X <- as.matrix(X)
  y <- as.numeric(y)
  stopifnot(nrow(X) == length(y), lambda > 0)
  K <- quantum_kernel(X, reps = reps)
  alpha <- solve(K + lambda * diag(nrow(K)), y)
  fitted <- as.vector(K %*% alpha)
  rmse   <- sqrt(mean((fitted - y)^2))

  structure(
    list(
      X_train  = X,
      y_train  = y,
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
  scores <- as.vector(K_new %*% object$alpha)
  if (type == "class") {
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
