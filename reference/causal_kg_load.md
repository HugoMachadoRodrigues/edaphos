# Load a Knowledge Graph from disk

Reads a `.rds` file previously written by
[`causal_kg_save()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_save.md)
and reconstructs the `edaphos_causal_kg`. The reconstruction is careful:
it re-calls
[`causal_kg_add_edge()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_add_edge.md)
for every saved edge so that the duplicate-edge merge + cycle check +
normalisation rules stay consistent with a freshly-built graph.

## Usage

``` r
causal_kg_load(path)
```

## Arguments

- path:

  Path to the `.rds` file.

## Value

An `edaphos_causal_kg`.
