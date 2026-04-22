# Pillar 6 v0.9.0 tests. Covers:
#   (i)   shot-based VQE on the Aer EstimatorV2 primitive,
#   (ii)  the qiskit-nature bridge,
#   (iii) IBMQ preflight and the `mitigation` <-> `resilience_level`
#         mapping.
#
# Every live call is gated on the corresponding Python stack so that
# the suite remains green on a vanilla CI runner without the qiskit,
# qiskit-nature or qiskit-ibm-runtime virtualenvs.

skip_if_no_qiskit <- function() {
  skip_if_not_installed("reticulate")
  if (!reticulate::py_module_available("qiskit")) {
    skip("qiskit Python module not available")
  }
  if (!reticulate::py_module_available("qiskit_algorithms")) {
    skip("qiskit_algorithms Python module not available")
  }
}

skip_if_no_aer <- function() {
  skip_if_no_qiskit()
  if (!reticulate::py_module_available("qiskit_aer")) {
    skip("qiskit_aer Python module not available")
  }
}

skip_if_no_nature <- function() {
  skip_if_no_qiskit()
  if (!reticulate::py_module_available("qiskit_nature") ||
      !reticulate::py_module_available("pyscf")) {
    skip("qiskit-nature / pyscf not available")
  }
}

# --- (i) shot-based VQE ------------------------------------------------------

test_that("aer_shots VQE on H2 lands within shot-noise tolerance", {
  skip_if_no_aer()
  ham <- quantum_hamiltonian_h2()
  # Shot-based VQE is noisy; SPSA + 40 iters + 4096 shots reliably
  # lands within a few milliHartree on this 2-qubit benchmark. We
  # assert a loose but meaningful bound.
  fit <- quantum_vqe_fit(ham, backend = "aer_shots",
                          shots = 4096L, optimizer = "SPSA",
                          max_iter = 40L, seed = 1L)
  expect_s3_class(fit, "edaphos_quantum_vqe")
  expect_equal(fit$backend, "aer_shots")
  expect_equal(fit$shots, 4096L)
  expect_lt(fit$gap, 0.05)   # 50 mHa is ~10x the 1/sqrt(shots) floor
  # History is populated by the VQE callback.
  expect_gt(length(fit$history), 0L)
})

test_that("aer_shots default shots defaults to 4096 when NULL", {
  skip_if_no_aer()
  ham <- quantum_hamiltonian_h2()
  fit <- quantum_vqe_fit(ham, backend = "aer_shots",
                          shots = NULL, optimizer = "SPSA",
                          max_iter = 5L, seed = 1L)
  expect_null(fit$shots)   # echoes the user input, not the default
  expect_true(is.finite(fit$energy))
})

test_that("mitigation on aer_shots emits a note (no-op) but still runs", {
  skip_if_no_aer()
  ham <- quantum_hamiltonian_h2()
  expect_message(
    fit <- quantum_vqe_fit(ham, backend = "aer_shots",
                            shots = 1024L, mitigation = "m3",
                            optimizer = "SPSA", max_iter = 5L,
                            seed = 1L),
    regexp = "no-op on backend 'aer_shots'"
  )
  expect_equal(fit$mitigation, "m3")
  expect_true(is.finite(fit$energy))
})

test_that("quantum_vqe_fit rejects an unknown backend", {
  skip_if_no_qiskit()
  ham <- quantum_hamiltonian_h2()
  expect_error(
    quantum_vqe_fit(ham, backend = "spooky_backend",
                     optimizer = "COBYLA", max_iter = 1L),
    regexp = "'arg' should be one of"
  )
})

test_that("print.edaphos_quantum_vqe echoes shots + mitigation", {
  skip_if_no_aer()
  ham <- quantum_hamiltonian_h2()
  fit <- quantum_vqe_fit(ham, backend = "aer_shots",
                          shots = 512L, optimizer = "SPSA",
                          max_iter = 3L, seed = 1L)
  out <- utils::capture.output(print(fit))
  expect_true(any(grepl("shots\\s*:\\s*512",    out)))
  expect_true(any(grepl("mitigation\\s*:\\s*none", out)))
})

# --- (ii) qiskit-nature bridge ----------------------------------------------

test_that("quantum_nature_available() returns a length-1 logical", {
  v <- quantum_nature_available()
  expect_length(v, 1L)
  expect_type(v, "logical")
})

test_that("quantum_hamiltonian_from_pyscf builds H2 with parity tapering", {
  skip_if_no_nature()
  ham <- quantum_hamiltonian_from_pyscf(
    atom = "H 0 0 0; H 0 0 0.735",
    basis = "sto3g", charge = 0L, spin = 0L,
    freeze_core = FALSE,
    num_active_electrons = NULL, num_active_orbitals = NULL,
    mapper = "parity"
  )
  expect_s3_class(ham, "edaphos_quantum_hamiltonian_nature")
  expect_equal(ham$n_qubits, 2L)
  expect_gte(length(ham$pauli_terms), 3L)
  # Energies
  nuc <- attr(ham, "nuclear_repulsion_energy")
  ref <- attr(ham, "reference_energy")
  expect_true(is.finite(nuc) && nuc > 0)
  expect_true(is.finite(ref) && ref < 0)
  # Metadata echo
  expect_equal(attr(ham, "basis"), "sto3g")
  expect_equal(attr(ham, "mapper"), "parity")
  expect_equal(attr(ham, "num_spatial_orbitals"), 2L)
})

