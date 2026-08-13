# Check a bundle against the script that produced it

Reads the provenance block written by
[`edaphos_provenance()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_provenance.md)
and reports whether the producing script has changed since the bundle
was built.

## Usage

``` r
edaphos_provenance_check(bundle, root = ".")
```

## Arguments

- bundle:

  Either a path to an `.rds` or an already-loaded list.

- root:

  Package root to resolve the recorded script path against. Defaults to
  the current directory.

## Value

A list with `ok` (logical, or `NA` when the bundle carries no
provenance) and `reason`. `ok = NA` is deliberately not `FALSE`: a
bundle with no block is unbindable rather than stale, and the two want
different remedies.

## See also

[`edaphos_provenance()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_provenance.md)

## Examples

``` r
# A bundle that carries no provenance reports NA, not FALSE.
edaphos_provenance_check(list(a = 1))
#> $ok
#> [1] NA
#> 
#> $reason
#> [1] "no provenance block"
#> 
```
