# Query the most informative unlabeled candidates

Given a fitted Active-Learning model, picks the next `n` candidates to
sample according to a trade-off strategy. All strategies use a **greedy
batch-mode** selection: the second and later picks within the same call
see the previously picked points as if they were already labeled, so the
batch remains internally diverse.

## Usage

``` r
al_query(
  model,
  candidates,
  n = 5L,
  strategy = c("hybrid", "uncertainty", "diverse", "cost"),
  alpha = 0.7,
  quantiles = c(0.1, 0.9),
  base = NULL,
  cost_weight = 0.3,
  physics_gate = NULL
)
```

## Arguments

- model:

  A `edaphos_al_model`.

- candidates:

  Data frame of unlabeled candidate locations. Must contain
  `model$covariates`. Rows with `NA` in any covariate are ignored.

- n:

  Integer, batch size.

- strategy:

  One of `"hybrid"`, `"uncertainty"`, `"diverse"`, `"cost"`.

- alpha:

  Numeric in `[0, 1]`, weight of uncertainty vs diversity in `hybrid` /
  `cost`.

- quantiles:

  Length-2 numeric with the lower/upper probabilities used to measure
  the QRF interval width. Defaults to `c(0.1, 0.9)`.

- base:

  Numeric length-2 vector `c(x, y)`; required by `strategy = "cost"`.

- cost_weight:

  Numeric, weight of the cost penalty in `"cost"`.

- physics_gate:

  Optional function `function(candidates, predicted_mean) -> logical`
  that returns `TRUE` for physically feasible candidates and `FALSE` for
  infeasible ones. Infeasible rows are excluded from the greedy
  selection, linking Pillar 5 to Pillar 2 — see
  [`al_physics_gate_piml()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml.md)
  for a ready-made gate driven by a PIML profile fit.

## Value

Integer vector of row indices in `candidates` that form the next batch,
in selection order.

## Strategies

- `"uncertainty"` — highest QRF prediction-interval width (pure
  exploitation of model uncertainty).

- `"diverse"` — max-min distance in the *standardised* covariate space
  from both the current labeled set and the already-picked batch members
  (pure exploration).

- `"hybrid"` — convex combination
  `alpha * uncertainty + (1 - alpha) * diversity` on 0-1 scaled scores.
  The recommended default.

- `"cost"` — `"hybrid"` minus `cost_weight * cost`, where `cost` is the
  0-1 normalised Euclidean distance to a logistical `base` (x, y). Use
  this to steer an autonomous sampler (drone, rover) towards points it
  can physically reach with limited energy.
