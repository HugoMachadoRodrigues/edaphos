# Estimate a causal effect using DAG-guided backdoor adjustment

Identifies a valid backdoor-adjustment set from the supplied DAG (unless
one is provided manually) and then fits an **adjusted outcome model**
conditional on that set. Two estimators are available:

## Usage

``` r
causal_estimate_effect(
  data,
  dag,
  exposure,
  outcome,
  adjustment = NULL,
  effect = c("direct", "total"),
  type = c("minimal", "canonical", "all"),
  estimator = c("lm", "bart"),
  delta = NULL,
  bart_kwargs = list()
)
```

## Arguments

- data:

  Data frame with columns covering at least `exposure`, `outcome`, and
  the chosen adjustment set.

- dag:

  A `dagitty` DAG.

- exposure, outcome:

  Character column names.

- adjustment:

  Optional character vector overriding the automatic adjustment set.

- effect, type:

  Forwarded to
  [`causal_adjustment_set()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_adjustment_set.md).

- estimator:

  One of `"lm"` (default) or `"bart"` (requires `dbarts`).

- delta:

  Numeric finite-difference step used by the BART estimator. Defaults to
  the interquartile range of `exposure` divided by two.

- bart_kwargs:

  Optional named list of extra arguments forwarded to
  [`dbarts::bart()`](https://rdrr.io/pkg/dbarts/man/bart.html) (e.g.
  `ndpost`, `nskip`, `seed`).

## Value

A `edaphos_causal_effect` object with:

- model:

  The fitted estimator (either an `lm` or a
  [`dbarts::bart`](https://rdrr.io/pkg/dbarts/man/bart.html) object).

- estimator:

  Character; `"lm"` or `"bart"`.

- adjustment:

  The adjustment set used.

- effect:

  Numeric direct effect.

- effect_ci:

  95 % CI (asymptotic for `"lm"`, posterior quantile for `"bart"`).

- effect_naive:

  Coefficient from the unadjusted `lm(outcome ~ exposure)` for contrast.

## Details

- `estimator = "lm"` — closed-form linear regression \\Y = \beta_0 +
  \beta\_{\text{exposure}}\\X + \sum\_{z\in Z}\gamma_z z +
  \varepsilon\\. The regression coefficient on `exposure` is the direct
  causal effect. Confidence intervals follow from OLS asymptotics.

- `estimator = "bart"` — non-linear Bayesian Additive Regression Trees
  (Chipman, George & McCulloch 2010), via the `dbarts` Suggests
  dependency. The effect of `exposure` is computed as the **average
  partial derivative** \\\bar{\partial} = \frac{1}{n}\sum_i
  \bigl\[\widehat{E}\[Y\mid X=x_i+\delta, Z=z_i\] - \widehat{E}\[Y\mid
  X=x_i, Z=z_i\]\bigr\] / \delta\\ averaged over the training data. A 95
  % credible interval is recovered from the BART posterior draws.

## References

Chipman, H. A., George, E. I., & McCulloch, R. E. (2010). BART: Bayesian
Additive Regression Trees. *Annals of Applied Statistics* **4**,
266-298.

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE)) {
  dag <- causal_cerrado_dag()

  # Greenness looks like an enormous SOC driver until the DAG is
  # honoured: twi, slope and map_mm cause both ndvi and soc, so the
  # raw slope (about 49) is inflated. Adjusting cuts it to about 18.
  print(causal_estimate_effect(br_cerrado, dag, "ndvi", "soc"))

  # Elevation is the instructive case: the adjusted effect comes out
  # positive, the unadjusted one negative -- a sign flip.
  print(causal_estimate_effect(br_cerrado, dag, "elev", "soc"))

  # Read that flip carefully. elev has no parents in this DAG, so
  # the unadjusted slope is not confounded at all, despite the
  # wording the print method uses: it is the *total* effect, and
  # asking for it reproduces the naive number exactly. The gap
  # between the two is mediation through slope, twi and map_mm.
  print(dagitty::parents(dag, "elev"))
  print(causal_estimate_effect(br_cerrado, dag, "elev", "soc",
                               effect = "total"))

  # Same adjustment set, non-linear estimator. BART also puts the
  # direct elevation effect above zero, and lands below the OLS
  # slope. Note what it reports: an average finite difference over a
  # step of delta = IQR/2 (76.4 m of elevation here), not a local
  # derivative, so it equals the OLS coefficient only if the
  # response really is linear over that span.
  if (requireNamespace("dbarts", quietly = TRUE)) {
    set.seed(1)
    print(causal_estimate_effect(
      br_cerrado, dag, "elev", "soc", estimator = "bart",
      bart_kwargs = list(ntree = 50L, ndpost = 200L, nskip = 100L)))
  }
}
#> <edaphos_causal_effect>
#>   ndvi -> soc   (estimator: lm)
#>   adjustment set : {map_mm, slope, twi}
#>   direct effect  : 18.43   (95% CI: 14.61, 22.25)
#>   naive effect   : 49.36   (un-adjusted, likely confounded)
#> <edaphos_causal_effect>
#>   elev -> soc   (estimator: lm)
#>   adjustment set : {map_mm, slope, twi}
#>   direct effect  : 0.01482   (95% CI: 0.01048, 0.01916)
#>   naive effect   : -0.02389   (un-adjusted, likely confounded)
#> character(0)
#> <edaphos_causal_effect>
#>   elev -> soc   (estimator: lm)
#>   adjustment set : {(empty)}
#>   total effect   : -0.02389   (95% CI: -0.02627, -0.02152)
#>   naive effect   : -0.02389   (un-adjusted, likely confounded)
#> <edaphos_causal_effect>
#>   elev -> soc   (estimator: bart)
#>   adjustment set : {map_mm, slope, twi}
#>   direct effect  : 0.01007   (95% credible: 0.004576, 0.01475)
#>   naive effect   : -0.02389   (un-adjusted, likely confounded)
#>   delta (finite diff) : 76.4
```
