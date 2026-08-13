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

## Examples

``` r
if (FALSE) { # \dontrun{
  # Step 3 of the discovery path, for when you have no reason to
  # prefer a particular processor.
  name <- quantum_ibmq_least_busy()
  name %in% quantum_ibmq_backends()        # TRUE: it is one of them

  # `min_num_qubits` filters the DEVICE, and says nothing about the
  # size of your problem. The 2-qubit preset from
  # quantum_hamiltonian_organo_mineral_nature() is routed onto the
  # full coupling map before submission, so the circuit that
  # actually leaves R is as wide as the processor -- 127 qubits on
  # an Eagle device. Width here is a capacity filter, not a limit.
  quantum_ibmq_least_busy(min_num_qubits = 127L)

  # TRAP: NA_character_ is the only failure signal and it covers
  # three unrelated causes -- no token (returns before any network
  # call), no backend matching the filter, and any API error (the
  # service call is wrapped in tryCatch). Split them by hand:
  if (is.na(quantum_ibmq_least_busy(min_num_qubits = 1000L))) {
    if (!quantum_ibmq_available()) {
      message("no IBMQ_TOKEN in this session")
    } else {
      message("token present; no backend that wide, or API error")
    }
  }

  # "Least busy" is a queue-depth decision, not a fidelity one, and
  # it can return a different processor minutes apart. Resolve it
  # once and pin the name when two runs have to be comparable:
  pinned <- quantum_ibmq_least_busy(min_num_qubits = 127L)
  quantum_ibmq_submit(quantum_hamiltonian_h2(),
                       parameters = rep(0.1, 12),
                       backend_name = pinned, mitigation = "m3")
} # }
```
