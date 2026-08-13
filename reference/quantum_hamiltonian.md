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

## Examples

``` r
if (FALSE) { # \dontrun{
# Everything in Pillar 6 talks to a live Qiskit stack through
# reticulate; install it once with
#   reticulate::py_install(c("qiskit", "qiskit-aer",
#                            "qiskit-algorithms"), pip = TRUE)

# Two non-interacting spins with different Zeeman energies.
h <- quantum_hamiltonian(c("ZI" = 1, "IZ" = 2))
h

# Qubit order is the trap.  The LEFTMOST character is the HIGHEST
# qubit index, so the coefficient 2 sits on qubit 0, not qubit 1.
# The diagonal, in Qiskit's |q1 q0> basis order (00, 01, 10, 11),
# comes back as 3, -1, 1, -3: flipping qubit 0 costs 4 = 2 * 2,
# flipping qubit 1 only 2 = 2 * 1.
Re(diag(h$op$to_matrix()))

# `n_qubits` is inferred from the FIRST string alone, so a ragged
# set of terms surfaces as an invalid-Pauli error naming the
# second string, never as a length mismatch.
try(quantum_hamiltonian(c("ZZI" = 1, "ZZ" = 1)))

# The alphabet is {I, X, Y, Z} and it is case sensitive.
try(quantum_hamiltonian(c("zz" = 1)))

# An all-identity term is a pure energy offset: it shifts every
# eigenvalue and no variational circuit can lower it.
quantum_vqe_exact(quantum_hamiltonian(c("IIII" = -2.5)))   # -2.5

# Repeated Pauli strings are NOT rejected -- SparsePauliOp adds
# them up, so this is the single term ZI with coefficient 3 and a
# ground state at -3.  De-duplicate upstream if that is not what
# you meant; nothing downstream will warn you.
quantum_vqe_exact(quantum_hamiltonian(c("ZI" = 1, "ZI" = 2)))  # -3
} # }
```
