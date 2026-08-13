# Build a standalone ConvLSTM cell (Pillar 3 primitive)

Build a standalone ConvLSTM cell (Pillar 3 primitive)

## Usage

``` r
temporal_convlstm_cell(input_dim, hidden_dim, kernel_size = 3L)
```

## Arguments

- input_dim, hidden_dim, kernel_size:

  See
  [`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md).

## Value

An `nn_module` cell with methods `forward(input, state)` and
`init_state(batch, height, width)`.

## Examples

``` r
# lantern is a separate binary download, so requireNamespace() alone
# is not enough -- torch_is_installed() is the half that matters.
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {
  torch::torch_manual_seed(1)
  cell <- temporal_convlstm_cell(input_dim = 2, hidden_dim = 3)

  # All four gates come out of ONE convolution: out_channels is
  # 4 * hidden_dim and in_channels is input_dim + hidden_dim,
  # because the input and the previous h are concatenated first.
  print(dim(cell$conv$weight))          # 12 5 3 3

  # init_state() returns (h, c) -- both zeros, both hidden_dim
  # channels. Height and width are yours to supply; the cell is
  # fully convolutional and has no built-in grid size.
  state <- cell$init_state(batch = 1, height = 8, width = 8)
  print(vapply(state, function(s) paste(dim(s), collapse = " x "), ""))
  # "1 x 3 x 8 x 8" "1 x 3 x 8 x 8"

  cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)
  tt   <- temporal_cube_to_tensor(cube)
  x1 <- torch::torch_tensor(
    tt$sequence[, 1, , , , drop = FALSE])$squeeze(2)
  print(x1$shape)                       # 1 2 8 8 = (batch, C, H, W)

  state <- cell(x1, state)
  # The cell emits hidden_dim feature channels, NOT a prediction.
  # The 1x1 head that turns them into one soil property lives in
  # temporal_convlstm_fit()'s stack, not here.
  print(state[[1]]$shape)               # 1 3 8 8

  # h = o * tanh(c) with o in (0, 1), so |h| can never exceed
  # |tanh(c)|. Read c as the retained memory and h as the part of
  # it the next layer is allowed to see.
  print(round(c(h_absmax = as.numeric(state[[1]]$abs()$max()$item()),
                c_absmax = as.numeric(state[[2]]$abs()$max()$item())), 4))
  # h_absmax c_absmax
  #   0.1323   0.2638

  # Trap: padding is floor((kernel_size - 1) / 2), which preserves
  # H and W only for ODD kernels. kernel_size = 2 gives padding 0,
  # so the gates come back 7 x 7 while c_prev is still 8 x 8 and
  # the cell dies on f * c_prev. There is no check for this.
  torch::torch_manual_seed(1)
  even <- temporal_convlstm_cell(2, 3, kernel_size = 2)
  print(tryCatch(even(x1, even$init_state(1, 8, 8)),
                 error = function(e) trimws(
                   sub("Exception raised.*", "", conditionMessage(e)))))
  # "The size of tensor a (7) must match the size of tensor b (8) at
  #  non-singleton dimension 3"
}
```
