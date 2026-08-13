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

## Examples

``` r
if (FALSE) { # \dontrun{
  # ENVO is not bundled with edaphos. Download the OBO release from
  # https://obofoundry.org/ontology/envo.html and install the
  # optional `ontologyIndex` package first: without it the function
  # stops rather than falling back to a partial parse.
  envo <- causal_ontology_envo("~/ontologies/envo.obo")
  head(envo)

  # Unlike causal_ontology_cerrado(), every row carries a persistent
  # ENVO id, so an alignment made against it stays traceable to a
  # versioned ontology release.
  subset(envo, grepl("savanna|ferralsol", term))

  # Most ENVO classes have nothing to do with pedometry, and the
  # fuzzy tier will cheerfully map a soil node onto one of them.
  # Filter the vocabulary down first, and leave fuzzy switched off.
  soil_vocab <- envo[grepl("soil|sediment", envo$term), ]
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "clay", "water_retention",
                           source = "Paper A")
  causal_kg_alignment(kg, vocab = soil_vocab,
                      method = c("exact", "substring"))
} # }
```
