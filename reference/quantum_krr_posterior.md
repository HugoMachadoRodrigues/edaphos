# GP-equivalent posterior for a Quantum Kernel Ridge Regression fit

Given a fitted
[`quantum_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_fit.md)
model, returns the predictive posterior at new inputs as an
[`edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_posterior.md).
Using the well-known equivalence between Kernel Ridge Regression and
Gaussian-process regression (Rasmussen & Williams 2006, §2.3), the
predictive variance is derived analytically from the same gram matrix
`K + lambda I` that produces the point prediction. Aleatoric noise is
estimated from leave-one-out residuals.

## Usage

``` r
quantum_krr_posterior(object, newdata, n_samples = 500L, units = NULL)
```

## Arguments

- object:

  An `edaphos_quantum_krr`.

- newdata:

  A matrix (or data frame) with `ncol(newdata) == object$n_qubits`.

- n_samples:

  Integer; the Gaussian posterior is analytic, so sampling is only
  needed for the `edaphos_posterior` machinery (CRPS estimation etc.).
  Defaults to `500L`.

- units:

  Optional free-text units tag.

## Value

An `edaphos_posterior` with `method = "analytic"` and
`query_type = "sample"`. The epistemic/aleatoric decomposition is
carried through `post$epistemic_sd` and `post$aleatoric_sd`.

## References

Rasmussen, C. E. and Williams, C. K. I. (2006). *Gaussian Processes for
Machine Learning*. MIT Press, §2.3.
