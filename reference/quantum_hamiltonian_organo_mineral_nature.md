# Organo-mineral Hamiltonians derived from ab initio molecular models

Curated presets that build an `edaphos_quantum_hamiltonian` from a
realistic molecular geometry through
[`quantum_hamiltonian_from_pyscf()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_from_pyscf.md).
Three variants are shipped, each chosen to expose a distinct piece of
organo-mineral chemistry at a qubit count that is accessible to
present-day hardware:

## Usage

``` r
quantum_hamiltonian_organo_mineral_nature(
  variant = c("formic_acid", "methanediol", "ferric_formate"),
  basis = "sto3g",
  num_active_electrons = NULL,
  num_active_orbitals = NULL,
  mapper = c("parity", "jordan_wigner", "bravyi_kitaev")
)
```

## Arguments

- variant:

  Character — `"formic_acid"` (default), `"methanediol"` or
  `"ferric_formate"`.

- basis:

  Character — PySCF basis set label. Default `"sto3g"` for speed;
  upgrade to `"631g"` for quantitative work.

- num_active_electrons, num_active_orbitals:

  Optional integer overrides for the active-space size. When left `NULL`
  the variant-specific default is used (`(2, 2)` for the closed-shell
  organics, `(4, 4)` for ferric formate).

- mapper:

  Character — fermion-to-qubit mapping; see
  [`quantum_hamiltonian_from_pyscf()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_from_pyscf.md).

## Value

An `edaphos_quantum_hamiltonian_nature` (which inherits from
`edaphos_quantum_hamiltonian`) carrying the qubit Hamiltonian plus the
nuclear-repulsion, frozen-core and reference-energy attributes needed to
reconstruct the total molecular energy.

## Details

- `"formic_acid"` (default):

  HCOOH in STO-3G with the chemical core frozen and a `(2e, 2o)` active
  space. Models the **carboxylate functional group** that is the
  dominant coordinating moiety of humic acids. After parity tapering the
  qubit Hamiltonian is 2 qubits / ~5 Pauli terms — fast enough to run on
  any hardware and small enough for CI.

- `"methanediol"`:

  H\\\_2\\C(OH)\\\_2\\ in STO-3G with the core frozen and a `(2e, 2o)`
  active space. Models the **ortho-diol** motif that underpins
  catechol-type Fe(III) chelation in humic substances. 2 qubits after
  tapering.

- `"ferric_formate"`:

  Monodentate Fe(III)–OOCH complex in STO-3G. Open-shell (S = 5/2),
  requires a `(4e, 4o)` active space around Fe 3d + carboxylate
  \\\pi^\*\\, and produces a 4-qubit Hamiltonian after parity tapering.
  This variant is the *minimum viable* representation of an
  organo-mineral coordination event at the clay–humus interface; because
  the SCF convergence is sensitive to the initial guess we recommend
  running it on `backend = "aer_shots"` or `"ibmq"` with `"SPSA"` and at
  least 100 iterations, and consulting `attr(ham, "reference_energy")`
  as a sanity check.

## References

Stevenson, F. J. (1994). *Humus Chemistry: Genesis, Composition,
Reactions*. Wiley. (Chapter on carboxylate and catechol-type chelation
of Fe(III) at mineral surfaces.)

## See also

[`quantum_hamiltonian_from_pyscf()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_from_pyscf.md),
[`quantum_hamiltonian_organo_mineral()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_organo_mineral.md)
(toy 4-qubit variant),
[`quantum_vqe_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_fit.md).

## Examples

``` r
if (FALSE) { # \dontrun{
  ham <- quantum_hamiltonian_organo_mineral_nature("formic_acid")
  attr(ham, "nuclear_repulsion_energy")
  quantum_vqe_fit(ham, seed = 1L)$energy +
    attr(ham, "nuclear_repulsion_energy")
} # }
```
