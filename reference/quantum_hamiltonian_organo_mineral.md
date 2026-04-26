# Toy organo-mineral Hamiltonian (4-qubit Fe + ligand coupling)

A deliberately minimalist representation of a clay-humus or iron- oxide
coordination complex, sized for classical simulation on a laptop and for
a meaningful walk-through of
[`quantum_vqe_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_fit.md)
in the Pillar 6 vignette. Four qubits are partitioned as two
metal-centre states (left pair) and two ligand states (right pair), with
on-site, same-sector exchange and cross-sector hopping / tunnelling
terms:

## Usage

``` r
quantum_hamiltonian_organo_mineral(
  eps_fe = 0.5,
  eps_l = 0.3,
  j_fe = 0.4,
  j_l = 0.2,
  t = 0.25
)
```

## Arguments

- eps_fe, eps_l:

  Numeric on-site energies for the Fe-like and ligand-like sub-sectors.

- j_fe, j_l:

  Numeric same-sector Z-Z exchange couplings.

- t:

  Numeric cross-sector X-X hopping amplitude.

## Value

An `edaphos_quantum_hamiltonian` with 4 qubits.

## Details

\$\$ H = -\\\varepsilon\_\mathrm{Fe}\\(Z_3 + Z_2) \\
-\\\varepsilon\_\mathrm{L}\\(Z_1 + Z_0) \\ +\\J\_\mathrm{Fe}\\Z_3 Z_2 \\
+\\J\_\mathrm{L}\\Z_1 Z_0 \\ +\\t\\(X_3 X_0 + X_2 X_1). \$\$

The default parameters \\(\varepsilon\_\mathrm{Fe},
\varepsilon\_\mathrm{L}, J\_\mathrm{Fe}, J\_\mathrm{L}, t) = (0.5, 0.3,
0.4, 0.2, 0.25)\\ give a non-trivial entangled ground state.
