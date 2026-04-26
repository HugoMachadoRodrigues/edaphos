# Align Knowledge-Graph node labels to a canonical vocabulary

Computes the mapping from node labels currently present in an
`edaphos_causal_kg` onto their canonical counterparts in a target
vocabulary
([`causal_ontology_cerrado()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_cerrado.md)
by default). Three matchers are tried in order — exact, substring, fuzzy
— and the first hit wins. The mapping is returned as a tidy data frame;
apply it with
[`causal_kg_rename()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_rename.md).

## Usage

``` r
causal_kg_alignment(
  kg,
  vocab = NULL,
  method = c("exact", "substring", "fuzzy"),
  max_distance = 4L,
  agrovoc_cache = NULL,
  agrovoc_batch = FALSE,
  agrovoc_max_active = 5L
)
```

## Arguments

- kg:

  An `edaphos_causal_kg`.

- vocab:

  Either a character vector / data frame of canonical terms, the string
  `"cerrado"` (default; uses
  [`causal_ontology_cerrado()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_cerrado.md))
  or the string `"agrovoc"` which triggers a **live SPARQL query** to
  the FAO AGROVOC endpoint via
  [`causal_ontology_agrovoc_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align.md).
  For AGROVOC the alignment type is reported as `"agrovoc"` instead of
  exact / substring / fuzzy.

- method:

  Which matcher tier(s) to enable (ignored when `vocab = "agrovoc"`).
  Any combination of `"exact"`, `"substring"`, `"fuzzy"`.

- max_distance:

  Fuzzy-matcher Levenshtein cap.

- agrovoc_cache:

  Optional `.rds` path used by `vocab = "agrovoc"` to avoid re-querying
  the same terms.

- agrovoc_batch:

  Logical — when `TRUE` and `vocab = "agrovoc"`, uses the
  parallel-dispatch variant
  [`causal_ontology_agrovoc_align_batch()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align_batch.md)
  to resolve all nodes in flight. Recommended for KGs with more than ~20
  unique nodes.

- agrovoc_max_active:

  Integer — concurrency for the parallel variant. Only consulted when
  `agrovoc_batch = TRUE`.

## Value

A data frame with columns `original`, `canonical`, `method`, `distance`.
When `vocab = "agrovoc"` an extra `uri` column is attached.
