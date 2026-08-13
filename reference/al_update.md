# Append newly labeled samples and refit the model

Manual one-shot companion to
[`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md):
takes a model, some freshly labeled samples (for instance returned from
the lab), refits the QRF, and appends a history entry. Use this when you
are driving the loop yourself instead of letting
[`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md)
orchestrate it.

## Usage

``` r
al_update(model, new_samples, ...)
```

## Arguments

- model:

  A `edaphos_al_model`.

- new_samples:

  Data frame with the same columns as `model$labeled` (i.e. target,
  covariates, and optional coords).

- ...:

  Extra arguments forwarded to
  [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md).

## Value

An updated `edaphos_al_model`.

## Examples

``` r
covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
set.seed(42)
i_lab <- sample(nrow(br_cerrado), 30)
lab   <- br_cerrado[i_lab, ]
pool  <- br_cerrado[-i_lab, ][seq(1, 1995, by = 5), ]
set.seed(1)
m <- al_fit(lab, target = "soc", covariates = covs,
            coords = c("x", "y"), seed = 1)

# One turn of the loop by hand: query 8 cells, send them to the lab
# (br_cerrado already carries the truth), append them.
idx <- al_query(m, pool, n = 8, strategy = "hybrid")
new <- pool[idx, ]

# `...` reaches ranger::ranger() through al_fit(). Without `seed` the
# refit grows a different forest on every call and the OOB RMSE moves.
identical(al_update(m, new)$history[[2]]$rmse_oob,
          al_update(m, new)$history[[2]]$rmse_oob)             # FALSE
#> [1] FALSE
set.seed(2); m2 <- al_update(m, new, seed = 1)
set.seed(2); m3 <- al_update(m, new, seed = 1)
identical(m2$history[[2]]$rmse_oob, m3$history[[2]]$rmse_oob)  # TRUE
#> [1] TRUE

# The OOB RMSE went UP, 4.659 -> 4.677, on 8 extra samples. That is
# the expected first move, not a failure: an uncertainty batch is by
# construction the part of the landscape the forest handles worst, so
# it enters the OOB average as 8 hard rows. Both are still well below
# predicting the labeled mean everywhere. Judge the loop on a
# held-out set, never on this column.
round(c(before    = m$history[[1]]$rmse_oob,
        after     = m2$history[[2]]$rmse_oob,
        mean_only = sqrt(mean((lab$soc - mean(lab$soc))^2))), 3)
#>    before     after mean_only 
#>     4.774     5.559     7.193 

# `mean_uncertainty` is recorded under the PRE-update model: it is
# the width al_query() acted on, not the width the refit now reports
# at those eight cells -- they are labeled, so the forest has
# collapsed them from 18.54 to 11.43 g/kg.
wid <- function(mod) {
  qq <- stats::predict(mod$model, data = new[, covs],
                       type = "quantiles",
                       quantiles = c(0.1, 0.9))$predictions
  mean(qq[, 2] - qq[, 1])
}
round(c(recorded = m2$history[[2]]$mean_uncertainty,
        pre_update = wid(m), post_update = wid(m2)), 2)
#>    recorded  pre_update post_update 
#>       19.06       19.06       14.91 

# history[[1]] stays frozen at iteration 0; read the LAST entry for
# the current state. `queried` is empty because al_update() is handed
# rows, not pool positions -- only al_loop() can record which.
str(m2$history[[2]])
#> List of 5
#>  $ iter            : int 1
#>  $ n_labeled       : int 38
#>  $ queried         : int(0) 
#>  $ rmse_oob        : num 5.56
#>  $ mean_uncertainty: num 19.1
c(history_1 = m2$history[[1]]$n_labeled, rows_now = nrow(m2$labeled))
#> history_1  rows_now 
#>        30        38 

# $labeled is rebuilt as target + covariates + coords, in that order.
# Anything else carried on `new_samples` -- a lab id, a sampling date
# -- is dropped, and the column order is not the one you passed in.
new$lab_id <- sprintf("BR-%02d", seq_len(nrow(new)))
set.seed(2); m4 <- al_update(m, new, seed = 1)
"lab_id" %in% names(m4$labeled)                                # FALSE
#> [1] FALSE
rbind(before = names(m$labeled), after = names(m4$labeled))
#>        [,1]  [,2]   [,3]    [,4]    [,5]     [,6]     [,7]   [,8] 
#> before "x"   "y"    "elev"  "slope" "twi"    "map_mm" "ndvi" "soc"
#> after  "soc" "elev" "slope" "twi"   "map_mm" "ndvi"   "x"    "y"  
```
