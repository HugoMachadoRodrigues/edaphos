# Rescale a covariate matrix into `[lower, upper]` column-wise

Utility for preparing a feature matrix for quantum encoding. The
ZZFeatureMap is only expressive when features are on a compact range —
the de-facto convention is `[0, pi]`.

## Usage

``` r
quantum_scale(X, lower = 0, upper = pi)
```

## Arguments

- X:

  Numeric matrix / data frame.

- lower, upper:

  Target interval bounds (default `0` and `pi`).

## Value

Numeric matrix with the same dimensions as `X`, rescaled column-wise –
except for a single-row `X`, which the underlying
[`apply()`](https://rdrr.io/r/base/apply.html) hands back as a plain
named vector.

## Examples

``` r
## A clay sweep at constant pH, in field units. Holding pH fixed
## isolates one covariate, and shows the constant-column rule: a
## column with no spread is sent to the midpoint (lower + upper) / 2.
clay <- seq(12, 58, by = 2)                      # % clay
raw  <- cbind(clay = clay, ph = rep(6.0, length(clay)))
X    <- quantum_scale(raw)
round(apply(X, 2L, range), 4)   # clay -> [0, pi]; pH -> 1.5708 twice
#>        clay     ph
#> [1,] 0.0000 1.5708
#> [2,] 3.1416 1.5708

## Why the rescaling is not cosmetic: the ZZFeatureMap encodes
## covariate i as Rz(2 x_i), so the kernel is PERIODIC in the
## covariate. With a single column the period is exactly pi, and two
## sites pi apart encode to the same state.
quantum_kernel(matrix(c(0.7, 0.7 + pi), ncol = 1L), reps = 2L)[1, 2]
#> [1] 1
#  1 -- not "similar", indistinguishable

## Fed raw, clay spans 46 units = 14.6 periods, and kernel similarity
## stops tracking soil similarity. Row 1 is the 12% clay site;
## columns 2, 12 and 23 are the 14%, 34% and 56% sites.
k_raw <- quantum_kernel(raw, reps = 2L)[1, ]
k_sc  <- quantum_kernel(X,   reps = 2L)[1, ]
rbind(raw    = round(k_raw[c(2, 12, 23)], 4),   # 0.2974 0.9967 0.9871
      scaled = round(k_sc[ c(2, 12, 23)], 4))   # 0.9368 0.0005 0.0033
#>          [,1]   [,2]   [,3]
#> raw    0.2974 0.9967 0.9871
#> scaled 0.9368 0.0005 0.0033

## Raw, it is the 34% and 56% sites that come back near-identical to
## the 12% site while its actual neighbour at 14% does not. Over the
## whole sweep the raw encoding carries no distance information:
c(raw    = round(cor(k_raw, -(clay - 12)), 4),   # 0.0223
  scaled = round(cor(k_sc,  -(clay - 12)), 4))   # 0.5382
#>    raw scaled 
#> 0.0223 0.5382 

## Read 0.5382 as "some", not "all". The ZZ kernel is not a distance
## kernel even on [0, pi] -- it revives at large gaps. Rescaling
## removes the exact aliasing; it does not buy monotonicity.

## TRAP -- the map is refitted from whatever you pass, so scaling a
## validation set on its own puts the same soil at a different angle.
## Carry the CALIBRATION range across instead of calling
## quantum_scale() a second time.
val <- cbind(clay = c(20, 34, 40), ph = rep(6.0, 3))
rng <- range(raw[, "clay"])
round(c(own_map   = unname(quantum_scale(val)[2L, "clay"]),   # 2.1991
        train_map = (34 - rng[1L]) * pi / diff(rng)), 4)      # 1.5025
#>   own_map train_map 
#>    2.1991    1.5025 

## One site scaled on its own is doubly broken: range() has no spread
## so every covariate collapses to pi/2, and apply() drops the result
## to a vector rather than the 1-row matrix.
quantum_scale(val[1L, , drop = FALSE])
#>     clay       ph 
#> 1.570796 1.570796 
```
