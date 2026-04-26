# Ingest an abstract into a pedogenetic Knowledge Graph

Wrapper that calls
[`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md)
on a single passage and then adds every returned claim as an edge of the
supplied `edaphos_causal_kg`. Claims whose `confidence` is below
`min_confidence` are discarded.

## Usage

``` r
causal_llm_ingest_abstract(kg, abstract, source, min_confidence = 0.5, ...)
```

## Arguments

- kg:

  An `edaphos_causal_kg` to update in place.

- abstract:

  Character scalar with the passage to annotate.

- source:

  Character scalar used as the `source` attribute of every added edge (a
  bibliographic key, a DOI, etc.).

- min_confidence:

  Numeric in `[0, 1]`. Claims with `confidence < min_confidence` are
  dropped before insertion.

- ...:

  Forwarded to
  [`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md)
  (`backend`, `model`, `host`, ...).

## Value

The updated `edaphos_causal_kg`. An attribute `"claims"` carries the
tidy data frame that was actually inserted.
