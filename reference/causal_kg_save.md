# Save a Knowledge Graph to disk

Writes an `edaphos_causal_kg` to an `.rds` file. The KG is serialised
through its tidy edge list plus metadata (version, timestamp, R and
package versions) rather than through the raw igraph object, so the file
is:

## Usage

``` r
causal_kg_save(kg, path)
```

## Arguments

- kg:

  An `edaphos_causal_kg`.

- path:

  Path to the target `.rds` file. The parent directory is created if it
  does not exist.

## Value

Invisibly returns `path` (for pipelining).

## Details

- **Portable** across igraph versions (the C-level pointer layout that
  `saveRDS(igraph_object)` would capture is not written).

- **Deterministic** (no hash-randomised attributes), so two saves of the
  same KG produce byte-identical files.

- **Small** — only the edge list and node names are written, not
  igraph's internal indices.

Load with
[`causal_kg_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_load.md).

## See also

[`causal_kg_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_load.md),
[`causal_kg_to_turtle()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_to_turtle.md)
for the human-readable RDF variant.

## Examples

``` r
# \donttest{
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "precipitation", "soc",
                            source = "Jenny 1941",
                            confidence = 0.9)
  f <- tempfile(fileext = ".rds")
  causal_kg_save(kg, f)
  kg2 <- causal_kg_load(f)
  identical(causal_kg_edges(kg), causal_kg_edges(kg2))
#> [1] TRUE
# }
```
