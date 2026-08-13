# Launch the interactive gold-standard review app

Opens a Shiny application that presents every abstract in the draft
JSONL and lets the annotator accept / edit / reject each LLM-drafted
claim, plus add any claim the LLM missed. Writes to `output_path` after
every abstract, so interrupted sessions resume exactly where they left
off.

## Usage

``` r
llm_annotation_launch(
  draft_path,
  output_path = NULL,
  keyboard_shortcuts = TRUE,
  port = NULL
)
```

## Arguments

- draft_path:

  Path to the draft JSONL produced by
  [`llm_preannotate()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_preannotate.md).

- output_path:

  Where to write the reviewed JSONL. Defaults to `draft_path` (in-place
  review).

- keyboard_shortcuts:

  Logical; enable keyboard bindings.

- port:

  Optional integer port for the Shiny app.

## Value

Called for its side-effect (launches app); invisibly returns the path of
the reviewed JSONL.

## Details

**Keyboard shortcuts** (when `keyboard_shortcuts = TRUE`): `a` – accept
all and next \| `r` – reject all \| `n` – next abstract (save) \| `p` –
previous \| `+` – add claim \| `1..9` – toggle accept on claim *n*.

## Examples

``` r
if (FALSE) { # \dontrun{
# Phase 2.  This blocks until the browser tab is closed, so it only
# makes sense from an interactive session, and it needs shiny, DT,
# bslib and shinyjs installed.
corpus <- list(
  list(abstract_id   = "CER_A",
       abstract_text = "Rainfall raised topsoil SOC on 520 Oxisols.")
)
draft <- file.path(tempdir(), "cerrado_draft.jsonl")
llm_preannotate(corpus, backend = "simulator", output_path = draft)

# In-place review: `output_path` defaults to `draft_path`, and the
# app rewrites the file after every abstract, so an interrupted
# session loses at most the abstract you were on.
llm_annotation_launch(draft)

# Better for anything you will publish: keep the machine draft
# pristine and write the human verdicts elsewhere.  In-place review
# destroys the LLM-vs-human comparison you need to report the
# extractor's precision and recall.
reviewed <- file.path(tempdir(), "cerrado_reviewed.jsonl")
llm_annotation_launch(draft, output_path = reviewed)

# `port` only matters when the app must be reachable from outside
# the R process (container, remote annotator); leave it NULL and
# shiny picks a free port.
llm_annotation_launch(draft, output_path = reviewed, port = 8080)

# Claims the reviewer never touched are still status = "draft" and
# are discarded here -- check the claim count in the message before
# treating the result as a finished gold standard.
llm_annotation_export(reviewed, file.path(tempdir(), "cerrado_gold.jsonl"))
llm_annotation_validate(file.path(tempdir(), "cerrado_gold.jsonl"))
} # }
```
