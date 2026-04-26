# Load an ENVO ontology from a local .obo file

Parses a downloaded Environmental Ontology (ENVO) OBO file via the
optional `ontologyIndex` Suggests dependency and returns a tidy
vocabulary frame. Download ENVO from
<https://obofoundry.org/ontology/envo.html>.

## Usage

``` r
causal_ontology_envo(path)
```

## Arguments

- path:

  Path to an `envo.obo` file.

## Value

A data frame with columns `id`, `term`, `label`.
