# Submit a single expectation-value PUB to IBM Quantum hardware

Synchronous, blocking submission of one
`(circuit, observable, parameter_values)` "primitive unified block"
(PUB) to the IBM Quantum Runtime `EstimatorV2`. The circuit is
transpiled to the Instruction-Set-Architecture of the target backend
before submission (preset pass manager, level 1). The function blocks
until the job finishes or `timeout_sec` elapses, whichever comes first,
and returns an `edaphos_quantum_ibmq_job` object wrapping the
expectation value, standard error, metadata and the opaque IBM Quantum
job id.

## Usage

``` r
quantum_ibmq_submit(
  hamiltonian,
  circuit = "efficient_su2",
  parameters,
  backend_name = NULL,
  shots = 4096L,
  mitigation = c("none", "m3", "zne"),
  ansatz_reps = 2L,
  timeout_sec = 600
)
```

## Arguments

- hamiltonian:

  An `edaphos_quantum_hamiltonian`.

- circuit:

  A `qiskit.circuit.QuantumCircuit` Python handle or a character string
  that names one of the pre-built ansatzes: currently `"efficient_su2"`
  (the default). When a handle is passed it must already have
  `hamiltonian$n_qubits` qubits.

- parameters:

  Numeric vector of ansatz parameters.

- backend_name:

  Character — IBM Quantum backend name. When `NULL`, the least-busy
  operational backend is chosen.

- shots:

  Integer — number of circuit shots. Default `4096`.

- mitigation:

  Character — `"none"` (default), `"m3"`, `"zne"`. See the Details of
  [`quantum_vqe_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_fit.md).

- ansatz_reps:

  Integer — repetition count when `circuit` is a name shorthand. Default
  `2`.

- timeout_sec:

  Numeric — seconds to wait for the job to finish before raising an
  error. Default `600` (10 minutes).

## Value

An `edaphos_quantum_ibmq_job` list with:

- job_id:

  IBM Quantum job identifier (character).

- backend:

  Name of the backend the job ran on.

- expectation:

  Scalar expectation value \\\langle \psi(\theta) \mid H \mid
  \psi(\theta) \rangle\\.

- std_error:

  Standard error of the expectation value, as reported by the
  EstimatorV2 primitive.

- shots, mitigation:

  Execution configuration echo.

- metadata:

  Raw metadata dictionary returned by the primitive (a named list).

## Details

This is the low-level escape hatch intended for users who want to
assemble their own hybrid loops outside of
[`quantum_vqe_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_fit.md);
in particular, it is the primitive consumed by a future
`quantum_krr_fit(..., backend = "ibmq")` release for quantum- kernel
matrix elements.
