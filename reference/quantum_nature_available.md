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
