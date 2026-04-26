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
