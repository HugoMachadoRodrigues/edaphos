# Fit the Pillar 2 profile model to a group of pedons independently

Convenience wrapper that calls
[`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)
separately on each pedon in a long-format data frame, returning a list
of fits keyed by `id`. This is the baseline against which a future
pooled (covariate-conditioned) PIML model will be compared.

## Usage

``` r
piml_profile_fit_group(data, id, depth, value, ...)
```

## Arguments

- data:

  Data frame in long form with one row per horizon.

- id:

  Character, name of the column identifying each pedon.

- depth:

  Character, name of the column with horizon mid-depths.

- value:

  Character, name of the column with observed values.

- ...:

  Forwarded to
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md).

## Value

A named list of `edaphos_piml_profile` fits.

## Examples

``` r
data(br_cerrado)

# Five pedons generated FROM the model, so the parameters the fit
# has to recover are known.  The closed form of
# dy/dz = -lambda0 exp(-mu z) (y - y_inf) is
#   y(z) = y_inf + (y0 - y_inf) exp(-(lambda0/mu)(1 - exp(-mu z)))
# and here surface SOC and the decay rate come from each Cerrado
# site's own soc and twi.
sites  <- br_cerrado[c(1, 400, 900, 1400, 1900), ]
depths <- c(5, 15, 30, 60, 100)
set.seed(42)
pedons <- do.call(rbind, lapply(1:5, function(i) {
  y0    <- sites$soc[i]                 # topsoil SOC, g/kg
  y_inf <- 0.30 * y0                    # parent material
  lam0  <- 0.02 + 0.004 * sites$twi[i]
  data.frame(
    pedon = c("P1", "P2", "P3", "P4", "P10")[i],
    depth = depths,
    soc   = y_inf + (y0 - y_inf) *
            exp(-(lam0 / 0.02) * (1 - exp(-0.02 * depths))) +
            rnorm(5, 0, 0.3),           # 0.3 g/kg of lab noise
    yinf_true = y_inf)
}))

fits <- piml_profile_fit_group(pedons, "pedon", "depth", "soc")

# The list is keyed by split(), which orders the ids as CHARACTERS.
# fits[[2]] is pedon "P10", not the second pedon of the data frame.
names(fits)
#> [1] "P1"  "P10" "P2"  "P3"  "P4" 
unique(pedons$pedon)
#> [1] "P1"  "P2"  "P3"  "P4"  "P10"

# Every pedon is fitted on its own, four parameters to five points,
# so a good rmse is cheap.  Read it next to the recovered asymptote:
# each profile is reproduced down to the 0.3 g/kg noise floor and
# `converged` is TRUE everywhere, while y_inf -- which describes the
# profile BELOW the deepest horizon and is constrained by no
# observation -- comes back between 0.35 and 1.27 times the truth.
truth <- unique(pedons[, c("pedon", "yinf_true")])
tab <- data.frame(
  rmse      = round(vapply(fits, function(f) f$rmse, 0), 3),
  converged = vapply(fits, function(f) f$converged, TRUE),
  yinf_hat  = round(vapply(fits, function(f) f$params$y_inf, 0), 2),
  yinf_true = round(truth$yinf_true[match(names(fits), truth$pedon)], 2))
tab
#>      rmse converged yinf_hat yinf_true
#> P1  0.119      TRUE     8.06      8.30
#> P10 0.034      TRUE     5.72      5.01
#> P2  0.257      TRUE     6.10      6.68
#> P3  0.274      TRUE     5.27      4.43
#> P4  0.305      TRUE     6.40      5.24
round(range(tab$yinf_hat / tab$yinf_true), 2)
#> [1] 0.91 1.22

# A pedon with a single horizon cannot be fitted (four parameters,
# one observation).  The wrapper warns and keeps a NULL in that
# slot rather than dropping it, so downstream code has to test.
two <- rbind(pedons[pedons$pedon %in% c("P1", "P2"),
                    c("pedon", "depth", "soc")],
             data.frame(pedon = "P99", depth = 5, soc = 21))
f2 <- piml_profile_fit_group(two, "pedon", "depth", "soc")
#> Warning: Pedon 'P99' failed: length(depths) >= 2L is not TRUE
vapply(f2, is.null, TRUE)
#>    P1    P2   P99 
#> FALSE FALSE  TRUE 

# `...` reaches piml_profile_fit(), but there is one `...` for the
# whole group: y_surface = 30 pins EVERY surface at 30 g/kg, above
# the true surface of all five pedons, and the misfit grows by up
# to nineteenfold.  Per-pedon surface values need a loop over
# piml_profile_fit(), not this wrapper.
round(range(sites$soc), 1)
#> [1] 14.8 27.6
fixed <- piml_profile_fit_group(pedons, "pedon", "depth", "soc",
                                y_surface = 30)
vapply(fixed, function(f) f$params$y0, 0)
#>  P1 P10  P2  P3  P4 
#>  30  30  30  30  30 
r_free  <- vapply(fits,  function(f) f$rmse, 0)
r_fixed <- vapply(fixed, function(f) f$rmse, 0)
round(rbind(free = r_free, fixed = r_fixed,
            ratio = r_fixed / r_free), 2)
#>         P1   P10   P2   P3   P4
#> free  0.12  0.03 0.26 0.27 0.31
#> fixed 0.26  0.64 1.25 1.54 1.24
#> ratio 2.21 19.12 4.88 5.63 4.05
```
