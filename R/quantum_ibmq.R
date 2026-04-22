# Pillar 6 -- IBM Quantum Runtime dispatch (shot-based + mitigation).
#
# This file is the single source of truth for every IBM Quantum
# hardware call made by `edaphos`. Three layers are exposed:
#
#   * quantum_ibmq_available() / quantum_ibmq_backends()
#       Preflight probes that do not contact the network until the
#       user explicitly asks for the backend list.
#
#   * quantum_ibmq_submit()
#       Low-level synchronous submission of a single
#       (circuit, observable, parameter-values) PUB to the IBM Quantum
#       Runtime EstimatorV2 primitive inside a managed `Session`.
#       Useful for users who assemble their own hybrid loops.
#
#   * .ibmq_estimator()
#       Internal factory that returns an EstimatorV2-compatible
#       handle for `.qk_estimator()` to plug into VQE. Picks the
#       resilience level from the user-facing `mitigation` argument
#       and transpiles the ansatz to the ISA gate set of the target
#       backend.
#
# All reticulate / Qiskit interop goes through the `.qk_env` cache
# established in R/quantum_vqe.R so imports are paid for once per R
# session.

# --- preflight + account helpers ---------------------------------------------

.ibmq_require <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("Install the `reticulate` package to use quantum_ibmq_*().",
         call. = FALSE)
  }
  if (!reticulate::py_module_available("qiskit_ibm_runtime")) {
    stop("`qiskit_ibm_runtime` Python module not found. Install once ",
         "via\n",
         "   reticulate::py_install('qiskit-ibm-runtime', pip = TRUE)\n",
         "then restart R.", call. = FALSE)
  }
  token <- Sys.getenv("IBMQ_TOKEN", "")
  if (!nzchar(token)) {
    stop("Set the IBMQ_TOKEN environment variable to your IBM Quantum ",
         "API token (https://quantum.ibm.com/account) before calling ",
         "any IBMQ dispatch function.", call. = FALSE)
  }
  if (is.null(.qk_env$qr)) {
    .qk_env$qr <- reticulate::import("qiskit_ibm_runtime",
                                      delay_load = FALSE)
  }
  invisible(TRUE)
}

.ibmq_service <- function() {
  .ibmq_require()
  .qk_env$qr$QiskitRuntimeService(token = Sys.getenv("IBMQ_TOKEN"))
}

#' Check whether an IBM Quantum backend is reachable
#'
#' Returns `TRUE` when (i) `reticulate` is installed; (ii) the
#' `qiskit_ibm_runtime` Python module is importable; and (iii) the
#' `IBMQ_TOKEN` environment variable is set. The function does not
#' contact the network; it is a cheap preflight probe safe to call
#' from examples, tests and CI.
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
#' @param operational_only Logical — if `TRUE` (default) restricts the
#'   result to backends whose `.status().operational` is `TRUE`.
#' @param simulator Logical — if `TRUE`, include simulator backends;
#'   if `FALSE` (default), restrict to real quantum processors.
#' @return A character vector of backend names, or a length-0 vector
#'   when the service is unavailable.
#' @export
quantum_ibmq_backends <- function(operational_only = TRUE,
                                    simulator = FALSE) {
  if (!quantum_ibmq_available()) return(character(0))
  service <- .ibmq_service()
  backends <- service$backends(simulator = simulator,
                                operational = operational_only)
  vapply(backends, function(b) b$name, character(1L))
}

#' Pick the least-busy operational IBM Quantum backend
#'
#' Thin wrapper around `QiskitRuntimeService$least_busy()`. Useful as
#' a sane default when the caller has no reason to target a specific
#' processor.
#'
#' @param simulator Logical — see [quantum_ibmq_backends()].
#' @param min_num_qubits Optional integer — require at least this many
#'   qubits on the returned backend.
#' @return The backend name as a single character string, or
#'   `NA_character_` when no backend matches.
#' @export
quantum_ibmq_least_busy <- function(simulator = FALSE,
                                      min_num_qubits = NULL) {
  if (!quantum_ibmq_available()) return(NA_character_)
  service <- .ibmq_service()
  kwargs <- list(simulator = simulator, operational = TRUE)
  if (!is.null(min_num_qubits)) {
    kwargs$min_num_qubits <- as.integer(min_num_qubits)
  }
  b <- tryCatch(do.call(service$least_busy, kwargs),
                 error = function(e) NULL)
  if (is.null(b)) NA_character_ else as.character(b$name)
}

