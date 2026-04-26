# Closed-loop Autonomous Active Learning for soil mapping

Runs the full Pillar 5 closed loop:

1.  fit a Quantile Regression Forest on the current labeled set;

2.  query the next batch of candidates via
    [`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md);

3.  label them through a user-supplied `oracle` (or a simulation oracle,
    when the reference values are already in `candidates`);

4.  append + refit;

5.  repeat until the sampling budget is exhausted or the OOB RMSE falls
    below `stop_rmse`.

## Usage

``` r
al_loop(
  labeled,
  candidates,
  target,
  covariates,
  coords = NULL,
  budget = 30L,
  batch = 5L,
  strategy = c("hybrid", "uncertainty", "diverse", "cost"),
  alpha = 0.7,
  quantiles = c(0.1, 0.9),
  base = NULL,
  cost_weight = 0.3,
  physics_gate = NULL,
  oracle = NULL,
  stop_rmse = NULL,
  num.trees = 500L,
  verbose = TRUE
)
```

## Arguments

- labeled:

  Data frame with the initial labeled sample.

- candidates:

  Data frame of unlabeled candidate locations. When `oracle` is `NULL`,
  `candidates[[target]]` must already contain the true values
  (simulation mode).

- target:

  Character, name of the target column.

- covariates:

  Character vector of covariate column names.

- coords:

  Optional length-2 character vector naming x/y columns.

- budget:

  Integer, total number of samples the loop is allowed to query (in
  addition to the initial set).

- batch:

  Integer, number of samples to query per iteration.

- strategy:

  Query strategy — see
  [`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md).

- alpha, quantiles, base, cost_weight, physics_gate:

  Forwarded to
  [`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md).
  See
  [`al_physics_gate_piml()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml.md)
  for a PIML-backed physics gate that couples this Pillar 5 loop to a
  Pillar 2 fit.

- oracle:

  Optional labelling function `function(samples) -> numeric`. When
  `NULL`, a simulation oracle reads the true target from `candidates`.

- stop_rmse:

  Optional early-stop threshold on OOB RMSE.

- num.trees:

  Integer, forest size used at every refit.

- verbose:

  Logical; print per-iteration diagnostics.

## Value

A `edaphos_al_model` whose `$history` contains one entry per iteration
(iter 0 is the initial fit).

## Details

The `oracle` argument is the extension point that lets the same code
drive simulation, lab-pipeline integration, or on-board Edge-AI decision
making on a drone/rover (the Pillar-5 endgame).

## Examples

``` r
# \donttest{
  if (requireNamespace("sp", quietly = TRUE)) {
    data(meuse, package = "sp")
    d <- stats::na.omit(meuse[, c("x", "y", "dist", "elev",
                                  "ffreq", "soil", "lead")])
    d$ffreq <- as.numeric(d$ffreq)
    d$soil  <- as.numeric(d$soil)
    set.seed(1)
    seed_idx  <- al_initial_design(d, c("dist", "elev", "ffreq", "soil"),
                                   n = 15, iter = 500)
    m <- al_loop(
      labeled    = d[seed_idx, ],
      candidates = d[-seed_idx, ],
      target     = "lead",
      covariates = c("dist", "elev", "ffreq", "soil"),
      coords     = c("x", "y"),
      budget     = 20, batch = 5,
      strategy   = "hybrid", verbose = FALSE
    )
    al_history(m)
  }
#>   iter n_labeled rmse_oob mean_uncertainty
#> 1    0        15 53.49527               NA
#> 2    1        20 63.21191            242.6
#> 3    2        25 63.28423            227.0
#> 4    3        30 62.15733            234.4
#> 5    4        35 67.83500            198.2
# }
```
