# Pillar 6 -- Variational Quantum Eigensolver (VQE) bridge.
#
# Reticulate + Qiskit implementation of the Peruzzo et al. 2014 VQE
# algorithm for the ground-state energy of a user-supplied Hamiltonian.
# Four Hamiltonian builders ship alongside the public
# quantum_hamiltonian() constructor: the canonical textbook H2
# benchmark, the 1-D transverse-field Ising chain, the toy 4-qubit
# organo-mineral cluster, and -- since v0.9.0 -- the qiskit-nature-
# backed molecular Hamiltonian derived from an ab initio PySCF run
# (see R/quantum_nature.R) so that realistic humic-proxy and
# iron-coordination fragments can be dispatched from R.
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
#   * "aer_shots"       -- shot-based simulation with the Aer
#                          EstimatorV2 primitive (finite-sample noise,
#                          optional depolarising / readout noise
#                          model). Ansatz is transpiled to a standard
#                          basis gate set.
#   * "ibmq"            -- real hardware via the IBM Quantum Runtime
#                          EstimatorV2 primitive (see
#                          R/quantum_ibmq.R). Requires qiskit-ibm-
#                          runtime and an IBMQ_TOKEN environment
#                          variable; supports M3 and ZNE mitigation
#                          through the `mitigation` argument.

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
    .qk_env$qk <- reticulate::import("qiskit",
                                      delay_load = FALSE)
    .qk_env$qa <- reticulate::import("qiskit_algorithms",
                                      delay_load = FALSE)
    .qk_env$qo <- reticulate::import("qiskit_algorithms.optimizers",
                                      delay_load = FALSE)
  }
  invisible(TRUE)
}

