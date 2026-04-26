# Coerce a native pillar object to `edaphos_posterior`

Each pillar ships an `as_edaphos_posterior()` method that wraps its
natural uncertainty representation in the unified class. The default
method accepts already-wrapped objects, numeric vectors (treated as a
1-D scalar posterior), and numeric matrices (treated as
`n_samples x n_query` matrices).

## Usage

``` r
as_edaphos_posterior(x, ...)
```

## Arguments

- x:

  Object to coerce.

- ...:

  Additional arguments passed to the pillar-specific method (e.g.
  `query_type`, `units`).

## Value

An `edaphos_posterior`.
