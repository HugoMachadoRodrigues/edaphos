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
