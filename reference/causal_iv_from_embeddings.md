# Fit 2SLS using foundation-model (or proxy) embeddings as instruments

Convenience wrapper that:

1.  Takes a matrix of per-profile embeddings (rows = profiles, columns =
    embedding dims),

2.  Reduces them to `n_pcs` principal components,

3.  Attaches the PCs to `data` as new columns named `PC_1`, ...,

4.  Runs
    [`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md)
    with the PCs as instruments.

## Usage

``` r
causal_iv_from_embeddings(
  data,
  embeddings,
  exposure,
  outcome,
  covariates = NULL,
  n_pcs = 5L
)
```

## Arguments

- data:

  Data frame with `exposure`, `outcome` and any `covariates`.

- embeddings:

  Numeric matrix with `nrow(data)` rows (one per data row) and any
  number of columns (embedding dimensions).

- exposure, outcome, covariates:

  See
  [`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md).

- n_pcs:

  Integer; number of top principal components to keep as instruments.
  Default `5L`.

## Value

`edaphos_causal_iv` object (see
[`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md)).

## Details

Using the top `n_pcs` principal components instead of raw embedding
dimensions keeps the instrument count manageable (avoiding the curse of
dimensionality) and ensures the instruments are orthogonal (which
simplifies the Sargan diagnostics). The default `n_pcs = 5L` yields a
4-over-identified model for a single-exposure query, enabling the Sargan
J-test.
