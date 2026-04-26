# Fit a stacked ConvLSTM on a 4D covariate cube

Trains a multi-layer ConvLSTM + 1x1 head on an input tensor shaped
`(batch, T, C, H, W)`. Supports two objectives:

- **sequence-to-one** (`return_sequence = FALSE`, default) — `target` is
  `(batch, H, W)`, typically the last-month property;

- **sequence-to-sequence** (`return_sequence = TRUE`) — `target` is
  `(batch, T, H, W)`, which is the setup used by
  [`temporal_convlstm_rollout()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_rollout.md)
  to forecast a whole horizon when future driver channels are known
  (e.g. weather forecasts).

## Usage

``` r
temporal_convlstm_fit(
  sequence,
  target,
  hidden_dims = 4L,
  kernel_size = 3L,
  return_sequence = FALSE,
  epochs = 80L,
  lr = 0.01,
  physics_lambda = 0,
  physics_k_in = 0.03,
  physics_k_out = 0.015,
  physics_driver_channel = 2L,
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- sequence:

  R array or `torch_tensor` of shape `(batch, T, C, H, W)`.

- target:

  R array or tensor; shape depends on `return_sequence`.

- hidden_dims:

  Integer vector — one entry per ConvLSTM layer. Length determines
  depth. Default `c(4L)` (single-layer).

- kernel_size:

  Integer, spatial kernel size (odd).

- return_sequence:

  Logical; see objectives above.

- epochs, lr:

  Adam hyperparameters.

- physics_lambda:

  Numeric `>= 0`; weight of the physics-informed mass-balance
  regulariser. When `> 0` (and `return_sequence = TRUE`), the loss
  becomes \$\$\mathrm{MSE}(\hat y, y) + \lambda\_{\text{phys}}\\
  \mathrm{MSE}\\\left(\Delta\hat y_t,\\ k\_{\text{in}} P_t -
  k\_{\text{out}} \hat y_t P_t / \bar P\right),\$\$ i.e. the predicted
  per-step change \\\Delta\hat y_t = \hat y\_{t+1} - \hat y_t\\ is
  pushed towards the mass-balance increment implied by the driver
  channel. This is the Pillar 2 × Pillar 3 fusion — a Physics-Informed
  ConvLSTM.

- physics_k_in, physics_k_out:

  Numeric rate coefficients of the mass-balance prior in the
  *normalised* units the model sees at training time. Setting both to
  zero collapses the physics loss to a pure temporal smoothness penalty.

- physics_driver_channel:

  Integer, index (1-based) of the input channel that carries the driver
  \\P_t\\ (e.g. precipitation).

- seed:

  Optional integer for reproducibility.

- verbose:

  Logical; print loss every 10 epochs.

## Value

A `edaphos_temporal_convlstm` object (list) with the trained model,
config, and loss history.
