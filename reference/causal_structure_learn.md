# Structure learning from horizon data -\> Knowledge Graph

Learns a Directed Acyclic Graph (DAG) over a set of soil covariate /
response variables directly from a horizon-level data frame, using one
of four canonical structure-learning algorithms from the `bnlearn`
package (Scutari 2010). The returned object is an `edaphos_causal_kg` so
the learned DAG can be (i) unioned with the LLM-extracted Knowledge
Graph via
[`causal_augment_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_augment_dag.md),
(ii) exported to RDF via
[`causal_kg_to_turtle()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_to_turtle.md),
and (iii) consumed by the backdoor-adjustment estimator via
[`causal_kg_to_dagitty()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_to_dagitty.md).

## Usage

``` r
causal_structure_learn(
  data,
  variables = NULL,
  method = c("hc", "tabu", "pc-stable", "mmhc"),
  whitelist = NULL,
  blacklist = NULL,
  score = "bic-g",
  alpha = 0.05,
  bootstrap = FALSE,
  R_boot = 200L,
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- data:

  A data frame with one row per observation (typically a pedon or
  horizon).

- variables:

  Optional character vector of columns to include in the analysis. When
  `NULL`, uses every numeric column of `data`.

- method:

  One of `"hc"` (default), `"tabu"`, `"pc-stable"`, `"mmhc"`.

- whitelist:

  Optional data frame with columns `from` and `to` listing edges that
  *must* be present in the learned DAG. Useful for pedological priors,
  e.g. "parent material must precede soil chemistry".

- blacklist:

  Optional data frame with columns `from` and `to` listing edges that
  *must not* appear — typically the reverse of the whitelist plus any
  physically impossible arrows (e.g. `soc -> elevation`).

- score:

  Scoring function for score-based algorithms (`"hc"`, `"tabu"`,
  `"mmhc"`). Defaults to `"bic-g"` (Gaussian BIC) for continuous data;
  `"bge"` (Bayesian Gaussian equivalent) is the alternative. For
  discrete data use `"bic"` or `"bde"`.

- alpha:

  Significance level for conditional-independence tests in `"pc-stable"`
  / `"mmhc"`. Default `0.05`.

- bootstrap:

  Logical — run a bootstrap to estimate edge confidence. Default
  `FALSE`.

- R_boot:

  Integer — number of bootstrap replicates. Default `200`.

- seed:

  Optional integer — used by the bootstrap resampler.

- verbose:

  Logical — forwarded to `bnlearn`.

## Value

An `edaphos_causal_kg` whose `source` field on every edge reads
`"structure_learn(method=...)"` and whose `confidence` is either `1.0`
(point learned DAG, no bootstrap) or the bootstrap edge-frequency.

## Algorithms

- `"hc"` (default):

  Hill-climbing greedy search over DAG space maximising a Bayesian
  Information Criterion (BIC) score (Gaussian BIC for continuous
  variables). Deterministic, fast, and widely used.

- `"tabu"`:

  Tabu-search variant that escapes local optima by keeping a short
  memory of recently visited DAGs.

- `"pc-stable"`:

  PC-stable constraint-based algorithm (Colombo and Maathuis 2014).
  Starts from a complete skeleton and removes edges based on partial
  correlation tests; returns a CPDAG which we extend to a DAG via a
  topological order consistent with the whitelist.

- `"mmhc"`:

  Max-Min Hill-Climbing (Tsamardinos, Brown and Aliferis 2006). Hybrid:
  learns a skeleton by constraint tests, then orients edges by
  hill-climbing over a BIC score.

## Bootstrap edge confidence

When `bootstrap = TRUE`, a non-parametric bootstrap over rows of `data`
is performed. Each bootstrap replicate runs the same `method`, whitelist
and blacklist; the fraction of replicates in which each edge appears is
recorded as that edge's `confidence` in the returned KG. This gives an
honest uncertainty estimate on the learned structure, useful when the
sample size is modest relative to the number of variables (a common
situation for soil surveys).

## References

Spirtes, P., Glymour, C. and Scheines, R. (2000). *Causation,
Prediction, and Search* (2nd ed.). MIT Press.

Scutari, M. (2010). Learning Bayesian networks with the `bnlearn` R
package. *Journal of Statistical Software* **35**, 1–22.

Colombo, D. and Maathuis, M. H. (2014). Order-independent
constraint-based causal structure learning. *Journal of Machine Learning
Research* **15**, 3741–3782.

Tsamardinos, I., Brown, L. E. and Aliferis, C. F. (2006). The max-min
hill-climbing Bayesian network structure learning algorithm. *Machine
Learning* **65**, 31–78.

## See also

[`causal_kg_new()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_new.md),
[`causal_augment_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_augment_dag.md),
[`causal_kg_to_dagitty()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_to_dagitty.md),
[`causal_kg_to_turtle()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_to_turtle.md).

## Examples

``` r
if (FALSE) { # \dontrun{
  data(br_cerrado)
  kg_learned <- causal_structure_learn(
    br_cerrado,
    variables = c("elev", "slope", "twi", "map_mm", "ndvi", "soc"),
    method    = "hc",
    whitelist = data.frame(from = c("elev", "map_mm"),
                            to   = c("twi",  "soc")),
    bootstrap = TRUE, R_boot = 200L, seed = 1L
  )
  print(kg_learned)
} # }
```
