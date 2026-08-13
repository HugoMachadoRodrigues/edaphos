# Exact ground-state energy via classical diagonalisation

Runs Qiskit's `NumPyMinimumEigensolver` (dense diagonalisation of the
Hamiltonian matrix) and returns the exact ground-state eigenvalue. Works
for any Hamiltonian up to ~12 qubits before memory becomes the limit.

## Usage

``` r
quantum_vqe_exact(hamiltonian)
```

## Arguments

- hamiltonian:

  An `edaphos_quantum_hamiltonian`.

## Value

A numeric scalar — the ground-state energy.

## Examples

``` r
if (FALSE) { # \dontrun{
h2 <- quantum_hamiltonian_h2()

# This is the yardstick.  `$exact` inside an edaphos_quantum_vqe
# object is literally this call and `$gap` is |energy - exact|; a
# VQE energy means nothing except read next to it.
round(quantum_vqe_exact(h2), 6)                      # -1.857275

# Dense diagonalisation, so cost is 2^n.  n = 14 (a 16384-square
# operator) still returns in about 0.2 s; memory, not time, is
# the wall shortly above that.
system.time(quantum_vqe_exact(quantum_hamiltonian_ising_1d(14)))

# "Exact" is not bit-reproducible: repeated calls scatter by a
# few times 1e-15 (H2) up to 6e-14 (a 10-qubit chain).  That is
# six orders below the best VQE gap below, so it never matters
# numerically -- but do not reach for identical() on it.
v <- replicate(8, quantum_vqe_exact(h2))
diff(range(v))                       # order 1e-15, not 0
isTRUE(all(v == v[1]))               # FALSE

# 1) Exact statevector back end.  No sampling noise whatever, so
#    the gap is pure optimiser error -- and wildly variable across
#    restarts: 1e-9 to 1.5e-3 in one sweep of eight, median 3e-8,
#    because the ansatz start point is random (see the caveat at
#    the end).  Quote the median of restarts, not one run.
fit <- quantum_vqe_fit(h2, backend = "aer_statevector")
c(energy = fit$energy, exact = fit$exact, gap = fit$gap)

# 2) Shot-based Aer with SPSA -- the honest simulation.  4096
#    shots put a 1/sqrt(4096) = 0.0156 Ha standard error on every
#    energy the optimiser sees, and the gap then runs 0.002-0.034
#    Ha: about five orders worse than the median of (1), none of
#    it physics.  SPSA, not COBYLA, because the cost function is
#    now stochastic.
fs <- quantum_vqe_fit(h2, backend = "aer_shots", shots = 4096L,
                      optimizer = "SPSA", max_iter = 60L)
c(gap = fs$gap, shot_se = 1 / sqrt(4096))

# The trap: min(fs$history) is the luckiest of ~171 noisy draws,
# not a variational bound.  It came out BELOW the exact energy in
# 3 of 6 runs, which is physically impossible and diagnoses noise
# rather than success; even fs$energy did so twice in eleven.
# Report `energy`, judge it by `gap`, and treat any gap smaller
# than shot_se as luck rather than convergence.
c(min_history = min(fs$history), exact = fs$exact,
  n_evals = length(fs$history))

# 3) Real hardware.  quantum_ibmq_available() is an offline probe
#    (reticulate + qiskit_ibm_runtime + IBMQ_TOKEN) that touches
#    no network.  `mitigation` is live only here: "m3" maps to IBM
#    resilience_level 1, "zne" to 2; both Aer back ends ignore it
#    and "aer_shots" says so out loud.  `ibmq_backend = NULL`
#    picks the least-busy operational device.  Run (1) first and
#    treat its gap as the floor device error sits on top of.
if (quantum_ibmq_available()) {
  fq <- quantum_vqe_fit(h2, backend = "ibmq",
                        ibmq_backend = "ibm_brisbane",
                        shots = 4096L, mitigation = "m3",
                        optimizer = "SPSA", max_iter = 50L)
  c(hardware = fq$gap, exact_sim = fit$gap)
}

# Caveat for all three: `seed` does NOT make quantum_vqe_fit()
# reproducible -- it seeds numpy's legacy global RNG, not the
# generator qiskit-algorithms draws the initial point from, so
# five runs at seed = 1L gave gaps from 5e-10 to 1e-4.  Pass an
# explicit `initial_point` (12 angles for 2 qubits at reps = 2)
# and `$energy` repeats to the last bit across sessions; `$gap`
# still wobbles at 1e-15 because `exact` does.
p0 <- rep(0.1, 12)
a <- quantum_vqe_fit(h2, initial_point = p0)$energy
b <- quantum_vqe_fit(h2, initial_point = p0)$energy
identical(a, b)             # TRUE, both -1.857131658135603
} # }
```
