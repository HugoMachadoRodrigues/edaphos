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

## Examples

``` r
if (FALSE) { # \dontrun{
  # Ollama needs no credentials, only a reachable server. The hosted
  # backends take their key from the environment instead:
  # backend = "openai" reads OPENAI_API_KEY, backend = "anthropic"
  # reads ANTHROPIC_API_KEY, and both ignore `host`.
  abstract <- paste(
    "Across 212 Cerrado profiles, mean annual precipitation was the",
    "dominant control on topsoil organic carbon, whereas slope",
    "position governed erosion losses under conventional tillage."
  )

  kg <- causal_kg_new()
  kg <- causal_llm_ingest_abstract(
    kg, abstract,
    source  = "Silva et al. 2019",
    backend = "ollama", model = "gemma4:latest",
    host    = "http://localhost:11434"
  )

  # The "claims" attribute is what was INSERTED, not what the model
  # returned -- anything below `min_confidence` is already gone. To
  # audit what was discarded, call causal_llm_extract() yourself.
  attr(kg, "claims")

  # It also carries the model's own labels, which the graph does not:
  # node names are snake_cased on insertion, so a claim about
  # "mean annual precipitation" becomes the node
  # "mean_annual_precipitation".
  causal_kg_edges(kg)$cause

  # Trap: min_confidence = 0 does not mean "keep everything". The
  # filter is `!is.na(confidence) & confidence >= min_confidence`, so
  # a claim whose confidence field the model omitted is dropped at
  # every threshold, silently.
  kg_all <- causal_llm_ingest_abstract(causal_kg_new(), abstract,
                                       source = "Silva et al. 2019",
                                       min_confidence = 0)

  # Trap: a cause and effect that differ only in spacing or hyphens
  # ("soil organic carbon" vs "soil-organic-carbon") pass the JSON
  # parser, then collapse onto one node, and causal_kg_add_edge()
  # raises "Self-loops are not allowed". That error aborts the whole
  # call, so every other claim in the abstract is lost too. Wrap the
  # ingest whenever the passages are not hand-checked.
  kg <- tryCatch(
    causal_llm_ingest_abstract(kg, abstract, source = "Silva 2019"),
    error = function(e) {
      message("skipped abstract: ", conditionMessage(e))
      kg
    }
  )
} # }
```