# --- mitigation <-> resilience level mapping ---------------------------------
#
# The IBM Quantum Runtime EstimatorV2 encodes its error-mitigation
# policy in a single integer `resilience_level` ranging from 0 (no
# mitigation) to 3 (probabilistic error cancellation). We expose the
# three levels that are stable on current heavy-hex processors and
# documented in Kim et al. 2023 (Nature 618, 500-505):
#
#   mitigation = "none" -> 0 (raw expectation values; baseline).
#   mitigation = "m3"   -> 1 (TREX + M3 readout-matrix inversion;
#                             cheap, corrects measurement errors).
#   mitigation = "zne"  -> 2 (zero-noise extrapolation via gate
#                             folding; corrects coherent and
#                             incoherent two-qubit-gate errors).
#
# Probabilistic error cancellation (resilience_level = 3) is omitted
# because (a) it is roughly an order of magnitude slower than ZNE and
# (b) the IBM Runtime API is still iterating on its stability.
.ibmq_resilience_level <- function(mitigation) {
  switch(tolower(mitigation),
         none = 0L,
         m3   = 1L,
         zne  = 2L,
         stop("Unknown `mitigation` = '", mitigation,
              "'. Expected one of 'none', 'm3', 'zne'.",
              call. = FALSE))
}

# Build an IBM Quantum Runtime EstimatorV2 inside a fresh Session on
# the requested backend. Called from `.qk_estimator()` when the VQE
# front end is dispatched with `backend = "ibmq"`.
.ibmq_estimator <- function(shots = NULL,
                              mitigation = "none",
                              backend_name = NULL) {
  .ibmq_require()
  service <- .ibmq_service()
  if (is.null(backend_name) || !nzchar(backend_name)) {
    backend <- service$least_busy(simulator = FALSE,
                                    operational = TRUE)
  } else {
    backend <- service$backend(as.character(backend_name))
  }
  shots <- if (is.null(shots)) 4096L else as.integer(shots)
  resilience <- .ibmq_resilience_level(mitigation)
  opts <- reticulate::dict(
    default_shots = shots,
    resilience_level = resilience
  )
  .qk_env$qr$EstimatorV2(mode = backend, options = opts)
}

# --- low-level single-PUB submission ----------------------------------------

