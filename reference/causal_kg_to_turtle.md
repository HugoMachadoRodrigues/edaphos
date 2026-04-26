# Export a Knowledge Graph to RDF 1.1 Turtle

Serialises an `edaphos_causal_kg` as **RDF 1.1 Turtle**
(<https://www.w3.org/TR/turtle/>), the W3C's canonical human-readable
triple language. Each edge becomes a reified `rdf:Statement` so
confidence, evidence, source and timestamp are preserved losslessly;
each node is given a stable IRI inside a user-controlled namespace. The
emitter is written in pure R with no external dependency — the output is
guaranteed parseable by any RDF 1.1-conformant consumer (rdflib, Jena,
Virtuoso, Blazegraph, GraphDB, Oxigraph …).

## Usage

``` r
causal_kg_to_turtle(
  kg,
  path = NULL,
  base_uri = "https://edaphos.io/kg/",
  schema_uri = "https://edaphos.io/schema#",
  namespaces = character(0),
  include_metadata = TRUE
)
```

## Arguments

- kg:

  An `edaphos_causal_kg`.

- path:

  Optional output file path. When `NULL` (default), the Turtle document
  is returned as a single character string.

- base_uri:

  Character — base IRI for the KG. Must end with `"/"` or `"#"`. Default
  `"https://edaphos.io/kg/"`.

- schema_uri:

  Character — IRI of the `eds:` schema namespace. Default
  `"https://edaphos.io/schema#"`.

- namespaces:

  Named character vector of extra prefix bindings to declare. Useful
  when you want to reference external vocabularies (e.g.
  `c(agrovoc = "http://aims.fao.org/aos/agrovoc/")`).

- include_metadata:

  Logical — emit document-level metadata (creation time, `edaphos`
  version) as `prov:` statements. Default `TRUE`.

## Value

When `path` is `NULL`, invisibly returns the Turtle document as a
length-1 character vector. When `path` is given, writes the document to
disk and invisibly returns `path`.

## Details

The emitted graph uses the following prefixes by default (all
overridable via `namespaces`):

- `ed:` — edaphos KG namespace (one IRI per node and edge).

- `eds:` — edaphos schema namespace (defines `eds:Causes`,
  `eds:confidence`, `eds:evidence`, `eds:source`).

- `rdf:`, `rdfs:`, `xsd:`, `prov:`, `dct:` — standard W3C vocabularies.

Every node `L` becomes an IRI `<base_uri>node/<sanitised_L>`; every edge
becomes an IRI `<base_uri>edge/<cause>__<effect>` typed as
`rdf:Statement`, with `rdf:subject` / `rdf:predicate` / `rdf:object`
pointing at the nodes and `eds:Causes` used as the predicate for the
causal direction. Provenance is attached via `dct:source` (bibliographic
identifier) and `prov:generatedAtTime` (timestamp).

## References

Beckett, D. (2014). RDF 1.1 Turtle — Terse RDF Triple Language. *W3C
Recommendation*.

## See also

[`causal_kg_save()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_save.md)
for binary RDS persistence.

## Examples

``` r
# \donttest{
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "precipitation", "soc",
                            source = "Jenny 1941",
                            evidence = "Higher precipitation favours SOC.",
                            confidence = 0.9)
  ttl <- causal_kg_to_turtle(kg)
  substr(ttl, 1, 200)
#> [1] "@prefix ed: <https://edaphos.io/kg/node/> .\n@prefix edge: <https://edaphos.io/kg/edge/> .\n@prefix eds: <https://edaphos.io/schema#> .\n@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .\n@pre"

  # Write to disk and (optionally) round-trip through rdflib if
  # installed -- a useful SPARQL-queryable artefact.
  tf <- tempfile(fileext = ".ttl")
  causal_kg_to_turtle(kg, tf)
# }
```
