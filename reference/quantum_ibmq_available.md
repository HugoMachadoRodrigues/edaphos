# Check whether an IBM Quantum backend is reachable

Returns `TRUE` when (i) `reticulate` is installed; (ii) the
`qiskit_ibm_runtime` Python module is importable; and (iii) the
`IBMQ_TOKEN` environment variable is set. The function does not contact
the network; it is a cheap preflight probe safe to call from examples,
tests and CI.

## Usage

``` r
quantum_ibmq_available()
```

## Value

Logical scalar.
