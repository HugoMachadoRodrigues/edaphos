# Molecular H2 in the Bravyi-Kitaev-tapered 2-qubit basis

Textbook Hamiltonian of the hydrogen molecule in the STO-3G basis after
parity mapping plus Z2 symmetry reduction — the 2-qubit problem whose
ground-state energy is the hallmark VQE benchmark. Coefficients are
reported at the equilibrium bond length 0.735 A.

## Usage

``` r
quantum_hamiltonian_h2()
```

## Value

An `edaphos_quantum_hamiltonian` with 2 qubits.

## References

Peruzzo, A. et al. (2014). A variational eigenvalue solver on a photonic
quantum processor. *Nature Communications* **5**, 4213.
doi:10.1038/ncomms5213.

## Examples

``` r
if (FALSE) { # \dontrun{
h2 <- quantum_hamiltonian_h2()
h2                                  # 2 qubits, 5 Pauli terms

# The reference every VQE run in this package is scored against:
# the exact STO-3G ground state at 0.735 A.
round(quantum_vqe_exact(h2), 6)                      # -1.857275

# -1.052373 of that is the "II" term, a constant no ansatz can
# touch.  Only -0.804902 Ha is what the circuit actually has to
# find, so a relative error quoted against -1.857 flatters the
# fit by a factor of 2.31.
h2_var <- quantum_hamiltonian(
  h2$pauli_terms[names(h2$pauli_terms) != "II"])
round(quantum_vqe_exact(h2_var), 6)                  # -0.804902
round(quantum_vqe_exact(h2) / quantum_vqe_exact(h2_var), 2)  # 2.31

# Four levels only, so the whole spectrum is inspectable.  The
# 0.6127 Ha gap to the first excited state is what makes H2 a
# forgiving benchmark: shot noise of order 0.02 Ha cannot confuse
# the two.  Read it next to the 0.1258 Ha gap of
# quantum_hamiltonian_organo_mineral(), where it can.
lv <- sort(Re(eigen(h2$op$to_matrix(), only.values = TRUE)$values))
round(lv, 6)     # -1.857275 -1.244584 -0.882722 -0.224911
round(lv[2] - lv[1], 4)                              # 0.6127
} # }
```
