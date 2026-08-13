# Check whether the qiskit-nature + PySCF stack is available

Returns `TRUE` when (i) `reticulate` is installed; (ii) the `qiskit`
core module is importable; (iii) the `qiskit_nature` Python module is
importable; and (iv) the `pyscf` Python module is importable. The
function does not execute any electronic- structure calculation — it is
a cheap preflight probe safe to call from tests and CI.

## Usage

``` r
quantum_nature_available()
```

## Value

Logical scalar.

## Examples

``` r
if (FALSE) { # \dontrun{
  quantum_nature_available()

  # Four independent conditions. qiskit-nature and pyscf are
  # separate pip installs and a missing pyscf is the usual culprit,
  # so decompose a FALSE instead of reinstalling the whole stack.
  c(reticulate = requireNamespace("reticulate", quietly = TRUE),
    qiskit     = reticulate::py_module_available("qiskit"),
    nature     = reticulate::py_module_available("qiskit_nature"),
    pyscf      = reticulate::py_module_available("pyscf"))

  # This probes the ab initio stack only; hardware dispatch is a
  # separate one, and the two are independent. A laptop with PySCF
  # and no IBM account reads TRUE / FALSE -- enough to build an
  # organo-mineral Hamiltonian, not enough to submit it.
  c(nature = quantum_nature_available(),
    ibmq   = quantum_ibmq_available())

  # TRUE only promises that the imports resolve. It says nothing
  # about whether a given geometry is tractable: the two
  # closed-shell presets build a 2-qubit Hamiltonian in under a
  # second, while "ferric_formate" raises a QiskitNatureError for
  # every active space (see
  # quantum_hamiltonian_organo_mineral_nature()).
  ham <- quantum_hamiltonian_organo_mineral_nature("formic_acid")
  c(qubits = ham$n_qubits, terms = length(ham$pauli_terms))  # 2, 9
} # }
```