# Optional: Aer primitives. Imported lazily on demand because shot-
# based VQE only needs them when `backend = "aer_shots"`.
.qk_require_aer <- function() {
  .qk_require()
  if (!reticulate::py_module_available("qiskit_aer")) {
    stop("`qiskit_aer` Python module not found. Install once via\n",
         "   reticulate::py_install('qiskit-aer', pip = TRUE)\n",
         "then restart R.", call. = FALSE)
  }
  if (is.null(.qk_env$ae)) {
    .qk_env$ae <- reticulate::import("qiskit_aer.primitives",
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

# Build the Qiskit EstimatorV2-compatible primitive that VQE will
# call to evaluate <ansatz(theta) | H | ansatz(theta)> at each
# optimiser step.
#
# `shots`      Integer -- number of circuit shots to request when the
#              backend is shot-based. Converted to Qiskit's
#              `default_precision = 1 / sqrt(shots)` convention. Ignored
#              for the analytic statevector backend.
# `mitigation` One of "none", "m3" (readout mitigation), "zne" (zero-
#              noise extrapolation). Maps to `resilience_level`
#              {0, 1, 2} of the IBM runtime EstimatorV2. Silently a
#              no-op on "aer_statevector"; emits a note on
#              "aer_shots" because qiskit-aer's primitive does not
#              apply hardware-oriented mitigation.
# `ibmq_backend` Character -- name of the target IBM Quantum backend.
#              Consulted only when `backend = "ibmq"`.
.qk_estimator <- function(backend, shots = NULL,
                            mitigation = "none",
                            ibmq_backend = NULL) {
  backend <- tolower(backend)
  if (backend == "aer_statevector") {
    return(.qk_env$qp$StatevectorEstimator())
  }
  if (backend == "aer_shots") {
    .qk_require_aer()
    shots <- if (is.null(shots)) 4096L else as.integer(shots)
    precision <- 1 / sqrt(as.numeric(shots))
    opts <- reticulate::dict(default_precision = precision)
    if (!identical(mitigation, "none")) {
      message("note: `mitigation` is a no-op on backend 'aer_shots' ",
              "(qiskit-aer's primitive has no hardware mitigation). ",
              "Use backend = 'ibmq' to activate M3 / ZNE.")
    }
    return(.qk_env$ae$EstimatorV2(options = opts))
  }
  if (backend == "ibmq") {
    # Delegated to quantum_ibmq.R so that every IBM Quantum Runtime
    # call lives in one place.
    return(.ibmq_estimator(shots = shots,
                            mitigation = mitigation,
                            backend_name = ibmq_backend))
  }
  stop("Unknown backend '", backend,
       "'. Expected one of 'aer_statevector', 'aer_shots', 'ibmq'.",
       call. = FALSE)
}

# Standard basis gate set for transpiling the ansatz. IBM's heavy-hex
# processors speak (cx, x, rz, sx, id, u); Aer accepts the same.
.qk_default_basis_gates <- c("id", "rz", "sx", "x", "cx", "u")

# Transpile a QuantumCircuit to `basis_gates` preserving parameter
# bindings so VQE can still iterate over theta. `backend` is only
# needed when the caller wants backend-aware optimisation; for the
# analytic statevector path we skip transpilation entirely.
.qk_transpile_ansatz <- function(ansatz, basis_gates = .qk_default_basis_gates,
                                   optimization_level = 1L,
                                   backend = NULL) {
  args <- list(ansatz, basis_gates = basis_gates,
               optimization_level = as.integer(optimization_level))
  if (!is.null(backend)) args$backend <- backend
  do.call(.qk_env$qk$transpile, args)
}

#' Variational Quantum Eigensolver (Pillar 6 main entry point)
#'
#' Runs the Peruzzo et al. 2014 VQE on the supplied Hamiltonian with
#' a hardware-efficient `EfficientSU2` ansatz (Kandala et al. 2017) and
#' a classical optimiser (default COBYLA). The optimisation trajectory
#' is captured by a callback so the energy curve can be plotted or
#' audited after the fact.
#'
#' Three execution back ends are supported as of **v0.9.0**:
#'
#' \describe{
#'   \item{`"aer_statevector"` (default)}{Exact noiseless statevector
#'     simulation via `qiskit.primitives.StatevectorEstimator`. The
#'     ansatz is not transpiled. Deterministic; limited by memory to
#'     roughly 24 qubits.}
#'   \item{`"aer_shots"`}{Shot-based simulation via
#'     `qiskit_aer.primitives.EstimatorV2`. Each energy evaluation is
#'     estimated from `shots` circuit executions and therefore carries
#'     a finite-sample noise of order `1/sqrt(shots)`. The ansatz is
#'     transpiled to the standard `\{id, rz, sx, x, cx, u\}` basis
#'     gate set so that the Aer primitive can dispatch it.}
#'   \item{`"ibmq"`}{Real hardware via `qiskit_ibm_runtime.EstimatorV2`
#'     inside a Runtime `Session`. Requires the `qiskit-ibm-runtime`
#'     Python package and an `IBMQ_TOKEN` environment variable. Supports
#'     two mitigation strategies (Kim et al. 2023, see References):
#'     \itemize{
#'       \item `mitigation = "m3"` — Matrix-free Measurement
#'         Mitigation (TREX + M3 readout correction), mapped to
#'         IBM runtime `resilience_level = 1`;
#'       \item `mitigation = "zne"` — Zero-Noise Extrapolation over
#'         gate-folding noise scales, mapped to IBM runtime
#'         `resilience_level = 2`.
#'     }
#'   }
#' }
#'
#' @param hamiltonian An `edaphos_quantum_hamiltonian`.
#' @param ansatz_reps Integer — number of `EfficientSU2` repetition
#'   blocks. More blocks increase expressivity at the cost of more
#'   variational parameters.
#' @param optimizer Character — one of `"COBYLA"` (default), `"SPSA"`,
#'   `"SLSQP"`, `"L-BFGS-B"`. Shot-based and hardware runs strongly
#'   prefer `"SPSA"` because it is robust to stochastic cost-function
#'   evaluations (Spall 1998).
#' @param max_iter Integer — maximum classical-optimiser iterations.
#' @param backend Character — one of `"aer_statevector"` (default,
#'   exact), `"aer_shots"` (shot-based simulation), `"ibmq"` (real
#'   IBM Quantum hardware). See Details.
#' @param shots Integer — number of circuit shots per energy
#'   evaluation. Ignored when `backend = "aer_statevector"`. Defaults
#'   to `4096` for `"aer_shots"` and `"ibmq"` when left `NULL`.
#' @param mitigation Character — one of `"none"` (default), `"m3"`,
#'   `"zne"`. Controls hardware error mitigation; see Details.
#' @param ibmq_backend Character — name of the target IBM Quantum
#'   backend (e.g. `"ibm_brisbane"`, `"ibm_sherbrooke"`) when
#'   `backend = "ibmq"`. If `NULL`, the least-busy operational
#'   backend available to the account is selected automatically.
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
#'   \item{shots, mitigation}{Echo of the execution configuration.}
#'   \item{hamiltonian,ansatz,optimizer,backend}{Configuration echo.}
#' }
#' @references
#' Peruzzo, A. et al. (2014). A variational eigenvalue solver on a
#' photonic quantum processor. *Nature Communications* **5**, 4213.
#'
#' Kandala, A. et al. (2017). Hardware-efficient variational quantum
#' eigensolver for small molecules and quantum magnets. *Nature*
#' **549**, 242–246.
#'
#' Kim, Y. et al. (2023). Evidence for the utility of quantum
#' computing before fault tolerance. *Nature* **618**, 500–505.
#'
#' Spall, J. C. (1998). Implementation of the simultaneous
#' perturbation algorithm for stochastic optimisation. *IEEE
#' Transactions on Aerospace and Electronic Systems* **34**, 817–823.
#'
#' @examples
#' \dontrun{
#'   ham <- quantum_hamiltonian_h2()
#'
#'   # 1) Exact noiseless reference (fast).
#'   fit <- quantum_vqe_fit(ham, backend = "aer_statevector", seed = 1L)
#'
#'   # 2) Shot-based simulation with SPSA (honest to finite sampling).
#'   fit_s <- quantum_vqe_fit(ham, backend = "aer_shots",
#'                             shots = 4096L, optimizer = "SPSA",
#'                             max_iter = 100L, seed = 1L)
#'
#'   # 3) Real IBM Quantum hardware with M3 readout mitigation.
#'   if (quantum_ibmq_available()) {
#'     fit_q <- quantum_vqe_fit(ham, backend = "ibmq",
#'                               shots = 4096L,
#'                               mitigation = "m3",
#'                               ibmq_backend = "ibm_brisbane",
#'                               optimizer = "SPSA",
#'                               max_iter = 50L)
#'   }
#' }
#' @export
quantum_vqe_fit <- function(hamiltonian,
                             ansatz_reps = 2L,
                             optimizer   = c("COBYLA", "SPSA",
                                             "SLSQP", "L-BFGS-B"),
                             max_iter    = 200L,
                             backend     = c("aer_statevector",
                                             "aer_shots",
                                             "ibmq"),
                             shots       = NULL,
                             mitigation  = c("none", "m3", "zne"),
                             ibmq_backend = NULL,
                             seed        = NULL,
                             initial_point = NULL) {
  .qk_require()
  stopifnot(inherits(hamiltonian, "edaphos_quantum_hamiltonian"))
  optimizer  <- match.arg(optimizer)
  backend    <- match.arg(backend)
  mitigation <- match.arg(mitigation)
  if (!is.null(seed)) {
    np <- reticulate::import("numpy", delay_load = FALSE)
    np$random$seed(as.integer(seed))
  }

  # Hardware-efficient ansatz. We use the function form introduced in
  # Qiskit 2.1 (the class form `EfficientSU2` was deprecated).
  ansatz <- .qk_env$ql$efficient_su2(num_qubits = hamiltonian$n_qubits,
                                      reps = as.integer(ansatz_reps))

  # Non-statevector back ends need a transpiled circuit that speaks
  # the basis gate set of the target simulator / hardware.
  if (backend != "aer_statevector") {
    ansatz <- .qk_transpile_ansatz(ansatz)
  }

  estimator <- .qk_estimator(backend,
                              shots        = shots,
                              mitigation   = mitigation,
                              ibmq_backend = ibmq_backend)
  opt <- .qk_optimizer(optimizer, max_iter)

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
      hamiltonian  = hamiltonian,
      ansatz_reps  = as.integer(ansatz_reps),
      optimizer    = optimizer,
      backend      = backend,
      shots        = shots,
      mitigation   = mitigation,
      ibmq_backend = ibmq_backend,
      energy       = energy,
      exact        = exact,
      gap          = abs(energy - exact),
      parameters   = params,
      history      = history$energies,
      n_iter       = n_iter
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
  shot_desc <- if (is.null(x$shots)) "-" else format(as.integer(x$shots))
  mit_desc  <- x$mitigation %||% "none"
  cat(sprintf("  shots       : %s    mitigation : %s\n",
              shot_desc, mit_desc))
  if (!is.null(x$ibmq_backend) && nzchar(x$ibmq_backend)) {
    cat(sprintf("  ibmq backend: %s\n", x$ibmq_backend))
  }
  cat(sprintf("  n params    : %d   n iter : %s\n",
              length(x$parameters),
              if (is.na(x$n_iter)) "-" else format(x$n_iter)))
  cat(sprintf("  energy      : %.6f\n", x$energy))
  cat(sprintf("  exact       : %.6f\n", x$exact))
  cat(sprintf("  gap         : %.3e\n", x$gap))
  invisible(x)
}
