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

A list with `sequence` `(1, T', 2, H, W)`, `target` `(1, T', H, W)`, and
`scaling` — the six constants (`soc_mu`, `soc_sd`, `prec_mu`, `prec_sd`,
`elev_mu`, `elev_sd`) needed to map z-scored predictions back to g/kg.
`scaling` is always computed from the whole `cube`, never from
`t_slice`.

## Examples

``` r
cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)

# The cube is a LIST of three fields of different rank: a static
# H x W elevation matrix and two T x H x W stacks. It is not an
# array, and it is not stacked in (T, C, H, W) order yet.
vapply(cube, function(z) paste(dim(z), collapse = " x "), "")
#>        elev      precip         soc 
#>     "8 x 8" "6 x 8 x 8" "6 x 8 x 8" 
#        elev      precip         soc
#     "8 x 8" "6 x 8 x 8" "6 x 8 x 8"

tt <- temporal_cube_to_tensor(cube)
dim(tt$sequence)   # 1 6 2 8 8 = (batch, T, channel, H, W)
#> [1] 1 6 2 8 8
dim(tt$target)     # 1 6 8 8   = (batch, T, H, W)
#> [1] 1 6 8 8

# Channel 1 is elevation broadcast along time, channel 2 is the
# monthly precipitation. A static covariate therefore costs T
# identical copies of the same map.
identical(tt$sequence[1, 1, 1, , ], tt$sequence[1, 6, 1, , ])  # TRUE
#> [1] TRUE
identical(tt$sequence[1, 1, 2, , ], tt$sequence[1, 6, 2, , ])  # FALSE
#> [1] FALSE

# Trap: `t_slice` subsets the sequence but NOT the standardisation.
# mu and sd always come from the whole cube, so a training window
# is not centred -- months 1:4 sit 0.55 sd below the six-month mean.
train <- temporal_cube_to_tensor(cube, t_slice = 1:4)
round(c(slice = mean(train$target), full = mean(tt$target)), 4)
#>   slice    full 
#> -0.5519  0.0000 
#   slice    full
# -0.5519  0.0000
identical(train$scaling, tt$scaling)   # TRUE
#> [1] TRUE

# That shared scaling is exactly what temporal_convlstm_rollout()
# needs to compare a train window with a forecast window. It also
# means the forecast months leak their mean and sd into the
# training normalisation; an operational forecast must standardise
# on history only.

# `scaling` is the only route back to g/kg, and it is exact.
soc3 <- tt$target[1, 3, , ] * tt$scaling$soc_sd + tt$scaling$soc_mu
max(abs(soc3 - cube$soc[3, , ]))       # 0
#> [1] 0
round(unlist(tt$scaling[c("soc_mu", "soc_sd")]), 3)
#> soc_mu soc_sd 
#> 23.782  4.313 
# soc_mu soc_sd
# 23.782  4.313
```
