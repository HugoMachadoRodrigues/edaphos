# Total molecular energy from an active-space VQE result

Adds the three constant shifts carried by a
`edaphos_quantum_hamiltonian_nature` (nuclear repulsion + frozen core +
active-space projection) onto the VQE-estimated electronic energy of the
active space.

## Usage

``` r
quantum_nature_total_energy(fit)
```

## Arguments

- fit:

  A `edaphos_quantum_vqe` fit whose `hamiltonian` is a
  `edaphos_quantum_hamiltonian_nature`.

## Value

A numeric scalar — the total molecular energy in Hartree.
