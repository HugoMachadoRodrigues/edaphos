# Benchmark wrapper: Pilar 6 – bootstrap-ensembled quantum KRR

PCA-reduces the covariate matrix to `n_pcs` components rescaled to
`[-pi, pi]`, then trains `n_boot` quantum-kernel ridge regressors on
bootstrap resamples and aggregates their predictions into a predictive
posterior.

## Usage

``` r
benchmark_fit_p6_quantum(
  train,
  test,
  cov_cols,
  n_pcs = 6L,
  reps = 2L,
  lambda = 0.5,
  n_boot = 20L,
  seed = 1L,
  calibrate = TRUE
)
```

## Arguments

- train, test:

  Data frames with `soc` + `cov_cols`.

- cov_cols:

  Character vector of covariate column names.

- n_pcs:

  Integer; number of PCs (= qubits). Default `6L`.

- reps:

  Integer; ZZFeatureMap repetitions. Default `2L`.

- lambda:

  Ridge regulariser. Default `0.5`.

- n_boot:

  Integer; number of bootstrap KRR fits. Default `20L`.

- seed:

  Optional RNG seed.

- calibrate:

  Logical (default `TRUE`). When `TRUE`, residual noise from a full-data
  quantum-KRR fit is injected into every posterior sample (see Pilar-1
  wrapper for the rationale).

## Value

An `edaphos_posterior` with `method = "ensemble"`, `query_type = "map"`.

## Examples

``` r
data(br_cerrado)
set.seed(2)
sub <- br_cerrado[sample(nrow(br_cerrado), 120L), ]
names(sub)[names(sub) == "x"] <- "lon"
names(sub)[names(sub) == "y"] <- "lat"
covs  <- c("elev", "slope", "twi", "map_mm", "ndvi")
train <- sub[1:90, ]; test <- sub[91:120, ]

# `n_pcs` IS the qubit count: the simulator carries a 2^n_pcs state
# vector per site and the Gram matrix needs O(n^2) of them, so keep it
# small.  It also cannot exceed the number of non-constant covariates --
# with these five columns the package default of 6 stops the fit.
try(benchmark_fit_p6_quantum(train, test, covs, n_pcs = 6L, n_boot = 2L))
#> Error : Only 5 non-constant embedding columns; n_pcs=6 requested.

post <- benchmark_fit_p6_quantum(train, test, covs, n_pcs = 4L, reps = 1L,
                                 n_boot = 5L, lambda = 0.5, seed = 1L)
dim(post$samples)                  # 5 bootstrap members x 30 sites
#> [1]  5 30

# Do not read this as a working model.  Against the training mean and
# against OLS on the same five covariates: 7.047 / 7.048 / 4.361.
cal <- uncertainty_calibrate(post, truth = test$soc)
ols <- lm(soc ~ elev + slope + twi + map_mm + ndvi, data = train)
round(c(qkrr = cal$point_rmse,
        null = sqrt(mean((mean(train$soc) - test$soc)^2)),
        ols  = sqrt(mean((predict(ols, test) - test$soc)^2))), 3)
#>  qkrr  null   ols 
#> 7.047 7.048 4.361 

# It ties the null because it has collapsed onto it.  At 4 qubits the
# ZZFeatureMap Gram matrix is nearly the identity (mean off-diagonal
# 0.063), the dual weights explain almost nothing, and predictions fall
# back on the offset that quantum_krr_fit() centres the response with --
# i.e. mean(train$soc).  The predictions vary by 1.75 g/kg where the
# truth varies by 7.13.
pt <- colMeans(post$samples)
red <- qf_embed_reduce(as.matrix(rbind(train[, covs], test[, covs])),
                       n_pcs = 4L)
K <- quantum_kernel(red$X_q[1:90, ], reps = 1L)
round(c(sd_pred = sd(pt), sd_truth = sd(test$soc),
        mean_pred = mean(pt), train_mean = mean(train$soc),
        gram_offdiag = mean(K[upper.tri(K)])), 3)
#>      sd_pred     sd_truth    mean_pred   train_mean gram_offdiag 
#>        1.754        7.130       20.420       19.938        0.063 

# Note which rows went into that PCA: the wrapper reduces
# rbind(train, test) jointly, so the rotation and the [-pi, pi] rescale
# have seen the test covariates.  Fine for a benchmark of the kernel,
# not a clean out-of-sample protocol -- PC1 takes 0.489 of the variance
# jointly against 0.477 on the training rows alone.
round(rbind(joint = red$variance_explained,
            train_only = qf_embed_reduce(as.matrix(train[, covs]),
                                         n_pcs = 4L)$variance_explained), 3)
#>              PC1   PC2   PC3   PC4
#> joint      0.489 0.275 0.169 0.051
#> train_only 0.477 0.276 0.171 0.055

# The interval story is separate, and n_boot bounds it: a 90% interval
# read off 5 members cannot be wider than their range.  More members
# widen it, but they cannot rescue a posterior centred in the wrong
# place -- coverage is still 0.467 at n_boot = 50.
picp <- vapply(c(5L, 20L, 50L), function(nb) {
  p <- benchmark_fit_p6_quantum(train, test, covs, n_pcs = 4L, reps = 1L,
                                n_boot = nb, lambda = 0.5, seed = 1L)
  uncertainty_calibrate(p, truth = test$soc)$picp[["0.90"]]
}, numeric(1))
round(picp, 3)
#> [1] 0.500 0.533 0.667
```
