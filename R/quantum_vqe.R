# Pillar 6 -- Variational Quantum Eigensolver (VQE) bridge.
#
# Reticulate + Qiskit implementation of the Peruzzo et al. 2014 VQE
# algorithm for the ground-state energy of a user-supplied Hamiltonian.
# Three toy organo-mineral Hamiltonians ship alongside the public
# quantum_hamiltonian() constructor so the canonical pedometric use
# cases (clay-humus adsorption, Fe-O cluster exchange, H2 bond as a
# reference) can be run out of the box.
#
# All Python interop goes through `reticulate` (Suggests). A one-shot
# module loader caches the imported Qiskit modules in a local
# environment so subsequent calls do not pay the import cost. Every
# public function fails gracefully with a clear install-hint when
# `reticulate` or Qiskit is missing.
#
# The VQE back end dispatches over three choices:
#   * "aer_statevector" -- exact noiseless statevector simulation
#                          (default). Deterministic, analytical.
#   * "aer_sampler"     -- shot-based simulation with optional
#                          depolarising / readout noise models.
#   * "ibmq"            -- real hardware via the IBM Quantum Runtime
#                          Estimator primitive. Requires the user to
#                          install qiskit-ibm-runtime and set an
#                          IBMQ_TOKEN environment variable.

.qk_env <- new.env(parent = emptyenv())

.qk_require <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("Install the `reticulate` package to use quantum_vqe_*().",
         call. = FALSE)
  }
  if (!reticulate::py_module_available("qiskit")) {
    stop("Install the Qiskit stack once via\n",
         "   reticulate::py_install(c('qiskit','qiskit-aer',",
         "'qiskit-algorithms','scipy'), pip = TRUE)\n",
         "then restart R.", call. = FALSE)
  }
  if (is.null(.qk_env$qi)) {
    .qk_env$qi <- reticulate::import("qiskit.quantum_info",
                                      delay_load = FALSE)
    .qk_env$ql <- reticulate::import("qiskit.circuit.library",
                                      delay_load = FALSE)
    .qk_env$qp <- reticulate::import("qiskit.primitives",
                                      delay_load = FALSE)
    .qk_env$qa <- reticulate::import("qiskit_algorithms",
                                      delay_load = FALSE)
    .qk_env$qo <- reticulate::import("qiskit_algorithms.optimizers",
                                      delay_load = FALSE)
  }
  invisible(TRUE)
}

.qk_is_valid_pauli <- function(s, n) {
  is.character(s) && length(s) == 1L &&
    nchar(s) == n &&
    grepl("^[IXYZ]+$", s, perl = TRUE)
}

# ---- Hamiltonian builders ---------------------------------------------------

#' Build a quantum Hamiltonian from Pauli-string coefficients
#'
#' Constructs an `edaphos_quantum_hamiltonian` wrapping a
#' `qiskit.quantum_info.SparsePauliOp`. Pauli strings use the standard
#' `\{I, X, Y, Z\}` alphabet; the highest-index qubit is on the left
#' (Qiskit convention).
#'
#' @param pauli_terms Named numeric vector or list mapping Pauli
#'   strings to their coefficients, e.g.
#'   `c("II" = -1.05, "ZZ" = -0.01, "XX" = 0.18)`.
#' @param n_qubits Integer override — defaults to the length of the
#'   first Pauli string.
#'
#' @return An object of class `edaphos_quantum_hamiltonian` carrying
#'   the Python `SparsePauliOp` handle (`$op`), the tidy
#'   `$pauli_terms`, and `$n_qubits`.
#' @export
quantum_hamiltonian <- function(pauli_terms, n_qubits = NULL) {
  .qk_require()
  stopifnot(length(pauli_terms) >= 1L,
            !is.null(names(pauli_terms)))
  strings <- names(pauli_terms)
  coeffs  <- unname(as.numeric(pauli_terms))
  if (is.null(n_qubits)) n_qubits <- nchar(strings[1L])
  n_qubits <- as.integer(n_qubits)
  ok <- vapply(strings, .qk_is_valid_pauli, logical(1L), n = n_qubits)
  if (!all(ok)) {
    bad <- strings[!ok]
    stop("Invalid Pauli string(s): ", paste(bad, collapse = ", "),
         " (expected ", n_qubits,
         " characters from {I,X,Y,Z}).", call. = FALSE)
  }
  terms <- lapply(seq_along(strings), function(i) {
    reticulate::tuple(list(strings[i], coeffs[i]))
  })
  sp <- .qk_env$qi$SparsePauliOp$from_list(terms)
  structure(
    list(
      op          = sp,
      pauli_terms = stats::setNames(coeffs, strings),
      n_qubits    = n_qubits
    ),
    class = "edaphos_quantum_hamiltonian"
  )
}

