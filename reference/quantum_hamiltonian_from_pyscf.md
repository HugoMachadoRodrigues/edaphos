# Build a quantum Hamiltonian from a molecular geometry

End-to-end ab initio pipeline:

1.  A restricted Hartree-Fock reference is computed by `PySCFDriver` in
    the requested atomic-orbital basis (STO-3G by default — minimal,
    illustrative, and small enough for laptop-scale VQE).

2.  Optionally, the chemical core orbitals are frozen out by
    `FreezeCoreTransformer` — a cheap and orbital-space-neutral
    reduction that typically halves the qubit count for first-row
    organics.

3.  The frontier orbitals are projected to an
    `(num_active_electrons, num_active_orbitals)` active space via
    `ActiveSpaceTransformer`, keeping the chemistry local to the
    coordination event the user cares about (e.g. Fe-O-C charge transfer
    in an organo-mineral complex).

4.  The resulting second-quantised Hamiltonian is mapped to qubits by
    the chosen fermion-to-qubit transformation; by default the
    `ParityMapper` is used with known particle numbers, which taper off
    two qubits by Z2 symmetry reduction.

## Usage

``` r
quantum_hamiltonian_from_pyscf(
  atom,
  basis = "sto3g",
  charge = 0L,
  spin = 0L,
  freeze_core = TRUE,
  num_active_electrons = NULL,
  num_active_orbitals = NULL,
  mapper = c("parity", "jordan_wigner", "bravyi_kitaev")
)
```

## Arguments

- atom:

  Character — the PySCF atom specification, one atom per
  semicolon-separated block, e.g. `"H 0 0 0; H 0 0 0.735"` (H2 at 0.735
  Angstroms) or
  `"C 0 0 0; O 1.21 0 0; O -0.63 1.08 0; H -0.3 -0.99 0; H -1.56 0.85 0"`
  (formic acid).

- basis:

  Character — the atomic-orbital basis set. Default `"sto3g"`. Use
  `"631g"`, `"ccpvdz"`, or larger for chemistry- grade accuracy at the
  cost of more qubits.

- charge:

  Integer — molecular charge. Default `0`.

- spin:

  Integer — `2S`, i.e. number of unpaired electrons. Default `0` (closed
  shell).

- freeze_core:

  Logical — apply the frozen-core approximation before the active-space
  transformation. Default `TRUE`.

- num_active_electrons:

  Optional integer — size of the active electron space (after freezing
  the core). When `NULL`, no active-space reduction is applied (all
  frontier orbitals kept).

- num_active_orbitals:

  Optional integer — size of the active orbital space.

- mapper:

  Character — fermion-to-qubit mapping. One of `"parity"` (default, with
  tapering by particle-number symmetry), `"jordan_wigner"`,
  `"bravyi_kitaev"`.

## Value

An `edaphos_quantum_hamiltonian` carrying the Pauli-string Hamiltonian
of the active-space problem. The object additionally exposes the
following attributes:

- `nuclear_repulsion_energy`:

  Nuclear-nuclear Coulomb repulsion (constant).

- `frozen_core_shift`:

  Constant energy shift introduced by the frozen-core transformation (0
  when `freeze_core = FALSE`).

- `reference_energy`:

  Hartree-Fock reference energy of the active-space problem.

- `num_particles`:

  Length-2 integer vector `c(alpha, beta)` — the number of spin-up and
  spin-down electrons in the active space.

- `num_spatial_orbitals`:

  Number of active spatial orbitals.

- `geometry, basis, charge, spin, mapper`:

  Echoed inputs.

## Details

The returned object is a standard `edaphos_quantum_hamiltonian` and can
be dropped straight into
[`quantum_vqe_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_fit.md)
or
[`quantum_ibmq_submit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_submit.md).
It additionally exposes the full set of energy shifts as attributes so
the user can recompute the total molecular energy from a VQE result:
\$\$E\_\mathrm{total} = \langle H \rangle\_\mathrm{VQE} +
E\_\mathrm{shift}\$\$ where \\E\_\mathrm{shift} = E\_\mathrm{nuc} +
E\_\mathrm{frozen} + E\_\mathrm{active}\\ sums the nuclear-repulsion
constant, the frozen-core shift (zero when `freeze_core = FALSE`) and
the active-space projection shift (zero when no active-space
transformation is applied). The helper
[`quantum_nature_total_energy()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_nature_total_energy.md)
performs this reconstruction on a fit object.

## References

Sun, Q. et al. (2018). PySCF: the Python-based simulations of chemistry
framework. *WIREs Computational Molecular Science* **8**, e1340.

Bravyi, S. et al. (2017). Tapering off qubits to simulate fermionic
Hamiltonians. arXiv:1701.08213.

## See also

[`quantum_hamiltonian_organo_mineral_nature()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_organo_mineral_nature.md)
for curated presets;
[`quantum_vqe_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_fit.md)
to minimise the returned Hamiltonian.

## Examples

``` r
if (FALSE) { # \dontrun{
  # H2 at equilibrium bond length, 2 qubits after parity tapering:
  h2 <- quantum_hamiltonian_from_pyscf(
    atom = "H 0 0 0; H 0 0 0.735",
    basis = "sto3g", charge = 0, spin = 0
  )
  fit <- quantum_vqe_fit(h2, seed = 1L)
  fit$energy + attr(h2, "nuclear_repulsion_energy")
} # }
```
