# Pre-annotate a corpus with an LLM to produce draft claims

Runs
[`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md)
(real Ollama / OpenAI / Anthropic) or the deterministic
[`llm_benchmark_simulate()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_benchmark_simulate.md)
fallback over every abstract in the corpus, and writes a **draft JSONL**
in the same schema as `cerrado_gold_standard_v1.jsonl` but with `claims`
marked `status = "draft"` so the Shiny reviewer can distinguish
machine-generated entries from human-added ones.

## Usage

``` r
llm_preannotate(
  corpus,
  backend = c("ollama", "openai", "anthropic", "simulator"),
  model = NULL,
  output_path = "cerrado_draft_gold.jsonl",
  cache_dir = NULL,
  max_abstracts = NULL,
  verbose = TRUE,
  ...
)
```

## Arguments

- corpus:

  Either a path to a JSONL file with one record per line (records must
  have `abstract_id` and `abstract_text`), or a list of records already
  in memory.

- backend:

  One of `"ollama"`, `"openai"`, `"anthropic"`, `"simulator"`. When
  `"simulator"` the function does not call an LLM at all: it seeds the
  RNG from `abstract_id` and pairs
  [`llm_annotation_vocabulary()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_annotation_vocabulary.md)
  terms at random, ignoring `abstract_text` entirely. That keeps demos
  and CI builds runnable without API access, but the claims it produces
  carry no information about the abstract. Defaults to `"ollama"` with
  `gemma4:latest`.

- model:

  Optional model id. Defaults to `"gemma4:latest"` for Ollama.

- output_path:

  Path to write the draft JSONL.

- cache_dir:

  Optional directory for per-record JSON caches. When set, re-running
  the function over the same corpus short-circuits to cached
  extractions, so interrupted jobs resume exactly where they left off.
  Defaults to `NULL` (no cache).

- max_abstracts:

  Optional integer cap on how many abstracts to process (useful for
  staged runs).

- verbose:

  Logical; print per-abstract progress.

- ...:

  Forwarded to
  [`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md).

## Value

Invisibly, the list of records written.

## Examples

``` r
# Two abstracts in memory.  `abstract_id` and `abstract_text` are
# the only required fields; anything else the record carries (year,
# doi, topic) is passed straight through into the draft.
corpus <- list(
  list(abstract_id   = "CER_A",
       abstract_text = "Rainfall raised topsoil SOC on 520 Oxisols.",
       year = 2021),
  list(abstract_id   = "CER_B",
       abstract_text = "Fire frequency cut vegetation cover on sands.",
       year = 2019)
)
draft <- file.path(tempdir(), "cerrado_draft.jsonl")
d <- llm_preannotate(corpus, backend = "simulator",
                     output_path = draft, verbose = FALSE)
vapply(d, function(r) nrow(r$claims), integer(1))
#> [1] 5 2

# Every drafted claim is stamped status = "draft".  That stamp is
# what makes llm_annotation_export() throw it away: nothing reaches
# the gold standard until a human changes it in the reviewer.
d[[1]]$claims[1:2, c("cause", "effect", "polarity", "status")]
#>        cause effect polarity status
#> 1 weathering   clay        +  draft
#> 2       silt   sand        +  draft

# The simulator is a placeholder, not a weak extractor.  Draft the
# first 5 abstracts of the bundled gold standard and score its
# (cause, effect) pairs against the human annotation: 17 drafted,
# 17 true, exactly 1 pair in common.  A simulator run is never a
# measurement of pre-annotation quality.
gs <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
                  package = "edaphos")
sim <- llm_preannotate(gs, backend = "simulator", max_abstracts = 5,
                       output_path = tempfile(fileext = ".jsonl"),
                       verbose = FALSE)
edges <- function(recs) unlist(lapply(recs,
  function(r) paste(r$claims$cause, r$claims$effect)))
truth <- edges(lapply(readLines(gs, warn = FALSE)[1:5], jsonlite::fromJSON))
c(true = length(truth), drafted = length(edges(sim)),
  hits = length(intersect(truth, edges(sim))))
#>    true drafted    hits 
#>      17      17       1 

# Note what that run also did: it overwrote the human `claims` of
# CER_01..CER_05 with machine drafts.  Pre-annotate a corpus file,
# never a gold standard you want to keep.

# The simulator keys on `abstract_id` alone, so its draft is stable
# across sessions -- but it does that with a bare set.seed(), which
# silently resets the CALLER's stream.  Draw what you need before
# the call, or re-seed after it.
set.seed(42); before <- runif(1)
set.seed(42)
invisible(llm_preannotate(corpus, backend = "simulator", verbose = FALSE,
                          output_path = tempfile(fileext = ".jsonl")))
c(before = before, after = runif(1))
#>    before     after 
#> 0.9148060 0.6117337 

# `cache_dir` keys on abstract_id plus the FIRST 200 CHARACTERS of
# the text, so fixing a typo past character 200 is a cache hit and
# silently reuses the stale extraction.  Two texts, one cache entry;
# edit the opening instead and a second entry appears.
if (requireNamespace("digest", quietly = TRUE)) {
  head200 <- paste(rep("Cerrado Oxisol rainfall carbon", 12), collapse = " ")
  cache <- file.path(tempdir(), "preann_cache")
  run1 <- function(txt) llm_preannotate(
    list(list(abstract_id = "CER_A", abstract_text = txt)),
    backend = "simulator", cache_dir = cache, verbose = FALSE,
    output_path = tempfile(fileext = ".jsonl"))
  invisible(run1(paste(head200, "original tail")))
  invisible(run1(paste(head200, "a completely different tail")))
  n_tail <- length(list.files(cache))
  invisible(run1(paste("DIFFERENT OPENING", head200)))
  print(c(after_tail_edit = n_tail,
          after_opening_edit = length(list.files(cache))))
}
#>    after_tail_edit after_opening_edit 
#>                  1                  2 
```
