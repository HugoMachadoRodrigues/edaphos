# Assemble a 4D input tensor-ready array from a synthetic cube

Packages
[`temporal_synth_soc_cube()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_synth_soc_cube.md)'s
output into the `(batch, T, C, H, W)` array shape expected by
[`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md),
with two channels:

1.  static elevation (broadcast along time);

2.  dynamic precipitation.

Also returns the target SOC array in `(batch, T, H, W)` form.

## Usage

``` r
temporal_cube_to_tensor(cube, t_slice = NULL)
```

## Arguments

- cube:

  List returned by
  [`temporal_synth_soc_cube()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_synth_soc_cube.md).

- t_slice:

  Optional integer vector with time indices to include (default = all
  months). Useful to split train / forecast windows.

## Value

A list with `sequence` `(1, T', 2, H, W)` and `target` `(1, T', H, W)`.
