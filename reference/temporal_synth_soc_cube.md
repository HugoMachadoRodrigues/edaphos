# Generate a synthetic 4D soil-dynamics cube (Pillar 3 helper)

Builds a small spatio-temporal cube with realistic-looking dynamics of
Soil Organic Carbon (SOC) driven by monthly precipitation over a static
elevation field. The governing update is a minimalist mass-balance

## Usage

``` r
temporal_synth_soc_cube(
  H = 16L,
  W = 16L,
  T_total = 18L,
  seed = 1L,
  k_in = 0.03,
  k_out = 0.015,
  noise = 0.2
)
```

## Arguments

- H, W:

  Integer, spatial grid size.

- T_total:

  Integer, total number of months.

- seed:

  Integer, RNG seed for reproducibility.

- k_in, k_out:

  Numeric rate coefficients (defaults are tuned so SOC stays in a
  physically plausible 10-50 g/kg range).

- noise:

  Numeric, standard deviation of Gaussian process noise on the SOC
  evolution (per pixel, per month).

## Value

A list with elements

- elev:

  Numeric matrix `H x W`.

- precip:

  Numeric array `T x H x W`.

- soc:

  Numeric array `T x H x W`.

## Details

\$\$ \mathrm{SOC}\_{t+1} = \mathrm{SOC}\_t + k\_{\text{in}}\\ P_t -
k\_{\text{out}}\\\mathrm{SOC}\_t\\ P_t / \bar{P} + \varepsilon \$\$

with `k_in, k_out` small, \\P_t\\ the monthly precipitation, and \\\bar
P\\ the long-term mean. Precipitation itself is a sinusoidal seasonal
cycle modulated by a west-east gradient so the cube shows both temporal
memory and spatial heterogeneity.

Use the resulting object to train
[`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md)
and forecast forward with
[`temporal_convlstm_rollout()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_rollout.md)
in the Pillar 3 vignette.

## Examples

``` r
cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 12, seed = 1)
dim(cube$soc)  # 12 x 8 x 8
#> [1] 12  8  8
```
