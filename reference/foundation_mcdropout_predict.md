# MC-dropout predictive draws from a fine-tuned Pillar 4 fit

Runs `n_draws` forward passes through a fitted
`edaphos_foundation_classifier` or `edaphos_foundation_regressor` with
the MLP head's dropout kept in train mode, producing a Monte-Carlo
sample of the predictive posterior (Gal & Ghahramani 2016). The fit must
have been trained with an MLP head and a non-zero `dropout` for the
draws to be non-degenerate.

## Usage

``` r
foundation_mcdropout_predict(object, x, n_draws = 50L, seed = NULL)
```

## Arguments

- object:

  An `edaphos_foundation_classifier` or `edaphos_foundation_regressor`
  fit.

- x:

  New patches `(N, C, H, W)`.

- n_draws:

  Integer; number of MC forward passes.

- seed:

  Optional integer seed.

## Value

For regression, a `(n_draws, N)` numeric matrix. For classification, a
`(n_draws, N, n_classes)` array of softmax probabilities.

## References

Gal, Y. and Ghahramani, Z. (2016). Dropout as a Bayesian approximation:
representing model uncertainty in deep learning. *ICML 33*, 1050-1059.
