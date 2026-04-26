# Add a causal edge to a pedogenetic Knowledge Graph

Add a causal edge to a pedogenetic Knowledge Graph

## Usage

``` r
causal_kg_add_edge(
  kg,
  cause,
  effect,
  source = NA_character_,
  evidence = NA_character_,
  confidence = 1,
  timestamp = NULL
)
```

## Arguments

- kg:

  An `edaphos_causal_kg` returned by
  [`causal_kg_new()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_new.md).

- cause, effect:

  Character scalar — the causal exposure and the outcome node. Node
  names are normalised to lower-snake-case.

- source:

  Character scalar with a bibliographic key or human description of the
  evidence source (e.g. `"Jenny 1941"`, `"Minasny et al. 2017"`).

- evidence:

  Character scalar with a short quotation supporting the claim (max ~200
  characters recommended).

- confidence:

  Numeric in `[0, 1]` — the LLM's or annotator's confidence that the
  claim is supported by the evidence.

- timestamp:

  Character ISO 8601 timestamp. Defaults to
  [`Sys.time()`](https://rdrr.io/r/base/Sys.time.html).

## Value

The updated `edaphos_causal_kg`.
