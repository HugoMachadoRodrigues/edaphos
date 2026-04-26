# Time-varying causal effect beta(t) over a sliding window

Closes the Pilar 1 x Pilar 3 loop: the v1.4.0 backdoor-adjusted
estimator is applied within non-overlapping (or overlapping) windows of
the temporal frame, producing a beta_hat(t) trajectory with bootstrap
CIs. Mann-Kendall tests for a significant trend.

## Usage

``` r
causal_effect_time_varying(
  frame,
  dag,
  exposure,
  outcome,
  window = 24L,
  step = 6L,
  adjustment = NULL,
  B = 200L,
  min_n = 30L,
  seed = NULL
)
```

## Arguments

- frame:

  A data frame with columns `t`, `lon`, `lat`, the `exposure`, `outcome`
  and any `adjustment` columns.

- dag:

  A `dagitty` DAG. Used only to derive the adjustment set when
  `adjustment = NULL`.

- exposure, outcome:

  Character column names.

- window:

  Integer; number of distinct `t` values per window.

- step:

  Integer; how many `t` values to advance the window.

- adjustment:

  Optional character vector of adjustment columns.

- B:

  Integer bootstrap replicates per window. `0` disables CI estimation
  (just a point estimate per window).

- min_n:

  Minimum in-window sample size to fit a window. Windows smaller than
  this yield `NA` estimates.

- seed:

  Optional RNG seed for bootstrap reproducibility.

## Value

A `data.frame` of class `edaphos_causal_4d` with columns `t_start`,
`t_end`, `t_centre`, `n`, `beta_hat`, `se`, `ci_lo`, `ci_hi`.
