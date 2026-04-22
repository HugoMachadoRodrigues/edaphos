# Pillar 6 VQE tests. Every live call is gated on Qiskit availability
# so the suite runs offline and remains CI-green on GitHub runners
# without the reticulate virtualenv.

skip_if_no_qiskit <- function() {
  skip_if_not_installed("reticulate")
  if (!reticulate::py_module_available("qiskit")) {
    skip("qiskit Python module not available")
  }
  if (!reticulate::py_module_available("qiskit_algorithms")) {
    skip("qiskit_algorithms Python module not available")
  }
}

test_that("quantum_hamiltonian rejects malformed Pauli strings", {
  skip_if_no_qiskit()
  expect_error(
    quantum_hamiltonian(c("IIZ" = 0.5), n_qubits = 2L),
    "Invalid Pauli"
  )
  expect_error(
    quantum_hamiltonian(c("IIa" = 0.5), n_qubits = 3L),
    "Invalid Pauli"
  )
})

test_that("quantum_hamiltonian builds a SparsePauliOp with the right dim", {
  skip_if_no_qiskit()
  ham <- quantum_hamiltonian(c("II" = -1.0, "XX" = 0.2, "ZZ" = -0.01))
  expect_s3_class(ham, "edaphos_quantum_hamiltonian")
  expect_equal(ham$n_qubits, 2L)
  expect_equal(length(ham$pauli_terms), 3L)
  expect_equal(ham$op$num_qubits, 2L)
})

test_that("quantum_hamiltonian_h2 reproduces the textbook H2 energy", {
  skip_if_no_qiskit()
  ham <- quantum_hamiltonian_h2()
  expect_equal(ham$n_qubits, 2L)
  # Published reduced H2 ground-state energy at 0.735 A is ~ -1.857 Ha
  e_ex <- quantum_vqe_exact(ham)
  expect_lt(abs(e_ex - (-1.857275)), 1e-4)
})

test_that("quantum_hamiltonian_ising_1d builds n-site chains", {
  skip_if_no_qiskit()
  ham <- quantum_hamiltonian_ising_1d(n_qubits = 3L, J = 1, h = 0.5)
  # Three ZZ edges (n-1 = 2) plus three X on-site terms.
  expect_equal(ham$n_qubits, 3L)
  expect_equal(length(ham$pauli_terms), 2L + 3L)
})

test_that("quantum_hamiltonian_organo_mineral builds a 4-qubit operator", {
  skip_if_no_qiskit()
  ham <- quantum_hamiltonian_organo_mineral()
  expect_equal(ham$n_qubits, 4L)
  expect_equal(length(ham$pauli_terms), 8L)
})

test_that("quantum_vqe_exact is a finite number", {
  skip_if_no_qiskit()
  ham <- quantum_hamiltonian_h2()
  e_ex <- quantum_vqe_exact(ham)
  expect_true(is.finite(e_ex))
  expect_type(e_ex, "double")
})

test_that("quantum_vqe_fit converges to the exact H2 ground state", {
  skip_if_no_qiskit()
  ham <- quantum_hamiltonian_h2()
  fit <- quantum_vqe_fit(ham, ansatz_reps = 2L, max_iter = 200L, seed = 1L)
  expect_s3_class(fit, "edaphos_quantum_vqe")
  # H2 reduced is 2-qubit: VQE + EfficientSU2(reps=2) routinely lands
  # within 1e-3 Hartree of the exact diagonalisation.
  expect_lt(fit$gap, 1e-3)
  # Energy history must be non-empty and monotonically non-worsening
  # on average.
  expect_gt(length(fit$history), 0L)
  expect_lt(mean(utils::tail(fit$history, 10L)),
            mean(utils::head(fit$history, 10L)))
})

test_that("print methods do not error", {
  skip_if_no_qiskit()
  ham <- quantum_hamiltonian_h2()
  expect_output(print(ham), "edaphos_quantum_hamiltonian")
  fit <- quantum_vqe_fit(ham, ansatz_reps = 1L, max_iter = 30L, seed = 1L)
  expect_output(print(fit), "edaphos_quantum_vqe")
})

test_that("quantum_ibmq_available is FALSE without IBMQ_TOKEN", {
  old <- Sys.getenv("IBMQ_TOKEN")
  Sys.setenv(IBMQ_TOKEN = "")
  on.exit(Sys.setenv(IBMQ_TOKEN = old), add = TRUE)
  expect_false(quantum_ibmq_available())
})
