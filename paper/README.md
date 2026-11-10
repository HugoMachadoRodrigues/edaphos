# Manuscript

Submission-formatted version of the edaphos paper (PLOS template). A condensed,
executable version ships with the package as the vignette
`vignettes/edaphos-paper.Rmd` (S1 File).

| File | What it is |
| --- | --- |
| `plos-manuscript.Rmd` | R Markdown source; every number in the text is computed at render time |
| `plos-manuscript.docx` | the rendered Word manuscript (PLOS accepts `.docx`) |
| `references.bib`, `plos.csl` | bibliography and PLOS citation style |
| `figures/` | Fig1-Fig14, 300 dpi, `.png` for the Word build and `.tiff` for submission |
| `S2_File_pipeline.zip` | S2 File: every `data-raw/` script plus a RUN-ORDER |
| `assets/` | figure script, Word reference style, docx clean-up |
| `slides.Rmd`, `slides.pdf` | talk slides |

## Where the numbers come from

The text reads only result bundles shipped in `inst/extdata/`, so the
installed package alone reproduces every number in it. The bundles hold
aggregate results, not records: the WoSIS and SoilData profiles behind them
are third-party measurements under per-record licences, and the package does
not redistribute them (see `PROVENANCE.md`).

Numbers that used to be computed at render time from records removed on
2026-08-28 now come from `inst/extdata/paper_record_aggregates.rds`, built by
`data-raw/paper_record_aggregates.R`. That script first checks that its input
records reproduce the aggregates already shipped, so the new numbers come from
the same records as the published ones.

## Regenerate

From the repository root. Steps 1 and 2 are needed only for the figures and
for `data-raw/` scripts that read records; the manuscript text needs neither.

```sh
# 1. local record cache: data-raw/build/records/ (gitignored, never shipped)
Rscript data-raw/restore_records.R

# 2. figures (Fig 1, the Fig 3 pedon and Fig 5 plot records from that cache)
Rscript paper/assets/figures.R          # EDAPHOS_FIGS_FORCE=1 to redraw all

# 3. S2 File
Rscript tools/build_s2_pipeline.R

# 4. the manuscript
cd paper && Rscript -e 'rmarkdown::render("plos-manuscript.Rmd")'
Rscript paper/assets/clean_docx.R       # strip bookmarks from the .docx
```

`restore_records.R` reads the records back out of the repository's git history
(the last commit before the 2026-08-28 strip) and checks each file against its
git blob, so it needs a clone with history and no network. A fresh pull from
the public sources instead (`data-raw/piml_wosis_multihorizon.R` and the other
retrieval scripts, which write to the same cache) re-runs the analysis on the
archives as they stand today, which will differ from the published snapshot.

**Caveat for `data-raw/` producers.** Re-running a producer writes its full
bundle, records included, into `inst/extdata/`.
`tests/testthat/test-no-third-party-data.R` fails until the records are removed
again, so a re-run cannot slip records into a release unnoticed.
