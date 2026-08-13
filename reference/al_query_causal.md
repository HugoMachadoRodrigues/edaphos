# Causal Active Learning: query the next sample(s) that most reduce the uncertainty of a targeted causal effect

Closes the loop between Pillar 1 (causal identification via backdoor
adjustment) and Pillar 5 (autonomous active learning): instead of
choosing candidates by marginal-Y uncertainty (classical AL), we choose
by expected shrinkage of `Var(beta_hat_{X->Y})`.

## Usage

``` r
al_query_causal(
  data,
  pool,
  dag,
  exposure,
  outcome,
  adjustment = NULL,
  n_select = 5L,
  strategy = c("leverage", "bootstrap"),
  B = 200L,
  seed = NULL
)
```

## Arguments

- data:

  Data frame with the exposure, outcome and adjustment columns (the
  current labelled set).

- pool:

  Data frame with the same columns as `data`; the unlabelled candidate
  pool to query.

- dag:

  A `dagitty` DAG.

- exposure, outcome:

  Character; column names of the causal query.

- adjustment:

  Optional character vector of adjustment-set columns. Inferred from
  `dag` via
  [`causal_adjustment_set()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_adjustment_set.md)
  when `NULL`.

- n_select:

  Integer; how many candidates to return. Default `5L`.

- strategy:

  One of `"leverage"` (hat-matrix diagonal, closed-form, fast,
  deterministic) or `"bootstrap"` (re-bootstrap `Var(beta_hat)` once per
  candidate). `"bootstrap"` costs `B * (|pool| + 1)` OLS fits and its
  ranking is a Monte-Carlo estimate: at `B = 100` on 80 sites the
  ordering of five candidates changes with `seed` (see the examples), so
  raise `B` until the ordering stabilises before reading anything into
  it.

- B:

  Bootstrap replications when `strategy = "bootstrap"`.

- seed:

  RNG seed for bootstrap reproducibility.

## Value

A data frame with one row per candidate, columns `pool_index`,
`leverage`, `expected_var_reduction`, sorted by descending expected
reduction. The top-`n_select` rows are the recommended next samples.

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE)) {
  # 80 labelled sites, 200 unlabelled candidates. The question is not
  # "where is SOC uncertain?" but "how hard does rainfall push SOC?".
  set.seed(11)
  i_d  <- sample(nrow(br_cerrado), 80)
  cols <- c("map_mm", "elev", "twi", "ndvi", "soc")
  dat  <- br_cerrado[i_d, cols]
  pool <- br_cerrado[-i_d, cols][1:200, ]

  # On 80 sites the effect is not distinguishable from zero (t = 0.79).
  # That is the situation this bridge exists for. (Inside a guarded
  # block nothing auto-prints, hence the explicit print() calls.)
  cf <- summary(stats::lm(soc ~ map_mm + elev + ndvi, dat))$coefficients
  print(round(cf["map_mm", c("Estimate", "Std. Error", "t value")], 5))

  dag <- dagitty::dagitty(
    "dag { elev -> map_mm ; elev -> soc ; twi -> soc ;
           map_mm -> ndvi ; map_mm -> soc ; ndvi -> soc }")
  q <- al_query_causal(dat, pool, dag, exposure = "map_mm",
                       outcome = "soc", n_select = 5L)
  print(q)

  # The set is inferred for the DIRECT effect, so the mediator ndvi is
  # in it while twi, which opens no backdoor path, is not.
  print(attr(q, "adjustment"))

  # Row names are inherited from `pool`, `pool_index` is the position
  # in it. Use the column; as.integer(rownames(q)) is a different row.
  print(c(rowname     = rownames(q)[1],
          pool_index  = q$pool_index[1],
          resolves_to = rownames(pool)[q$pool_index[1]]))

  # Leverage is a property of the design matrix alone: blank out every
  # outcome in the pool and the ranking does not move one place.
  pool_na <- pool; pool_na$soc <- NA_real_
  print(identical(q$pool_index,
                  al_query_causal(dat, pool_na, dag, exposure = "map_mm",
                                  outcome = "soc")$pool_index))   # TRUE

  # And it is JOINT, not marginal. Row 187 sits at the 40th percentile
  # of the exposure yet ranks 4th, on the strength of being at the 6th
  # percentile of elev and the maximum of ndvi.
  top <- utils::head(q$pool_index, 5)
  pct <- function(cc, i) round(100 * mean(pool[[cc]] <= pool[[cc]][i]))
  print(t(sapply(top, function(i)
    c(row = i, map_mm = pct("map_mm", i), elev = pct("elev", i),
      ndvi = pct("ndvi", i)))))

  # Classical Pillar 5 asks a different question of the same pool and
  # gets a disjoint answer: 0 of its 5 picks are in the causal top 5.
  set.seed(3)
  m <- al_fit(dat, target = "soc",
              covariates = c("map_mm", "elev", "twi", "ndvi"), seed = 3)
  print(length(intersect(top, al_query(m, pool, n = 5,
                                       strategy = "uncertainty"))))

  # `expected_var_reduction` is h / (1 + h), a monotone relabelling of
  # `leverage`: under strategy = "leverage" the two columns always
  # rank identically, and neither is a variance in the units of beta.
  print(stats::cor(rank(q$leverage), rank(q$expected_var_reduction)))

  # strategy = "bootstrap" re-bootstraps Var(beta_hat) once per
  # candidate. At B = 100 the answer is Monte-Carlo noise: three seeds
  # give three orderings of the same five candidates, none of them the
  # closed-form one. Raise B until the ordering stops moving.
  ord <- function(s) al_query_causal(dat, pool[1:5, ], dag,
                                     exposure = "map_mm",
                                     outcome  = "soc",
                                     strategy = "bootstrap",
                                     B = 100L, seed = s)$pool_index
  print(rbind(seed1 = ord(1), seed2 = ord(2), seed3 = ord(3),
              leverage = al_query_causal(dat, pool[1:5, ], dag,
                                         exposure = "map_mm",
                                         outcome  = "soc")$pool_index))
}
#>   Estimate Std. Error    t value 
#>    0.00230    0.00291    0.79033 
#> <edaphos_causal_al_query>  (Pilar 1 x Pilar 5 bridge)
#>   target effect : map_mm -> soc
#>   adjustment    : elev, ndvi
#>   strategy      : leverage
#>   n_select      : 5
#>   top-5 candidates:
#>     pool_index  leverage expected_var_reduction
#> 136        128 0.2223619              0.1819117
#> 44          41 0.1854640              0.1564484
#> 1            1 0.1467496              0.1279700
#> 198        187 0.1457032              0.1271736
#> 87          82 0.1362830              0.1199376
#> [1] "elev" "ndvi"
#>     rowname  pool_index resolves_to 
#>       "136"       "128"       "136" 
#> [1] TRUE
#>      row map_mm elev ndvi
#> [1,] 128      2   46   99
#> [2,]  41     99   28  100
#> [3,]   1      6   61   96
#> [4,] 187     40    6  100
#> [5,]  82     96   24   24
#> [1] 0
#> [1] 1
#>          [,1] [,2] [,3] [,4] [,5]
#> seed1       1    4    2    5    3
#> seed2       3    4    2    1    5
#> seed3       4    2    1    3    5
#> leverage    1    2    4    3    5
```
