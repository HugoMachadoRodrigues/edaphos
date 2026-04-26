# Query the AGROVOC SPARQL endpoint

Thin wrapper around the FAO AGROVOC SPARQL endpoint
(<https://agrovoc.fao.org/sparql>). The endpoint is **public and
keyless** and returns RDF/JSON.

## Usage

``` r
causal_ontology_agrovoc(
  query,
  limit = 10L,
  timeout_sec = 60L,
  endpoint = "https://agrovoc.fao.org/sparql"
)
```

## Arguments

- query:

  Character concept label to search for (e.g. `"soil organic carbon"`).
  A `rdfs:label` filter with English language tag is applied.

- limit:

  Integer, max number of matches returned.

- timeout_sec:

  Request timeout (seconds).

- endpoint:

  Override the default AGROVOC SPARQL endpoint URL (mirror / proxy).

## Value

A data frame with columns `uri` (AGROVOC concept URI) and `term`
(canonical lower-snake-case label).

## Examples

``` r
if (FALSE) { # \dontrun{
  causal_ontology_agrovoc("soil organic carbon", limit = 5)
} # }
```
