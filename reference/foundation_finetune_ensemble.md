# Deep-ensemble fine-tune of a Pillar 4 foundation encoder

Trains `K_ens` independent heads on the same encoder with different
random seeds and collects them into a single object. Each member is a
full
[`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md)
or
[`foundation_fit_regressor()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_regressor.md)
fit.

## Usage

``` r
foundation_finetune_ensemble(
  encoder,
  x,
  y,
  task = c("classification", "regression"),
  K_ens = 5L,
  base_seed = 301L,
  ...
)
```

## Arguments

- encoder:

  A MoCo/SimCLR encoder as returned by
  [`foundation_weights_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_load.md)
  (or an equivalent `nn_module`).

- x, y:

  Training data; same shape requirements as the base fine-tune functions
  (4-D array `(N, C, H, W)` + vector `y`).

- task:

  `"classification"` or `"regression"`.

- K_ens:

  Integer; number of ensemble heads. Defaults to `5L`.

- base_seed:

  Integer; each member uses `base_seed + k - 1L`.

- ...:

  Additional arguments forwarded verbatim to
  [`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md)
  or
  [`foundation_fit_regressor()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_regressor.md)
  (e.g. `epochs`, `batch_size`, `lr`, `dropout`, `hidden`,
  `freeze_backbone`, `device`, `verbose`).

## Value

A list with class `edaphos_foundation_ensemble` containing `members`
(list of K fits), `task`, `K_ens`, `encoder` (a reference to the
fit-time encoder), and `final_losses` / `loss_histories`.

## References

Lakshminarayanan, B., Pritzel, A. and Blundell, C. (2017). Simple and
scalable predictive uncertainty estimation using deep ensembles.
*NeurIPS 30*.
