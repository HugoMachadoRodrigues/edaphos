# One-line summary of a Knowledge Graph

Structural and statistical overview of an `edaphos_causal_kg`: node /
edge / source counts, confidence quantiles, DAG-ness and the most
prolific source. Useful as the first thing to print after a large
[`causal_llm_ingest_corpus()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_corpus.md)
run.

## Usage

``` r
# S3 method for class 'edaphos_causal_kg'
summary(object, ...)
```

## Arguments

- object:

  An `edaphos_causal_kg`.

- ...:

  Unused; present for S3 dispatch.

## Value

An `edaphos_causal_kg_summary` list (printed with a custom method)
carrying the raw numbers.
