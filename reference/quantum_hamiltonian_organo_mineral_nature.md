# Organo-mineral Hamiltonians derived from ab initio molecular models

Curated presets that build an `edaphos_quantum_hamiltonian` from a
realistic molecular geometry through
[`quantum_hamiltonian_from_pyscf()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_from_pyscf.md).
Three variants are shipped, of which the two closed-shell organics
build; each is chosen to expose a distinct piece of organo-mineral
chemistry at a qubit count accessible to present-day hardware:

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
  qubit Hamiltonian is 2 qubits / 9 Pauli terms — fast enough to run on
  any hardware and small enough for CI.

- `"methanediol"`:

  H\\\_2\\C(OH)\\\_2\\ in STO-3G with the core frozen and a `(2e, 2o)`
  active space. Models the **ortho-diol** motif that underpins
  catechol-type Fe(III) chelation in humic substances. 2 qubits / 5
  Pauli terms after tapering. Note that this active space is nearly
  closed shell: it recovers only 0.5 mHartree of correlation energy
  against 34.2 mHartree for `"formic_acid"`, so the two are not
  interchangeable as demonstrations even though they cost the same to
  run. See
  [`quantum_nature_total_energy()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_nature_total_energy.md).

- `"ferric_formate"`:

  Monodentate Fe(III)–OOCH complex in STO-3G, intended as the *minimum
  viable* representation of an organo-mineral coordination event at the
  clay–humus interface. **This variant does not currently build.** The
  shipped geometry is neutral and open-shell (49 electrons, `spin = 5`);
  after `FreezeCoreTransformer` it carries 25 active electrons, an odd
  number, and `ActiveSpaceTransformer` then rejects every reachable
  configuration: an even `num_active_electrons` leaves an odd inactive
  count (`'The number of inactive electrons must be even.'`) while an
  odd one fails the alpha/beta split
  (`'Incorrect Active-Space configuration.'`). Because
  `num_active_electrons` is coerced with
  [`as.integer()`](https://rdrr.io/r/base/integer.html) it cannot carry
  the `(alpha, beta)` tuple that qiskit-nature would need, so no
  override rescues it from R. Treat it as a known gap, not as a slow
  calculation.

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
