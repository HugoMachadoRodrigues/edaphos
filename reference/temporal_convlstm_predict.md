# Predict with a fitted stacked ConvLSTM

Predict with a fitted stacked ConvLSTM

## Usage

``` r
temporal_convlstm_predict(object, sequence, return_sequence = NULL, ...)
```

## Arguments

- object:

  A `edaphos_temporal_convlstm`.

- sequence:

  Array / `torch_tensor` of shape `(batch, T, C, H, W)`.

- return_sequence:

  Logical override; defaults to the value used at training time.

- ...:

  Unused.

## Value

An R array. Shape is `(batch, T, H, W)` when `return_sequence = TRUE`,
otherwise `(batch, H, W)`.
