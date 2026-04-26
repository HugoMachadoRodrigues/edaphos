# Append newly labeled samples and refit the model

Manual one-shot companion to
[`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md):
takes a model, some freshly labeled samples (for instance returned from
the lab), refits the QRF, and appends a history entry. Use this when you
are driving the loop yourself instead of letting
[`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md)
orchestrate it.

## Usage

``` r
al_update(model, new_samples, ...)
```

## Arguments

- model:

  A `edaphos_al_model`.

- new_samples:

  Data frame with the same columns as `model$labeled` (i.e. target,
  covariates, and optional coords).

- ...:

  Extra arguments forwarded to
  [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md).

## Value

An updated `edaphos_al_model`.
