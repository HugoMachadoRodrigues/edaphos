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

## Examples

``` r
if (requireNamespace("igraph", quietly = TRUE)) {
  # Node labels the way an LLM extractor really emits them: typos,
  # plurals, US spellings, over-specific compounds.
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "precipitaton", "soc", source = "A")
  kg <- causal_kg_add_edge(kg, "aluminum", "root_biomass",
                           source = "B")
  kg <- causal_kg_add_edge(kg, "steeper_slopes", "erosion",
                           source = "C")
  kg <- causal_kg_add_edge(kg, "microbial_biomass", "decomposition",
                           source = "D")

  print(causal_kg_alignment(kg))

  # Two things to read off that table.
  #
  # `steeper_slopes` stays unmatched. The substring tier only matches
  # whole underscore-separated tokens, so the plural "slopes" misses
  # "slope", and the nearest vocabulary term is 8 edits away, past
  # the default max_distance = 4.
  #
  # `microbial_biomass` is folded into `biomass` by the substring
  # tier, silently merging two different carbon pools. Substring
  # matching is lossy; drop the tier when you would rather see a
  # node come back unmatched than wrongly matched.
  print(causal_kg_alignment(kg, method = c("exact", "fuzzy")))

  # Do not repair the misses by loosening the fuzzy cap. At
  # max_distance = 8 the fuzzy tier maps `steeper_slopes` onto
  # `temperature`, which is worse than no match at all.
  causal_kg_alignment(kg, max_distance = 8L)
}
#>            original     canonical    method distance
#> 1      precipitaton precipitation     fuzzy        1
#> 2               soc           soc     exact        0
#> 3          aluminum     aluminium     fuzzy        1
#> 4      root_biomass  root_biomass     exact        0
#> 5    steeper_slopes          <NA>      none       NA
#> 6           erosion       erosion     exact        0
#> 7 microbial_biomass       biomass substring       NA
#> 8     decomposition decomposition     exact        0
#>            original     canonical method distance
#> 1      precipitaton precipitation  fuzzy        1
#> 2               soc           soc  exact        0
#> 3          aluminum     aluminium  fuzzy        1
#> 4      root_biomass  root_biomass  exact        0
#> 5    steeper_slopes          <NA>   none       NA
#> 6           erosion       erosion  exact        0
#> 7 microbial_biomass          <NA>   none       NA
#> 8     decomposition decomposition  exact        0
#>            original     canonical    method distance
#> 1      precipitaton precipitation     fuzzy        1
#> 2               soc           soc     exact        0
#> 3          aluminum     aluminium     fuzzy        1
#> 4      root_biomass  root_biomass     exact        0
#> 5    steeper_slopes   temperature     fuzzy        8
#> 6           erosion       erosion     exact        0
#> 7 microbial_biomass       biomass substring       NA
#> 8     decomposition decomposition     exact        0
```
