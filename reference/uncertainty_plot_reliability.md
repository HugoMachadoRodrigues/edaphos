# Reliability diagram from a calibration result

Given the output of
[`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md),
draws a reliability diagram (nominal vs empirical coverage) with the
identity line.

## Usage

``` r
uncertainty_plot_reliability(calib, ...)
```

## Arguments

- calib:

  List returned by
  [`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md).

- ...:

  Ignored.

## Value

A `ggplot` object.
