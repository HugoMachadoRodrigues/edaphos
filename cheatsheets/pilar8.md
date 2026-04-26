# Pilar 8 — Neural Operators (DeepONet / FNO)

Operator-learning over depth-profile function space: the model
takes a covariate vector + a depth grid and returns the entire
profile.  Two architectures:

* **DeepONet** (Lu et al. 2021) — branch (covariates) + trunk
  (depths) with an inner-product readout.
* **FNO** (Li et al. 2021) — Fourier Neural Operator with spectral
  convolution.

## Core API

```r
# DeepONet: branch input is a static covariate vector
fit <- no_deeponet_fit(
  depths     = c(5, 15, 30, 60, 100),    # length n_depths
  targets    = obs_matrix,               # n_obs x n_depths
  covariates = cov_matrix,               # n_obs x p_in
  branch_hidden = 16L, trunk_hidden = 16L,
  output_dim    = 8L, epochs = 300L, lr = 0.02,
  backend = "r"   # or "torch" with autograd
)
pr <- predict(fit, new_cov_matrix, newdepths = c(10, 50))

# FNO: branch input is a depth-dependent cube
cov_dep <- array(my_cov_static, dim = c(n_obs, n_depths, p_in))
fit_fno <- no_fno_fit(
  depths, targets, cov_dep,
  n_modes = 8L, width = 16L, n_blocks = 2L,
  epochs = 300L, lr = 0.01
)
predict(fit_fno, cov_dep_new)
```

## v3.0.0 bridge: `al_query_neural_operator()` (Pilar 8 × Pilar 5)

Ranks pool sites by the disagreement between the NO operator and a
classical Pilar 2 ODE, normalised by NO perturbation-spread
uncertainty.

## Key references

* Lu, Jin, Pang & Zhang (2021) DeepONet.
* Li, Kovachki, Azizzadenesheli, Liu, Bhattacharya, Stuart &
  Anandkumar (2021) FNO.

## See also

* `cheatsheets/pilar5.md` — AL-flavoured P8 query.
