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
#' @examples
#' \dontrun{
#'   # The gate that every other IBMQ entry point consults first.
#'   quantum_ibmq_available()
#'
#'   # It is a three-part check and the third part is only
#'   # nzchar(Sys.getenv("IBMQ_TOKEN")). Any non-empty string passes,
#'   # so TRUE means "a token is present", never "the token
#'   # authenticates": junk credentials return TRUE here and then
#'   # fail at the first network call in quantum_ibmq_backends().
#'   old <- Sys.getenv("IBMQ_TOKEN", "")
#'   Sys.setenv(IBMQ_TOKEN = "not-a-real-token")
#'   quantum_ibmq_available()                       # TRUE
#'   if (nzchar(old)) Sys.setenv(IBMQ_TOKEN = old) else
#'     Sys.unsetenv("IBMQ_TOKEN")
#'
#'   # When it is FALSE, decompose it. The three preconditions fail
#'   # for unrelated reasons and only the third is fixed by editing
#'   # ~/.Renviron.
#'   c(reticulate = requireNamespace("reticulate", quietly = TRUE),
#'     runtime    = reticulate::py_module_available("qiskit_ibm_runtime"),
#'     token      = nzchar(Sys.getenv("IBMQ_TOKEN", "")))
#'
#'   # The token is read from the environment and nowhere else, so
#'   # keep it out of scripts: put IBMQ_TOKEN=<key from
#'   # https://quantum.ibm.com/account> in ~/.Renviron and restart R.
#' }
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
#' @examples
#' \dontrun{
#'   # Step 2 of the discovery path: preflight, list, then pick.
#'   stopifnot(quantum_ibmq_available())
#'   qpus <- quantum_ibmq_backends()
#'   qpus
#'
#'   # TRAP: an unavailable service is reported as character(0), not
#'   # as an error, so a length-0 result is indistinguishable from
#'   # "this account has no operational processor". The preflight
#'   # above is the only thing that tells the two apart -- without it
#'   # a missing IBMQ_TOKEN looks exactly like an empty fleet.
#'   length(quantum_ibmq_backends())
#'
#'   # The difference between the two calls is the calibration queue:
#'   # `operational_only = FALSE` also lists processors paused for
#'   # maintenance. Read it before blaming a stalled job on your
#'   # circuit.
#'   setdiff(quantum_ibmq_backends(operational_only = FALSE), qpus)
#'
#'   # `simulator = FALSE` is the default, i.e. real processors only.
#'   # Flip it to see whatever simulated backends the account still
#'   # exposes; IBM has been retiring them, so an empty answer here is
#'   # a normal outcome rather than a misconfiguration.
#'   quantum_ibmq_backends(simulator = TRUE)
#'
#'   # Feed a name straight into the dispatch layer. Pinning it is
#'   # what makes two runs comparable -- see quantum_ibmq_least_busy()
#'   # for why leaving `ibmq_backend = NULL` does not.
#'   quantum_vqe_fit(quantum_hamiltonian_h2(), backend = "ibmq",
#'                    ibmq_backend = qpus[1L],
#'                    optimizer = "SPSA", max_iter = 50L)
#' }
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
#' @examples
#' \dontrun{
#'   # Step 3 of the discovery path, for when you have no reason to
#'   # prefer a particular processor.
#'   name <- quantum_ibmq_least_busy()
#'   name %in% quantum_ibmq_backends()        # TRUE: it is one of them
#'
#'   # `min_num_qubits` filters the DEVICE, and says nothing about the
#'   # size of your problem. The 2-qubit preset from
#'   # quantum_hamiltonian_organo_mineral_nature() is routed onto the
#'   # full coupling map before submission, so the circuit that
#'   # actually leaves R is as wide as the processor -- 127 qubits on
#'   # an Eagle device. Width here is a capacity filter, not a limit.
#'   quantum_ibmq_least_busy(min_num_qubits = 127L)
#'
#'   # TRAP: NA_character_ is the only failure signal and it covers
#'   # three unrelated causes -- no token (returns before any network
#'   # call), no backend matching the filter, and any API error (the
#'   # service call is wrapped in tryCatch). Split them by hand:
#'   if (is.na(quantum_ibmq_least_busy(min_num_qubits = 1000L))) {
#'     if (!quantum_ibmq_available()) {
#'       message("no IBMQ_TOKEN in this session")
#'     } else {
#'       message("token present; no backend that wide, or API error")
#'     }
#'   }
#'
#'   # "Least busy" is a queue-depth decision, not a fidelity one, and
#'   # it can return a different processor minutes apart. Resolve it
#'   # once and pin the name when two runs have to be comparable:
#'   pinned <- quantum_ibmq_least_busy(min_num_qubits = 127L)
#'   quantum_ibmq_submit(quantum_hamiltonian_h2(),
#'                        parameters = rep(0.1, 12),
#'                        backend_name = pinned, mitigation = "m3")
#' }
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
#' @examples
#' \dontrun{
#'   ham <- quantum_hamiltonian_h2()          # 2 qubits, 5 Pauli terms
#'
#'   # `parameters` must match the ansatz length exactly: there is no
#'   # recycling, and nothing on the R side checks it. EfficientSU2
#'   # carries n_qubits * 2 * (reps + 1) angles, so 2 * 2 * 3 = 12 at
#'   # the default `ansatz_reps = 2`. Compute it, do not guess it.
#'   theta <- rep(0.1, 12)
#'
#'   job <- quantum_ibmq_submit(ham, parameters = theta,
#'                               shots = 4096L, mitigation = "m3")
#'   job
#'
#'   # One PUB is ONE expectation value at ONE parameter point -- this
#'   # is not an optimisation. The noiseless value at this theta is
#'   # -1.029329 while the ground state is -1.857275, so theta = 0.1
#'   # sits 0.83 Hartree above the minimum. A hardware number near
#'   # -1.03 therefore means the device worked, NOT that the chemistry
#'   # converged; quantum_vqe_fit(backend = "ibmq") does the latter.
#'   ref <- quantum_vqe_fit(ham, backend = "aer_statevector",
#'                           initial_point = theta)$history[1L]
#'   c(hardware = job$expectation, noiseless = ref,
#'     ground_state = quantum_vqe_exact(ham))
#'
#'   # `std_error` is shot noise ONLY -- the EstimatorV2 standard
#'   # error, of order 1/sqrt(shots) (0.0156 at 4096 shots).
#'   # Quadrupling `shots` halves it and does nothing whatsoever to
#'   # the coherent gate error, which is the bias `mitigation`
#'   # attacks. A tight std_error next to an untreated bias is the
#'   # classic way to over-trust a hardware run.
#'   c(std_error = job$std_error, shot_floor = 1 / sqrt(job$shots))
#'
#'   # So compare mitigation levels rather than trusting one run, and
#'   # pin `backend_name` while doing it: the default picks the
#'   # least-busy device afresh each call, which would confound the
#'   # comparison with a change of processor. Two queue slots.
#'   raw <- quantum_ibmq_submit(ham, parameters = theta, shots = 4096L,
#'                               backend_name = job$backend,
#'                               mitigation = "none")
#'   c(none = raw$expectation, m3 = job$expectation, noiseless = ref)
#'
#'   # `mitigation` is match.arg()'d here, so it is case sensitive
#'   # even though the internal level map is not: "zne" works, "ZNE"
#'   # errors.
#'
#'   # Supplying your own circuit ignores `ansatz_reps` and is
#'   # unchecked: a handle whose width differs from ham$n_qubits gets
#'   # past the transpiler and dies later inside apply_layout() with
#'   # "Number of qargs does not match (3 != 2)". Match the width to
#'   # hamiltonian$n_qubits yourself.
#'   names(job$metadata)                      # primitive's own report
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
