# Transverse-field Ising Hamiltonian on an n-qubit chain

\\H = -J \sum\_{i=1}^{n-1} Z_i Z\_{i+1} - h \sum\_{i=1}^{n} X_i\\.
Classic condensed-matter benchmark with a well-known ground state.

## Usage

``` r
quantum_hamiltonian_ising_1d(n_qubits, J = 1, h = 1)
```

## Arguments

- n_qubits:

  Integer number of sites / qubits (\>= 2).

- J:

  Nearest-neighbour coupling.

- h:

  Transverse field strength.

## Value

An `edaphos_quantum_hamiltonian`.
