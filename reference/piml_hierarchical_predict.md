# Predict depth profiles for new locations from covariates

Predict depth profiles for new locations from covariates

## Usage

``` r
piml_hierarchical_predict(object, new_covariates, newdepths)
```

## Arguments

- object:

  A `edaphos_piml_hierarchical`.

- new_covariates:

  Data frame with at least the covariate columns used at training time
  (one row per location).

- newdepths:

  Numeric vector of depths.

## Value

Numeric matrix, one row per location in `new_covariates`, one column per
depth in `newdepths`.
