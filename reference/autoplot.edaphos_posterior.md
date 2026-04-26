# Default ggplot for an `edaphos_posterior`

Dispatches on the posterior's `query_type` to produce a suitable figure.
For `"effect"`, `"param"`, `"energy"` the plot is a posterior-density
histogram with a 95 % interval; for `"map"` a three-panel mean / SD / 90
% interval-width facet; for `"sample"` a quantile ribbon indexed by
query position; for `"feature"` a faceted density by feature; for
`"other"` it falls back to the `"sample"` layout.

## Usage

``` r
autoplot.edaphos_posterior(object, ...)
```

## Arguments

- object:

  An `edaphos_posterior`.

- ...:

  Ignored (for S3 compatibility).

## Value

A `ggplot` object.

## Details

Requires the `ggplot2` package.
