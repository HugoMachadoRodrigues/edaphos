# Spatially blocked cross-validation folds with a buffer

Assigns rows to `k` spatial blocks by k-means on the coordinates, then,
for each fold, drops training rows that lie within `buffer_km`
great-circle distance of any test row.

## Usage

``` r
spatial_block_folds(coords, k = 5L, buffer_km = 68, seed = NULL)
```

## Arguments

- coords:

  Two-column numeric matrix or data frame of longitude and latitude, in
  that order, in degrees.

- k:

  Number of folds.

- buffer_km:

  Width of the dead zone in kilometres. Training rows closer than this
  to any test row are excluded from that fold. The default, 68 km, is
  the largest identified variogram range among the depth-function
  parameters fitted to Cerrado WoSIS profiles; reproduce it with
  `data-raw/piml_parameter_variograms.R`. Set `0` to reproduce the
  unbuffered behaviour, which is what earlier versions did implicitly.

- seed:

  Optional integer seed for the k-means start.

## Value

An `edaphos_spatial_folds` object: a list with `fold` (an integer vector
of block assignments), `train` and `test` (lists of row-index vectors,
one per fold), `n_buffered` (rows removed per fold), `min_dist_km` (the
realised minimum training-to-test distance per fold, which should be at
least `buffer_km`), `min_dist_km_unbuffered` (the same distance the
unbuffered split would have allowed, so the buffer's effect can be
quoted rather than asserted), and the settings.

## References

Roberts DR, Bahn V, Ciuti S, et al. (2017). Cross-validation strategies
for data with temporal, spatial, hierarchical, or phylogenetic
structure. *Ecography* 40:913-929.
[doi:10.1111/ecog.02881](https://doi.org/10.1111/ecog.02881)

## Examples

``` r
data(br_cerrado)
xy <- br_cerrado[seq(1, nrow(br_cerrado), by = 20), c("x", "y")]

# Scale the buffer to the data. `br_cerrado` is a 0.3-degree demonstration
# grid whose widest separation is about 47 km, so the 68 km default -- set
# for the Cerrado-wide WoSIS extract -- would empty a fold, and the function
# says so rather than returning one silently.
try(spatial_block_folds(xy, k = 5, buffer_km = 68, seed = 1))
#> Error : buffer_km = 68 leaves fewer than two training rows in at least one fold. Reduce the buffer or the number of folds.

# Without a buffer, the nearest training neighbour of a test row can be
# arbitrarily close to it.
f0 <- spatial_block_folds(xy, k = 5, buffer_km = 0, seed = 1)
round(min(f0$min_dist_km), 2)
#> [1] 3.03

# With one, no training row is closer than the buffer, and the cost in
# discarded training data is reported rather than hidden.
f1 <- spatial_block_folds(xy, k = 5, buffer_km = 10, seed = 1)
round(min(f1$min_dist_km), 2)
#> [1] 10.73
f1$n_buffered
#> [1] 24 25 27 28 41
f1
#> <edaphos_spatial_folds>
#>   102 rows, 5 blocks, buffer 10 km
#>   test rows per fold : 16, 19, 23, 25, 19
#>   training rows kept : 62, 58, 52, 49, 42
#>   discarded to buffer: 24, 25, 27, 28, 41 (28.4% of all rows)
#>   realised min train-test distance: 10.7 km
```
