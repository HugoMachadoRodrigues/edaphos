# Fit the Pillar 2 profile model to a group of pedons independently

Convenience wrapper that calls
[`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)
separately on each pedon in a long-format data frame, returning a list
of fits keyed by `id`. This is the baseline against which a future
pooled (covariate-conditioned) PIML model will be compared.

## Usage

``` r
piml_profile_fit_group(data, id, depth, value, ...)
```

## Arguments

- data:

  Data frame in long form with one row per horizon.

- id:

  Character, name of the column identifying each pedon.

- depth:

  Character, name of the column with horizon mid-depths.

- value:

  Character, name of the column with observed values.

- ...:

  Forwarded to
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md).

## Value

A named list of `edaphos_piml_profile` fits.
