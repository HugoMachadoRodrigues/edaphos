# Quantum feature map (Pillar 6)

Returns the complex amplitude vector of the ZZFeatureMap quantum state
\\\lvert\phi(\mathbf{x})\rangle\\ produced by the data- encoding circuit
of Havlicek et al. (2019). The feature vector `x` should already be
normalised into the range `[0, pi]` — see
[`quantum_scale()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_scale.md).

## Usage

``` r
quantum_feature_map(x, reps = 2L)
```

## Arguments

- x:

  Numeric vector of features (one qubit per feature).

- reps:

  Integer, number of times the encoding circuit is repeated (`>= 1`).
  Higher values give more expressive kernels at a per-sample simulation
  cost of `O(reps * 2^n)`.

## Value

Complex vector of length `2^length(x)` — the state-vector amplitudes of
\\\lvert\phi(\mathbf{x})\rangle\\ in the computational basis.

## Examples

``` r
psi <- quantum_feature_map(c(pi/4, pi/3, pi/2), reps = 2L)
sum(Mod(psi)^2)  # 1 — quantum state is normalised
#> [1] 1
```
