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

## Examples

``` r
if (FALSE) { # \dontrun{
  # Step 2 of the discovery path: preflight, list, then pick.
  stopifnot(quantum_ibmq_available())
  qpus <- quantum_ibmq_backends()
  qpus

  # TRAP: an unavailable service is reported as character(0), not
  # as an error, so a length-0 result is indistinguishable from
  # "this account has no operational processor". The preflight
  # above is the only thing that tells the two apart -- without it
  # a missing IBMQ_TOKEN looks exactly like an empty fleet.
  length(quantum_ibmq_backends())

  # The difference between the two calls is the calibration queue:
  # `operational_only = FALSE` also lists processors paused for
  # maintenance. Read it before blaming a stalled job on your
  # circuit.
  setdiff(quantum_ibmq_backends(operational_only = FALSE), qpus)

  # `simulator = FALSE` is the default, i.e. real processors only.
  # Flip it to see whatever simulated backends the account still
  # exposes; IBM has been retiring them, so an empty answer here is
  # a normal outcome rather than a misconfiguration.
  quantum_ibmq_backends(simulator = TRUE)

  # Feed a name straight into the dispatch layer. Pinning it is
  # what makes two runs comparable -- see quantum_ibmq_least_busy()
  # for why leaving `ibmq_backend = NULL` does not.
  quantum_vqe_fit(quantum_hamiltonian_h2(), backend = "ibmq",
                   ibmq_backend = qpus[1L],
                   optimizer = "SPSA", max_iter = 50L)
} # }
```
