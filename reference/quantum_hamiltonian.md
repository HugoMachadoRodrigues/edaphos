# Build a quantum Hamiltonian from Pauli-string coefficients

Constructs an `edaphos_quantum_hamiltonian` wrapping a
`qiskit.quantum_info.SparsePauliOp`. Pauli strings use the standard
`\{I, X, Y, Z\}` alphabet; the highest-index qubit is on the left
(Qiskit convention).

## Usage

``` r
quantum_hamiltonian(pauli_terms, n_qubits = NULL)
```

## Arguments

- pauli_terms:

  Named numeric vector or list mapping Pauli strings to their
  coefficients, e.g. `c("II" = -1.05, "ZZ" = -0.01, "XX" = 0.18)`.

- n_qubits:

  Integer override — defaults to the length of the first Pauli string.

## Value

An object of class `edaphos_quantum_hamiltonian` carrying the Python
`SparsePauliOp` handle (`$op`), the tidy `$pauli_terms`, and
`$n_qubits`.
