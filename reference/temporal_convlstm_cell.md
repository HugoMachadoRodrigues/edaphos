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