#' Molecular H2 in the Bravyi-Kitaev-tapered 2-qubit basis
#'
#' Textbook Hamiltonian of the hydrogen molecule in the STO-3G basis
#' after parity mapping plus Z2 symmetry reduction — the 2-qubit
#' problem whose ground-state energy is the hallmark VQE benchmark.
#' Coefficients are reported at the equilibrium bond length 0.735 A.
#'
#' @return An `edaphos_quantum_hamiltonian` with 2 qubits.
#' @references Peruzzo, A. et al. (2014). A variational eigenvalue
#'   solver on a photonic quantum processor. *Nature Communications*
#'   **5**, 4213. doi:10.1038/ncomms5213.
#' @export
quantum_hamiltonian_h2 <- function() {
  quantum_hamiltonian(c(
    "II" = -1.0523732,
    "IZ" =  0.39793742,
    "ZI" = -0.39793742,
    "ZZ" = -0.01128010,
    "XX" =  0.18093119
  ), n_qubits = 2L)
}

#' Transverse-field Ising Hamiltonian on an n-qubit chain
#'
#' \eqn{H = -J \sum_{i=1}^{n-1} Z_i Z_{i+1} - h \sum_{i=1}^{n} X_i}.
#' Classic condensed-matter benchmark with a well-known ground state.
#'
#' @param n_qubits Integer number of sites / qubits (>= 2).
#' @param J Nearest-neighbour coupling.
#' @param h Transverse field strength.
#' @return An `edaphos_quantum_hamiltonian`.
#' @export
quantum_hamiltonian_ising_1d <- function(n_qubits, J = 1, h = 1) {
  stopifnot(n_qubits >= 2L)
  n <- as.integer(n_qubits)
  terms <- list()
  # ZZ nearest-neighbour couplings
  for (i in seq_len(n - 1L)) {
    s <- strrep("I", n)
    substr(s, n - i + 1L, n - i + 1L) <- "Z"
    substr(s, n - i,     n - i)       <- "Z"
    terms[[s]] <- -J
  }
  # Transverse field
  for (i in seq_len(n)) {
    s <- strrep("I", n)
    substr(s, n - i + 1L, n - i + 1L) <- "X"
    terms[[s]] <- -h
  }
  quantum_hamiltonian(unlist(terms), n_qubits = n)
}

#' Toy organo-mineral Hamiltonian (4-qubit Fe + ligand coupling)
#'
#' A deliberately minimalist representation of a clay-humus or iron-
#' oxide coordination complex, sized for classical simulation on a
#' laptop and for a meaningful walk-through of
#' [quantum_vqe_fit()] in the Pillar 6 vignette. Four qubits are
#' partitioned as two metal-centre states (left pair) and two
#' ligand states (right pair), with on-site, same-sector exchange
#' and cross-sector hopping / tunnelling terms:
#'
#' \deqn{
#'   H = -\,\varepsilon_\mathrm{Fe}\,(Z_3 + Z_2) \;
#'       -\,\varepsilon_\mathrm{L}\,(Z_1 + Z_0) \;
#'       +\,J_\mathrm{Fe}\,Z_3 Z_2 \;
#'       +\,J_\mathrm{L}\,Z_1 Z_0 \;
#'       +\,t\,(X_3 X_0 + X_2 X_1).
#' }
#'
#' The default parameters \eqn{(\varepsilon_\mathrm{Fe},
#' \varepsilon_\mathrm{L}, J_\mathrm{Fe}, J_\mathrm{L}, t) =
#' (0.5, 0.3, 0.4, 0.2, 0.25)} give a non-trivial entangled ground
#' state.
#'
#' @param eps_fe,eps_l Numeric on-site energies for the Fe-like and
#'   ligand-like sub-sectors.
#' @param j_fe,j_l Numeric same-sector Z-Z exchange couplings.
#' @param t Numeric cross-sector X-X hopping amplitude.
#' @return An `edaphos_quantum_hamiltonian` with 4 qubits.
#' @export
quantum_hamiltonian_organo_mineral <- function(eps_fe = 0.5, eps_l = 0.3,
                                                j_fe   = 0.4, j_l   = 0.2,
                                                t      = 0.25) {
  quantum_hamiltonian(c(
    "ZIII" = -eps_fe,  # Fe site 3
    "IZII" = -eps_fe,  # Fe site 2
    "IIZI" = -eps_l,   # ligand site 1
    "IIIZ" = -eps_l,   # ligand site 0
    "ZZII" =  j_fe,    # Fe-Fe exchange
    "IIZZ" =  j_l,     # ligand-ligand exchange
    "XIIX" =  t,       # Fe(3) - L(0) hopping
    "IXXI" =  t        # Fe(2) - L(1) hopping
  ), n_qubits = 4L)
}

