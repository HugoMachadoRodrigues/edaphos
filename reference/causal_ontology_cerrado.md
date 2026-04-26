# Canonical Cerrado pedometric vocabulary

Returns a hand-curated data frame of ~60 canonical terms covering the
major drivers of Cerrado soil formation — climate, relief, parent
material, chemistry, vegetation, processes and outcomes. The vocabulary
is a deliberately narrow subset of AGROVOC + ENVO, chosen for coverage
of the topics that actually appear in Brazilian pedology abstracts. It
is the default reference used by
[`causal_kg_alignment()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_alignment.md).

## Usage

``` r
causal_ontology_cerrado()
```

## Value

A data frame with columns `term` and `category`.
