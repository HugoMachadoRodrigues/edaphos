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

## Examples

``` r
vocab <- causal_ontology_cerrado()
nrow(vocab)
#> [1] 58
table(vocab$category)
#> 
#>       chemistry         climate         outcome parent_material         process 
#>              13               8               5               9               7 
#>          relief      vegetation 
#>               6              10 

# The vocabulary is deliberately narrow: it covers the drivers that
# actually turn up in Cerrado pedology abstracts, not all of soil
# science. Terms outside it come back unmatched from
# causal_kg_alignment() -- that is the intended behaviour, not a bug.
#
# Note what "narrow" does and does not mean. `gibbsite` and `cec`
# ARE in it, because Cerrado abstracts discuss them; the SPELLING
# is what is narrow. `cation_exchange_capacity` is absent even
# though `cec` is present, so an extractor that emits the expanded
# form goes unmatched while one that emits the abbreviation does
# not. `salinity` is genuinely out of scope for the biome.
c("gibbsite", "cec", "cation_exchange_capacity", "salinity") %in%
  vocab$term   # TRUE TRUE FALSE FALSE
#> [1]  TRUE  TRUE FALSE FALSE

# A trap: `soc` and `soil_organic_carbon` are BOTH canonical terms,
# both filed under chemistry. Alignment will therefore keep them as
# two separate nodes rather than merging them -- collapse them
# yourself with causal_kg_rename() if your KG needs one carbon node.
subset(vocab, term %in% c("soc", "soil_organic_carbon", "soc_loss"))
#>                   term  category
#> 26                 soc chemistry
#> 27 soil_organic_carbon chemistry
#> 56            soc_loss   outcome

# Spelling is British throughout, so American labels can only be
# rescued by the fuzzy tier of causal_kg_alignment().
grep("alumin|mineralis", vocab$term, value = TRUE)
#> [1] "aluminium"      "mineralisation"
```
