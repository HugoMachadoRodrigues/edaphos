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
  physics_scaling = NULL,
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

- physics_scaling:

  The `scaling` list returned by
  [`temporal_cube_to_tensor()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_cube_to_tensor.md)
  (`soc_mu`, `soc_sd`, `prec_mu`, `prec_sd`). **Required whenever
  `physics_lambda > 0`.** `physics_k_in` and `physics_k_out` are rates
  in the property's raw units, but the driver channel the network sees
  is standardised, whose mean is zero to machine precision — so the
  outflow term \\k\_{out} y P / \bar P\\ cannot be formed without the
  constants that map between the two scales. An earlier version guarded
  the division with `1e-6` instead, which turned the physics residual
  into a 1e6 amplification of numerical noise: it arrived 2.6e7 times
  heavier than the data-fit term, its sign flipped with the seed, and it
  made the fit 12 times worse rather than regularising it. Supplying the
  scaling is now mandatory rather than optional, because there is no
  correct way to proceed without it.

- seed:

  Optional integer for reproducibility.

- verbose:

  Logical; print loss every 10 epochs.

## Value

A `edaphos_temporal_convlstm` object (list) with the trained model,
config, and loss history.

## Examples

``` r
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {
  cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)
  tt   <- temporal_cube_to_tensor(cube)

  # Sequence-to-one: six months of (elev, precip) -> the month-6 SOC
  # map. `target` must keep its batch axis, so 3-D (1, H, W). The
  # 2-D map that tt$target[1, 6, , ] returns is rejected by
  # stopifnot(target$dim() == 3L).
  y6  <- array(tt$target[1, 6, , ], dim = c(1, 8, 8))
  fit <- temporal_convlstm_fit(tt$sequence, y6, hidden_dims = 4L,
                               epochs = 150L, lr = 0.05, seed = 1L)
  print(fit)

  # A loss number alone means nothing. The reference that makes it
  # readable is the constant map: mean(y6) predicted everywhere.
  baseline <- mean((y6 - mean(y6))^2)
  print(round(c(final = fit$final_loss, baseline = baseline,
                ratio = fit$final_loss / baseline), 4))
  #   final baseline    ratio
  #  0.0091   0.5382   0.0169

  # Adam at lr = 0.05 is not monotone: 7 of the 149 steps go uphill,
  # so never read final_loss as "the best loss reached".
  print(sum(diff(fit$loss_history) > 0))          # 7

  # And keep the ratio in proportion -- this fits 64 pixels with
  # this many parameters and no held-out month, so 0.0169 measures
  # capacity, not skill. temporal_convlstm_rollout() is where the
  # same model has to face months it never saw.
  print(sum(vapply(fit$model$parameters,
                   function(p) prod(dim(p)), 0)))  # 885

  # Trap 1: the physics regulariser is silently inert unless
  # return_sequence = TRUE. physics_lambda is stored on the object
  # either way, so loss_phys_history is the only proof it ever ran.
  off <- temporal_convlstm_fit(tt$sequence, y6, epochs = 20L, lr = 0.05,
                               seed = 1L, physics_lambda = 10)
  print(c(lambda = off$physics_lambda,
          phys_loss = max(off$loss_phys_history)))
  #    lambda phys_loss
  #        10         0

  # Trap 2: the mass balance is written in RAW units -- physics_k_in
  # and physics_k_out are the g/kg-per-mm rates of the generator --
  # but temporal_cube_to_tensor() hands over a z-scored driver whose
  # mean is zero to machine precision, so the outflow term
  # k_out * y * P / mean(P) cannot be formed on that scale.
  print(mean(as.numeric(tt$sequence[1, , 2, , ])))   # ~1.2e-16

  # Supplying the scaling constants is therefore mandatory, not
  # optional. Without them the fit refuses rather than guessing.
  print(class(try(
    temporal_convlstm_fit(tt$sequence, tt$target, return_sequence = TRUE,
                          epochs = 2L, physics_lambda = 1, seed = 1L),
    silent = TRUE)))                                 # "try-error"

  on <- temporal_convlstm_fit(tt$sequence, tt$target, hidden_dims = 4L,
                              return_sequence = TRUE, epochs = 30L,
                              lr = 0.05, seed = 1L, physics_lambda = 1,
                              physics_scaling = tt$scaling)
  print(signif(c(fit   = on$loss_fit_history[1],
                 phys  = on$loss_phys_history[1],
                 ratio = on$loss_phys_history[1] /
                         on$loss_fit_history[1]), 3))

  # The physics term is now the same order of magnitude as the term it
  # regularises, and it is itself minimised over training rather than
  # merely recorded.
  print(signif(c(phys_first = on$loss_phys_history[1],
                 phys_last  = on$loss_phys_history[30]), 3))

  # What it costs the data fit is now a normal regulariser trade-off,
  # small and of either sign depending on the cube: on this one it
  # costs about 8%, on the seed-1 cube it gains about 15%.
  off2 <- temporal_convlstm_fit(tt$sequence, tt$target, hidden_dims = 4L,
                                return_sequence = TRUE, epochs = 30L,
                                lr = 0.05, seed = 1L, physics_lambda = 0)
  print(signif(c(no_physics = off2$loss_fit_history[30],
                 with_physics = on$loss_fit_history[30]), 4))
  # For scale: an earlier version guarded the zero-mean division with
  # 1e-6, which amplified the residual ~1e6-fold. It arrived 2.6e7
  # times heavier than the data term and made the fit 12 times WORSE,
  # so training optimised the guard rather than the soil. That is why
  # the scaling constants are now required rather than optional.
}
```
