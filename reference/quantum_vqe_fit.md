# Variational Quantum Eigensolver (Pillar 6 main entry point)

Runs the Peruzzo et al. 2014 VQE on the supplied Hamiltonian with a
hardware-efficient `EfficientSU2` ansatz (Kandala et al. 2017) and a
classical optimiser (default COBYLA). The optimisation trajectory is
captured by a callback so the energy curve can be plotted or audited
after the fact.

## Usage

``` r
quantum_vqe_fit(
  hamiltonian,
  ansatz_reps = 2L,
  optimizer = c("COBYLA", "SPSA", "SLSQP", "L-BFGS-B"),
  max_iter = 200L,
  backend = c("aer_statevector", "aer_shots", "ibmq"),
  shots = NULL,
  mitigation = c("none", "m3", "zne"),
  ibmq_backend = NULL,
  seed = NULL,
  initial_point = NULL
)
```

## Arguments

- hamiltonian:

  An `edaphos_quantum_hamiltonian`.

- ansatz_reps:

  Integer — number of `EfficientSU2` repetition blocks. More blocks
  increase expressivity at the cost of more variational parameters.

- optimizer:

  Character — one of `"COBYLA"` (default), `"SPSA"`, `"SLSQP"`,
  `"L-BFGS-B"`. Shot-based and hardware runs strongly prefer `"SPSA"`
  because it is robust to stochastic cost-function evaluations (Spall
  1998).

- max_iter:

  Integer — maximum classical-optimiser iterations.

- backend:

  Character — one of `"aer_statevector"` (default, exact), `"aer_shots"`
  (shot-based simulation), `"ibmq"` (real IBM Quantum hardware). See
  Details.

- shots:

  Integer — number of circuit shots per energy evaluation. Ignored when
  `backend = "aer_statevector"`. Defaults to `4096` for `"aer_shots"`
  and `"ibmq"` when left `NULL`.

- mitigation:

  Character — one of `"none"` (default), `"m3"`, `"zne"`. Controls
  hardware error mitigation; see Details.

- ibmq_backend:

  Character — name of the target IBM Quantum backend (e.g.
  `"ibm_brisbane"`, `"ibm_sherbrooke"`) when `backend = "ibmq"`. If
  `NULL`, the least-busy operational backend available to the account is
  selected automatically.

- seed:

  Optional integer — seeds NumPy / Qiskit RNGs for reproducible runs.

- initial_point:

  Optional numeric vector — custom starting ansatz parameters. Defaults
  to Qiskit's random initial point.

## Value

An `edaphos_quantum_vqe` object with:

- energy:

  Ground-state energy estimate.

- exact:

  Numerically exact ground-state energy, for reference.

- gap:

  Absolute difference `|energy - exact|`.

- parameters:

  Numeric vector of optimal ansatz parameters.

- history:

  Numeric vector of energy values, one per optimiser iteration (via
  callback).

- n_iter:

  Integer iteration count.

- shots, mitigation:

  Echo of the execution configuration.

- hamiltonian,ansatz,optimizer,backend:

  Configuration echo.

## Details

Three execution back ends are supported as of **v0.9.0**:

- `"aer_statevector"` (default):

  Exact noiseless statevector simulation via
  `qiskit.primitives.StatevectorEstimator`. The ansatz is not
  transpiled. Deterministic; limited by memory to roughly 24 qubits.

- `"aer_shots"`:

  Shot-based simulation via `qiskit_aer.primitives.EstimatorV2`. Each
  energy evaluation is estimated from `shots` circuit executions and
  therefore carries a finite-sample noise of order `1/sqrt(shots)`. The
  ansatz is transpiled to the standard `\{id, rz, sx, x, cx, u\}` basis
  gate set so that the Aer primitive can dispatch it.

- `"ibmq"`:

  Real hardware via `qiskit_ibm_runtime.EstimatorV2` inside a Runtime
  `Session`. Requires the `qiskit-ibm-runtime` Python package and an
  `IBMQ_TOKEN` environment variable. Supports two mitigation strategies
  (Kim et al. 2023, see References):

  - `mitigation = "m3"` — Matrix-free Measurement Mitigation (TREX + M3
    readout correction), mapped to IBM runtime `resilience_level = 1`;

  - `mitigation = "zne"` — Zero-Noise Extrapolation over gate-folding
    noise scales, mapped to IBM runtime `resilience_level = 2`.

## References

Peruzzo, A. et al. (2014). A variational eigenvalue solver on a photonic
quantum processor. *Nature Communications* **5**, 4213.

Kandala, A. et al. (2017). Hardware-efficient variational quantum
eigensolver for small molecules and quantum magnets. *Nature* **549**,
242–246.

Kim, Y. et al. (2023). Evidence for the utility of quantum computing
before fault tolerance. *Nature* **618**, 500–505.

Spall, J. C. (1998). Implementation of the simultaneous perturbation
algorithm for stochastic optimisation. *IEEE Transactions on Aerospace
and Electronic Systems* **34**, 817–823.

## Examples

``` r
if (FALSE) { # \dontrun{
  ham <- quantum_hamiltonian_h2()

  # 1) Exact noiseless reference (fast).
  fit <- quantum_vqe_fit(ham, backend = "aer_statevector", seed = 1L)

  # 2) Shot-based simulation with SPSA (honest to finite sampling).
  fit_s <- quantum_vqe_fit(ham, backend = "aer_shots",
                            shots = 4096L, optimizer = "SPSA",
                            max_iter = 100L, seed = 1L)

  # 3) Real IBM Quantum hardware with M3 readout mitigation.
  if (quantum_ibmq_available()) {
    fit_q <- quantum_vqe_fit(ham, backend = "ibmq",
                              shots = 4096L,
                              mitigation = "m3",
                              ibmq_backend = "ibm_brisbane",
                              optimizer = "SPSA",
                              max_iter = 50L)
  }
} # }
```