#' Submit a single expectation-value PUB to IBM Quantum hardware
#'
#' Synchronous, blocking submission of one
#' `(circuit, observable, parameter_values)` "primitive unified block"
#' (PUB) to the IBM Quantum Runtime `EstimatorV2`. The circuit is
#' transpiled to the Instruction-Set-Architecture of the target
#' backend before submission (preset pass manager, level 1). The
#' function blocks until the job finishes or `timeout_sec` elapses,
#' whichever comes first, and returns an `edaphos_quantum_ibmq_job`
#' object wrapping the expectation value, standard error, metadata
#' and the opaque IBM Quantum job id.
#'
#' This is the low-level escape hatch intended for users who want to
#' assemble their own hybrid loops outside of [quantum_vqe_fit()];
#' in particular, it is the primitive consumed by a future
#' `quantum_krr_fit(..., backend = "ibmq")` release for quantum-
#' kernel matrix elements.
#'
#' @param hamiltonian An `edaphos_quantum_hamiltonian`.
#' @param circuit A `qiskit.circuit.QuantumCircuit` Python handle or
#'   a character string that names one of the pre-built ansatzes:
#'   currently `"efficient_su2"` (the default). When a handle is
#'   passed it must already have `hamiltonian$n_qubits` qubits.
#' @param parameters Numeric vector of ansatz parameters.
#' @param backend_name Character — IBM Quantum backend name. When
#'   `NULL`, the least-busy operational backend is chosen.
#' @param shots Integer — number of circuit shots. Default `4096`.
#' @param mitigation Character — `"none"` (default), `"m3"`, `"zne"`.
#'   See the Details of [quantum_vqe_fit()].
#' @param ansatz_reps Integer — repetition count when `circuit` is a
#'   name shorthand. Default `2`.
#' @param timeout_sec Numeric — seconds to wait for the job to finish
#'   before raising an error. Default `600` (10 minutes).
#'
#' @return An `edaphos_quantum_ibmq_job` list with:
#' \describe{
#'   \item{job_id}{IBM Quantum job identifier (character).}
#'   \item{backend}{Name of the backend the job ran on.}
#'   \item{expectation}{Scalar expectation value
#'     \eqn{\langle \psi(\theta) \mid H \mid \psi(\theta) \rangle}.}
#'   \item{std_error}{Standard error of the expectation value, as
#'     reported by the EstimatorV2 primitive.}
#'   \item{shots, mitigation}{Execution configuration echo.}
#'   \item{metadata}{Raw metadata dictionary returned by the
#'     primitive (a named list).}
#' }
#' @export
quantum_ibmq_submit <- function(hamiltonian,
                                 circuit = "efficient_su2",
                                 parameters,
                                 backend_name = NULL,
                                 shots = 4096L,
                                 mitigation = c("none", "m3", "zne"),
                                 ansatz_reps = 2L,
                                 timeout_sec = 600) {
  .qk_require()
  .ibmq_require()
  stopifnot(inherits(hamiltonian, "edaphos_quantum_hamiltonian"))
  mitigation <- match.arg(mitigation)
  service <- .ibmq_service()
  backend <- if (is.null(backend_name) || !nzchar(backend_name)) {
    service$least_busy(simulator = FALSE, operational = TRUE)
  } else {
    service$backend(as.character(backend_name))
  }

  if (is.character(circuit) && length(circuit) == 1L) {
    if (!identical(circuit, "efficient_su2")) {
      stop("Only 'efficient_su2' is wired as a named ansatz. Pass a ",
           "Python QuantumCircuit handle for anything else.",
           call. = FALSE)
    }
    qc <- .qk_env$ql$efficient_su2(num_qubits = hamiltonian$n_qubits,
                                    reps = as.integer(ansatz_reps))
  } else {
    qc <- circuit
  }

  # Transpile to the ISA of the target backend using the preset pass
  # manager (Qiskit 2.x idiom). This gets us (i) routing to the
  # backend's coupling map, (ii) basis-gate translation, and (iii)
  # optimisation-level-1 pre-routing passes.
  pmg <- reticulate::import("qiskit.transpiler.preset_passmanagers",
                             delay_load = FALSE)
  pm  <- pmg$generate_preset_pass_manager(target = backend$target,
                                            optimization_level = 1L)
  qc_isa <- pm$run(qc)

  # The observable must be mapped to the qubits the circuit ended up
  # on after routing. apply_layout() does that re-indexing.
  obs_isa <- hamiltonian$op$apply_layout(qc_isa$layout)

  resilience <- .ibmq_resilience_level(mitigation)
  opts <- reticulate::dict(
    default_shots    = as.integer(shots),
    resilience_level = resilience
  )
  est <- .qk_env$qr$EstimatorV2(mode = backend, options = opts)

  pub <- reticulate::tuple(
    list(qc_isa, obs_isa, reticulate::r_to_py(as.numeric(parameters)))
  )
  job <- est$run(list(pub))
  job_id <- tryCatch(as.character(job$job_id()),
                      error = function(e) NA_character_)

  # Poll until the job is in a terminal state.
  t0 <- Sys.time()
  repeat {
    st <- tryCatch(as.character(job$status()),
                    error = function(e) "UNKNOWN")
    if (st %in% c("DONE", "CANCELLED", "ERROR")) break
    if (as.numeric(difftime(Sys.time(), t0, units = "secs")) >
        as.numeric(timeout_sec)) {
      stop("IBMQ job ", job_id, " did not finish within ",
           timeout_sec, " seconds (last status: ", st, ").",
           call. = FALSE)
    }
    Sys.sleep(2)
  }
  result <- job$result()
  pub_result <- result[[0L]]
  ev  <- as.numeric(pub_result$data$evs)
  stds <- tryCatch(as.numeric(pub_result$data$stds),
                    error = function(e) NA_real_)
  meta <- tryCatch(reticulate::py_to_r(pub_result$metadata),
                    error = function(e) list())

  structure(
    list(
      job_id       = job_id,
      backend      = as.character(backend$name),
      expectation  = ev[1L],
      std_error    = if (length(stds) >= 1L) stds[1L] else NA_real_,
      shots        = as.integer(shots),
      mitigation   = mitigation,
      metadata     = meta
    ),
    class = "edaphos_quantum_ibmq_job"
  )
}

#' @export
print.edaphos_quantum_ibmq_job <- function(x, ...) {
  cat("<edaphos_quantum_ibmq_job>\n")
  cat(sprintf("  backend     : %s\n", x$backend))
  cat(sprintf("  job_id      : %s\n", x$job_id))
  cat(sprintf("  expectation : %.6f  (std = %.3e)\n",
              x$expectation, x$std_error))
  cat(sprintf("  shots       : %d   mitigation : %s\n",
              as.integer(x$shots), x$mitigation))
  invisible(x)
}
