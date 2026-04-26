# Exact ground-state energy via classical diagonalisation

Runs Qiskit's `NumPyMinimumEigensolver` (dense diagonalisation of the
Hamiltonian matrix) and returns the exact ground-state eigenvalue. Works
for any Hamiltonian up to ~12 qubits before memory becomes the limit.

## Usage

``` r
quantum_vqe_exact(hamiltonian)
```

## Arguments

- hamiltonian:

  An `edaphos_quantum_hamiltonian`.

## Value

A numeric scalar — the ground-state energy.
