# List IBM Quantum backends available to the current account

Requires
[`quantum_ibmq_available()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_available.md)
to return `TRUE`. Pulls the current list via
`qiskit_ibm_runtime.QiskitRuntimeService`.

## Usage

``` r
quantum_ibmq_backends(operational_only = TRUE, simulator = FALSE)
```

## Arguments

- operational_only:

  Logical — if `TRUE` (default) restricts the result to backends whose
  `.status().operational` is `TRUE`.

- simulator:

  Logical — if `TRUE`, include simulator backends; if `FALSE` (default),
  restrict to real quantum processors.

## Value

A character vector of backend names, or a length-0 vector when the
service is unavailable.
