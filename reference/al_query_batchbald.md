# BatchBALD information-theoretic batch acquisition

Selects an **information-theoretically optimal batch** of Active
Learning queries from a pool of candidates, following Kirsch, van
Amersfoort and Gal 2019 (see the @references section below). Unlike the
top-`n` BALD strategy (which repeatedly picks the single most uncertain
candidate and therefore tends to select *n* copies of "the same
question" on clustered pools), BatchBALD optimises the joint mutual
information between the *batch* \\y_B = (y\_{x_1}, \ldots, y\_{x_n})\\
and the model parameters:

## Usage

``` r
al_query_batchbald(
  model,
  candidates,
  n = 5L,
  sigma_a2 = NULL,
  physics_gate = NULL
)
```

## Arguments

- model:

  A `edaphos_al_model` from
  [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md)
  or
  [`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md).
  The underlying
  [`ranger::ranger`](http://imbs-hl.github.io/ranger/reference/ranger.md)
  object must have been trained with `keep.inbag = TRUE` (default in
  [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md)),
  so that per-tree predictions are available via
  `predict(..., predict.all = TRUE)`.

- candidates:

  Data frame of unlabelled candidates. Must contain the covariates
  listed in `model$covariates`.

- n:

  Integer — batch size.

- sigma_a2:

  Optional numeric — aleatoric noise variance \\\sigma_a^2\\. When
  `NULL` (default), estimated from the out-of-bag residuals of the
  fitted forest.

- physics_gate:

  Optional function `function(candidates, predicted_mean) -> logical`.
  See
  [`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md).

## Value

Integer vector of row indices in `candidates` that form the selected
batch, in greedy-selection order (the first index is the highest-BALD
single point; each subsequent index is the point that maximally
increases the joint log-determinant given the previously selected
batch).

## Details

\$\$ \mathrm{BatchBALD}(B) \\=\\ I\bigl(y_B ; \theta \mid x_B, \mathcal
D\bigr). \$\$

For a regression model with Gaussian aleatoric noise of variance
\\\sigma_a^2\\ and an epistemic posterior represented by `T` parameter
draws \\f\_\theta^{(1)}, \ldots, f\_\theta^{(T)}\\, the objective
reduces to a log-determinant :

\$\$ \mathrm{BatchBALD}(B) \\\propto\\ \tfrac{1}{2}\log\det\\\bigl(
\mathrm{Cov}\_\theta\bigl(f\_\theta(B)\bigr) + \sigma_a^2 I\_{\|B\|}
\bigr). \$\$

For a Quantile Regression Forest (which is what
[`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md)
produces) the trees themselves are the `T` parameter draws, so the joint
covariance is just the per-tree empirical covariance across candidates.
The greedy selection inherits the \\(1 - 1/e)\\-optimality guarantee of
submodular maximisation (Nemhauser, Wolsey and Fisher 1978) and is
implemented via Schur-complement / Cholesky updates so every greedy step
is \\O(m^2 n\_\mathrm{pool})\\ rather than \\O(m^3 n\_\mathrm{pool})\\.

This is a **complement** to
[`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md),
not a replacement: the hybrid uncertainty + diversity strategy there
remains the default for low-budget settings where a physical-distance
term is needed. Use BatchBALD when (a) the covariate pool contains
clusters of near-duplicate candidates and top-`n` BALD would select all
of them, (b) the QRF aleatoric noise is well-estimated, and (c) the
batch size is moderate (`n <= 50` for laptop-scale pools of up to ~10
000 candidates).

## References

Kirsch, A., van Amersfoort, J. and Gal, Y. (2019). BatchBALD: Efficient
and diverse batch acquisition for deep Bayesian active learning.
*NeurIPS 32*, 7024–7035.

Meinshausen, N. (2006). Quantile regression forests. *Journal of Machine
Learning Research* **7**, 983–999.

Nemhauser, G. L., Wolsey, L. A. and Fisher, M. L. (1978). An analysis of
approximations for maximizing submodular set functions — I.
*Mathematical Programming* **14**, 265–294.

## See also

[`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md)
for uncertainty-plus-diversity acquisition;
[`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md)
for the QRF backbone.

## Examples

``` r
if (FALSE) { # \dontrun{
  al <- al_initial_design(br_cerrado, c("elev","slope","twi"),
                           n = 20L, seed = 1L)
  fit <- al_fit(al, target = "soc")
  pool <- br_cerrado[setdiff(seq_len(nrow(br_cerrado)), al$idx), ]
  batch <- al_query_batchbald(fit, pool, n = 10L)
} # }
```
