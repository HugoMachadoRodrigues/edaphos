# Pick the least-busy operational IBM Quantum backend

Thin wrapper around `QiskitRuntimeService$least_busy()`. Useful as a
sane default when the caller has no reason to target a specific
processor.

## Usage

``` r
quantum_ibmq_least_busy(simulator = FALSE, min_num_qubits = NULL)
```

## Arguments

- simulator:

  Logical — see
  [`quantum_ibmq_backends()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_backends.md).

- min_num_qubits:

  Optional integer — require at least this many qubits on the returned
  backend.

## Value

The backend name as a single character string, or `NA_character_` when
no backend matches.