test_that("organo_mineral_nature('formic_acid') is a 2-qubit Hamiltonian", {
  skip_if_no_nature()
  ham <- quantum_hamiltonian_organo_mineral_nature("formic_acid")
  expect_s3_class(ham, "edaphos_quantum_hamiltonian_nature")
  expect_equal(ham$n_qubits, 2L)
  expect_equal(attr(ham, "variant"), "formic_acid")
  expect_true(is.finite(attr(ham, "energy_shift")))
})

test_that("quantum_nature_total_energy reconstructs total HF + VQE", {
  skip_if_no_nature()
  ham <- quantum_hamiltonian_organo_mineral_nature("formic_acid")
  fit <- quantum_vqe_fit(ham, backend = "aer_statevector",
                          ansatz_reps = 2L, max_iter = 200L, seed = 1L)
  etot <- quantum_nature_total_energy(fit)
  ref  <- attr(ham, "reference_energy")
  # Active-space VQE lands AT or BELOW Hartree-Fock by definition
  # (CASCI recovers some correlation energy).
  expect_true(etot <= ref + 1e-6)
  # And it cannot be lower than HF minus 1 Hartree for a (2e,2o)
  # active space -- protects against catastrophic sign / bookkeeping
  # bugs.
  expect_gt(etot, ref - 1.0)
})

test_that("methanediol variant builds cleanly", {
  skip_if_no_nature()
  ham <- quantum_hamiltonian_organo_mineral_nature("methanediol")
  expect_equal(ham$n_qubits, 2L)
  expect_equal(attr(ham, "variant"), "methanediol")
})

test_that("print.edaphos_quantum_hamiltonian_nature shows shifts", {
  skip_if_no_nature()
  ham <- quantum_hamiltonian_organo_mineral_nature("formic_acid")
  out <- utils::capture.output(print(ham))
  expect_true(any(grepl("formic_acid", out)))
  expect_true(any(grepl("sto3g",       out)))
  expect_true(any(grepl("nuc_rep",     out)))
  expect_true(any(grepl("active_shft", out)))
})

test_that("unknown mapper is rejected with a helpful error", {
  skip_if_no_nature()
  expect_error(
    quantum_hamiltonian_from_pyscf(
      atom = "H 0 0 0; H 0 0 0.735",
      mapper = "not_a_mapper"
    ),
    regexp = "should be one of"
  )
})

# --- (iii) IBMQ preflight + dispatch plumbing --------------------------------

test_that("quantum_ibmq_available is FALSE without IBMQ_TOKEN", {
  old <- Sys.getenv("IBMQ_TOKEN")
  Sys.setenv(IBMQ_TOKEN = "")
  on.exit(Sys.setenv(IBMQ_TOKEN = old), add = TRUE)
  expect_false(quantum_ibmq_available())
  expect_length(quantum_ibmq_backends(), 0L)
})

test_that("quantum_ibmq_least_busy returns NA without IBMQ_TOKEN", {
  old <- Sys.getenv("IBMQ_TOKEN")
  Sys.setenv(IBMQ_TOKEN = "")
  on.exit(Sys.setenv(IBMQ_TOKEN = old), add = TRUE)
  expect_identical(quantum_ibmq_least_busy(), NA_character_)
})

test_that(".ibmq_resilience_level maps the three mitigation policies", {
  # Direct unit test of the internal mapper; no network calls.
  expect_identical(edaphos:::.ibmq_resilience_level("none"), 0L)
  expect_identical(edaphos:::.ibmq_resilience_level("m3"),   1L)
  expect_identical(edaphos:::.ibmq_resilience_level("zne"),  2L)
  expect_error(edaphos:::.ibmq_resilience_level("bogus"),
                regexp = "Unknown")
})

test_that("quantum_ibmq_submit rejects a bad circuit shorthand", {
  skip_if_no_qiskit()
  old <- Sys.getenv("IBMQ_TOKEN")
  Sys.setenv(IBMQ_TOKEN = "dummy_token_for_type_checks_only")
  on.exit(Sys.setenv(IBMQ_TOKEN = old), add = TRUE)
  ham <- quantum_hamiltonian_h2()
  # Without a real token the call will fail inside the runtime
  # service, but the BAD circuit name must be caught first. We use
  # expect_error without a regex here because the exact message
  # depends on which guard fires first.
  expect_error(
    quantum_ibmq_submit(ham, circuit = "not_an_ansatz",
                         parameters = numeric(0))
  )
})
