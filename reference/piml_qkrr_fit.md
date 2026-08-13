# Fit a Physics-Informed Quantum Kernel Ridge Regression

Composes
[`piml_quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_quantum_kernel.md)
with the closed-form KRR dual solution \\\boldsymbol{\alpha} = (K +
\lambda I)^{-1} y\\. The returned object carries the training-time
residuals and ODE fit so
[`predict()`](https://rdrr.io/r/stats/predict.html) handles the full
forward pipeline (ODE predict -\> residual -\> PI kernel row -\> dual
sum).

## Usage

``` r
piml_qkrr_fit(
  X,
  y,
  depths,
  ode_fit,
  alpha = 0.7,
  sigma = NULL,
  reps = 2L,
  lambda = 0.1,
  backend = c("rcpp", "r")
)
```

## Arguments

- X, y, depths, ode_fit, alpha, sigma, reps, backend:

  See
  [`piml_quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_quantum_kernel.md).

- lambda:

  Ridge regulariser; positive.

## Value

An `edaphos_piml_qkrr` fit.

## Examples

``` r
# br_cerrado ships 0-5 cm only, so extend each site downwards with
# the closed form of the Pillar-2 ODE at mu = 0, giving every site
# its own decay rate: wetter hollows (high TWI) keep carbon deeper.
# The physics is therefore exactly right by construction, which
# FLATTERS the residual half of the kernel.
data(br_cerrado)
set.seed(4)
sit <- br_cerrado[sample(nrow(br_cerrado), 16L), ]
zh  <- c(5, 15, 30, 60, 100)
g   <- expand.grid(h = seq_along(zh), s = seq_len(16L))
z   <- zh[g$h]
lam <- 0.010 + 0.030 * (1 - (sit$twi - min(sit$twi)) / diff(range(sit$twi)))
soc <- 6 + (sit$soc[g$s] - 6) * exp(-lam[g$s] * z) +
  stats::rnorm(80L, sd = 1)
Xa <- quantum_scale(cbind(twi = sit$twi[g$s], ndvi = sit$ndvi[g$s],
                          elev = sit$elev[g$s], depth = z))

set.seed(5)
tr <- sample(80L, 55L)
te <- setdiff(seq_len(80L), tr)
mean_prof <- vapply(zh, function(zz)
  mean(soc[z == zz & seq_len(80L) %in% tr]), 0)
ref <- piml_profile_fit(zh, mean_prof)

qk <- piml_qkrr_fit(Xa[tr, ], soc[tr], z[tr], ref, alpha = 0.7,
                    lambda = 0.1)
qk
#> <edaphos_piml_qkrr>  (Pilar 2 x Pilar 6 bridge)
#>   n_qubits = 4   reps = 2   lambda = 0.1
#>   alpha    = 0.70  (quantum weight; 1-alpha on physics)
#>   sigma    = 1.75  (residual RBF bandwidth)
#>   n_train  = 55   training RMSE = 0.8582

# Score every claim on the same held-out 25 horizons, with a
# baseline and an RBF on the SAME features in the same table. The
# quantum kernel improves on predicting the training mean by 1%;
# the RBF is 4x better than either. `pi_quantum` --- the honest use
# of this fit, with no test y to hand --- is worse than the
# baseline, and the reference ODE on its own beats the whole
# bridge, leaky variant included.
rmse <- function(a, b) sqrt(mean((a - b)^2))
p_def  <- stats::predict(qk, Xa[te, ], newdepths = z[te])
p_leak <- stats::predict(qk, Xa[te, ], newdepths = z[te], newy = soc[te])
qk1 <- piml_qkrr_fit(Xa[tr, ], soc[tr], z[tr], ref, alpha = 1,
                     lambda = 0.1)
p_q <- stats::predict(qk1, Xa[te, ], newdepths = z[te])
sqd <- function(A, B) outer(rowSums(A^2), rowSums(B^2), "+") - 2 * A %*% t(B)
ell <- stats::median(sqrt(pmax(sqd(Xa[tr, ], Xa[tr, ]), 0)))
Ktr <- exp(-sqd(Xa[tr, ], Xa[tr, ]) / (2 * ell^2))
Kte <- exp(-sqd(Xa[te, ], Xa[tr, ]) / (2 * ell^2))
p_rbf <- as.numeric(Kte %*% solve(Ktr + 0.1 * diag(55L), soc[tr]))
round(c(train_mean    = rmse(soc[te], mean(soc[tr])),      # 4.7919
        ode_only      = rmse(soc[te],
                             stats::predict(ref, newdepths = z[te])),
        quantum       = rmse(soc[te], p_q),                # 4.7456
        pi_quantum    = rmse(soc[te], p_def),              # 5.5793
        rbf_krr       = rmse(soc[te], p_rbf),              # 1.1869
        pi_with_truth = rmse(soc[te], p_leak)), 4)         # 3.5720
#>    train_mean      ode_only       quantum    pi_quantum       rbf_krr 
#>        4.7919        3.4764        4.7456        5.7098        1.1869 
#> pi_with_truth 
#>        3.6269 

# Training RMSE would have told the opposite story: the quantum fit
# interpolates its 55 training points to 0.88 g/kg and then lands
# within 1% of the training mean out of sample.
round(c(train = qk1$rmse, test = rmse(soc[te], p_q)), 4)
#>  train   test 
#> 0.8783 4.7456 

# Not a ridge artefact --- the ordering survives three lambdas.
for (lb in c(0.01, 0.1, 1)) {
  q  <- piml_qkrr_fit(Xa[tr, ], soc[tr], z[tr], ref, alpha = 1,
                      lambda = lb)
  pq <- stats::predict(q, Xa[te, ], newdepths = z[te])
  pr <- as.numeric(Kte %*% solve(Ktr + lb * diag(55L), soc[tr]))
  cat(sprintf("lambda %-5g quantum %.3f  rbf %.3f\n", lb,
              rmse(soc[te], pq), rmse(soc[te], pr)))
}
#> lambda 0.01  quantum 4.764  rbf 1.268
#> lambda 0.1   quantum 4.746  rbf 1.187
#> lambda 1     quantum 6.034  rbf 2.780

# Why `pi_with_truth` looks good: the physics half needs e_i = y_i -
# ODE(z_i), i.e. the response at the site you are predicting. That is
# the thing you do not have. Its absence is not signalled --- the
# default `newy` silently substitutes the training mean, so the
# physics block degenerates into a function of depth alone:
identical(p_def, stats::predict(qk, Xa[te, ], newdepths = z[te],
                                newy = rep(mean(soc[tr]), 25L)))
#> [1] TRUE

# TRAP, sharper. Omit `newdepths` as well and predict() takes the
# first nrow(newdata) TRAINING depths, in training-row order. No
# error, no warning, silently misaligned depths:
round(rmse(soc[te], stats::predict(qk, Xa[te, ])), 4)
#> [1] 4.3063
rbind(used = qk$depths[1:6], actual = z[te][1:6])
#>        [,1] [,2] [,3] [,4] [,5] [,6]
#> used      5   15  100    5    5   60
#> actual   15   60  100   15   60    5
```