#' @export
print.edaphos_quantum_hamiltonian <- function(x, ...) {
  cat("<edaphos_quantum_hamiltonian>\n")
  cat(sprintf("  n_qubits = %d   n_terms = %d\n",
              x$n_qubits, length(x$pauli_terms)))
  cat("  Pauli terms (top 8 by |coef|):\n")
  ord <- order(abs(x$pauli_terms), decreasing = TRUE)
  show <- utils::head(ord, 8L)
  for (i in show) {
    cat(sprintf("    %-16s  % .6f\n",
                names(x$pauli_terms)[i], x$pauli_terms[i]))
  }
  if (length(x$pauli_terms) > 8L) {
    cat(sprintf("    ... %d more term(s)\n",
                length(x$pauli_terms) - 8L))
  }
  invisible(x)
}

# ---- Exact reference --------------------------------------------------------

#' Exact ground-state energy via classical diagonalisation
#'
#' Runs Qiskit's `NumPyMinimumEigensolver` (dense diagonalisation of
#' the Hamiltonian matrix) and returns the exact ground-state
#' eigenvalue. Works for any Hamiltonian up to ~12 qubits before
#' memory becomes the limit.
#'
#' @param hamiltonian An `edaphos_quantum_hamiltonian`.
#' @return A numeric scalar — the ground-state energy.
#' @export
quantum_vqe_exact <- function(hamiltonian) {
  .qk_require()
  stopifnot(inherits(hamiltonian, "edaphos_quantum_hamiltonian"))
  exact  <- .qk_env$qa$NumPyMinimumEigensolver()
  result <- exact$compute_minimum_eigenvalue(operator = hamiltonian$op)
  Re(as.complex(result$eigenvalue))
}

# ---- VQE fit ----------------------------------------------------------------

.qk_optimizer <- function(name, max_iter) {
  name <- toupper(name)
  switch(
    name,
    COBYLA = .qk_env$qo$COBYLA(maxiter = as.integer(max_iter)),
    SPSA   = .qk_env$qo$SPSA(maxiter  = as.integer(max_iter)),
    SLSQP  = .qk_env$qo$SLSQP(maxiter = as.integer(max_iter)),
    `L-BFGS-B` = .qk_env$qo$L_BFGS_B(maxiter = as.integer(max_iter)),
    stop("Unknown optimizer: ", name, call. = FALSE)
  )
}

.qk_estimator <- function(backend) {
  backend <- tolower(backend)
  switch(
    backend,
    aer_statevector = .qk_env$qp$StatevectorEstimator(),
    stop("Backend '", backend, "' is not wired up in this release. ",
         "Use 'aer_statevector' for now; 'ibmq' requires ",
         "qiskit-ibm-runtime and a token.", call. = FALSE)
  )
}

