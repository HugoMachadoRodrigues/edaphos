# Calibration diagnostics for an `edaphos_posterior`

Computes the continuous ranked probability score (CRPS), a
prediction-interval coverage probability (PICP) at each requested
nominal level, the mean prediction-interval width (MPIW) at the same
levels, and a ready-for-ggplot reliability data frame.

## Usage

``` r
uncertainty_calibrate(post, truth, probs = seq(0.05, 0.95, by = 0.05))
```

## Arguments

- post:

  An `edaphos_posterior`.

- truth:

  Numeric array with the same shape as `post$mean`; the ground-truth
  values.

- probs:

  Nominal coverage probabilities at which to report PICP + MPIW, and for
  the reliability curve. Defaults to `seq(0.05, 0.95, by = 0.05)`.

## Value

A list with:

- crps:

  Mean sample-based CRPS across query cells.

- picp:

  Named vector of empirical coverage, one per `probs`.

- mpiw:

  Named vector of mean interval widths, one per `probs`.

- reliability_df:

  Data frame with columns `nominal`, `empirical`, `diff` suitable for
  [`ggplot2::geom_line`](https://ggplot2.tidyverse.org/reference/geom_path.html).

- point_rmse:

  Root-mean-squared error of the posterior mean against the truth.

## Details

The CRPS for a sample-based posterior `F` and a scalar truth `y` is
computed from the Monte-Carlo formula \\ \mathrm{CRPS}(F, y) =
\tfrac{1}{N}\sum_i \|s_i - y\| - \tfrac{1}{2N^2}\sum\_{i,j} \|s_i -
s_j\| \\ (see Gneiting & Raftery 2007 for the derivation and its
strictly proper scoring rule interpretation). The per-query CRPS is
averaged across all query cells for a single reported scalar.

## References

Gneiting, T. and Raftery, A. E. (2007). Strictly proper scoring rules,
prediction, and estimation. *Journal of the American Statistical
Association* **102**(477), 359-378.
