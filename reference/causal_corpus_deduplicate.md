# Deduplicate a corpus by DOI or title

Collapses rows that refer to the same publication when combining results
from multiple sources (SciELO + OpenAlex frequently share Brazilian
pedology papers). DOI is the primary key when available; a normalised
lower-case title is the fallback.

## Usage

``` r
causal_corpus_deduplicate(corpus, by = c("doi", "title"))
```

## Arguments

- corpus:

  Data frame with at minimum a `doi` and / or `title` column.

- by:

  Character vector of columns to deduplicate on. Default
  `c("doi","title")` — try DOI first, fall back to title.

## Value

A de-duplicated data frame.