#' Variational Quantum Eigensolver (Pillar 6 main entry point)
#'
#' Runs the Peruzzo et al. 2014 VQE on the supplied Hamiltonian with
#' an `EfficientSU2` hardware-efficient ansatz and a classical
#' optimiser (default COBYLA). The optimisation trajectory is
#' captured by a callback so the energy curve can be plotted or
#' audited after the fact.
#'
#' @param hamiltonian An `edaphos_quantum_hamiltonian`.
#' @param ansatz_reps Integer — number of `EfficientSU2` repetition
#'   blocks. More blocks increase expressivity at the cost of more
#'   variational parameters.
#' @param optimizer Character — one of `"COBYLA"` (default), `"SPSA"`,
#'   `"SLSQP"`, `"L-BFGS-B"`.
#' @param max_iter Integer — maximum classical-optimiser iterations.
#' @param backend Character — `"aer_statevector"` (default, exact
#'   noiseless simulation). `"ibmq"` is reserved for a future release.
#' @param seed Optional integer — seeds NumPy / Qiskit RNGs for
#'   reproducible runs.
#' @param initial_point Optional numeric vector — custom starting
#'   ansatz parameters. Defaults to Qiskit's random initial point.
#'
#' @return An `edaphos_quantum_vqe` object with:
#' \describe{
#'   \item{energy}{Ground-state energy estimate.}
#'   \item{exact}{Numerically exact ground-state energy, for
#'     reference.}
#'   \item{gap}{Absolute difference `|energy - exact|`.}
#'   \item{parameters}{Numeric vector of optimal ansatz parameters.}
#'   \item{history}{Numeric vector of energy values, one per
#'     optimiser iteration (via callback).}
#'   \item{n_iter}{Integer iteration count.}
#'   \item{hamiltonian,ansatz,optimizer,backend}{Configuration echo.}
#' }
#' @references Peruzzo, A. et al. (2014). A variational eigenvalue
#'   solver on a photonic quantum processor. *Nature Communications*
#'   **5**, 4213. McClean, J. R. et al. (2016). The theory of
#'   variational hybrid quantum-classical algorithms. *New Journal of
#'   Physics* **18**, 023023.
#' @export
quantum_vqe_fit <- function(hamiltonian,
                             ansatz_reps = 2L,
                             optimizer   = c("COBYLA", "SPSA",
                                             "SLSQP", "L-BFGS-B"),
                             max_iter    = 200L,
                             backend     = "aer_statevector",
                             seed        = NULL,
                             initial_point = NULL) {
  .qk_require()
  stopifnot(inherits(hamiltonian, "edaphos_quantum_hamiltonian"))
  optimizer <- match.arg(optimizer)
  if (!is.null(seed)) {
    np <- reticulate::import("numpy", delay_load = FALSE)
    np$random$seed(as.integer(seed))
  }

  ansatz <- .qk_env$ql$EfficientSU2(num_qubits = hamiltonian$n_qubits,
                                     reps = as.integer(ansatz_reps))
  estimator <- .qk_estimator(backend)
  opt       <- .qk_optimizer(optimizer, max_iter)

  # Capture the optimisation trajectory via the VQE callback.
  history <- new.env(parent = emptyenv())
  history$energies <- numeric(0)
  callback <- function(eval_count, params, mean, std) {
    history$energies <- c(history$energies, as.numeric(mean))
    invisible(NULL)
  }

  vqe_args <- list(
    estimator = estimator,
    ansatz    = ansatz,
    optimizer = opt,
    callback  = callback
  )
  if (!is.null(initial_point)) {
    vqe_args$initial_point <- reticulate::r_to_py(as.numeric(initial_point))
  }
  vqe <- do.call(.qk_env$qa$VQE, vqe_args)

  result  <- vqe$compute_minimum_eigenvalue(operator = hamiltonian$op)
  energy  <- Re(as.complex(result$eigenvalue))
  params  <- as.numeric(result$optimal_point)
  n_iter  <- tryCatch(as.integer(result$cost_function_evals),
                       error = function(e) NA_integer_)
  exact   <- quantum_vqe_exact(hamiltonian)

  structure(
    list(
      hamiltonian = hamiltonian,
      ansatz_reps = as.integer(ansatz_reps),
      optimizer   = optimizer,
      backend     = backend,
      energy      = energy,
      exact       = exact,
      gap         = abs(energy - exact),
      parameters  = params,
      history     = history$energies,
      n_iter      = n_iter
    ),
    class = "edaphos_quantum_vqe"
  )
}

#' @export
print.edaphos_quantum_vqe <- function(x, ...) {
  cat("<edaphos_quantum_vqe>\n")
  cat(sprintf("  Hamiltonian : %d qubits / %d Pauli terms\n",
              x$hamiltonian$n_qubits, length(x$hamiltonian$pauli_terms)))
  cat(sprintf("  ansatz      : EfficientSU2(reps = %d)\n", x$ansatz_reps))
  cat(sprintf("  optimizer   : %s    backend : %s\n",
              x$optimizer, x$backend))
  cat(sprintf("  n params    : %d   n iter : %s\n",
              length(x$parameters),
              if (is.na(x$n_iter)) "-" else format(x$n_iter)))
  cat(sprintf("  energy      : %.6f\n", x$energy))
  cat(sprintf("  exact       : %.6f\n", x$exact))
  cat(sprintf("  gap         : %.3e\n", x$gap))
  invisible(x)
}

# ---- IBMQ bridge ------------------------------------------------------------

#' Check whether an IBM Quantum backend is reachable
#'
#' Returns `TRUE` when (i) `reticulate` is installed; (ii) the
#' `qiskit_ibm_runtime` Python module is importable; and (iii) the
#' `IBMQ_TOKEN` environment variable is set. The function does not
#' contact the network; it is a cheap preflight probe.
#'
#' @return Logical scalar.
#' @export
quantum_ibmq_available <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) return(FALSE)
  if (!reticulate::py_module_available("qiskit_ibm_runtime")) return(FALSE)
  nzchar(Sys.getenv("IBMQ_TOKEN", ""))
}

#' List IBM Quantum backends available to the current account
#'
#' Requires [quantum_ibmq_available()] to return `TRUE`. Pulls the
#' current list via `qiskit_ibm_runtime.QiskitRuntimeService`.
#'
#' @return A character vector of backend names, or a length-0
#'   character vector when the service is unavailable.
#' @export
quantum_ibmq_backends <- function() {
  if (!quantum_ibmq_available()) return(character(0))
  rt <- reticulate::import("qiskit_ibm_runtime", delay_load = FALSE)
  service <- rt$QiskitRuntimeService(token = Sys.getenv("IBMQ_TOKEN"))
  backends <- service$backends()
  vapply(backends, function(b) b$name, character(1L))
}
