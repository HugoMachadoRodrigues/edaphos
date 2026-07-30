# Manuscript

Submission-formatted version of the edaphos paper. The **reproducible source of
truth** is the package vignette `vignettes/edaphos-paper.Rmd`; this directory
holds the same content reformatted for journal submission (PLOS ONE template).

| File | What it is |
| --- | --- |
| `manuscript.Rmd` | R Markdown source (PLOS template via `rticles::plos_article`); every number is computed from the shipped bundles at render time |
| `manuscript.pdf` | Compiled PLOS-formatted PDF (6 pp.) |
| `manuscript.docx` | Word version (PLOS accepts `.docx` submissions; no LaTeX needed) |
| `manuscript.tex` | LaTeX source, ready for Overleaf / a current TeX Live |
| `references.bib`, `plos.csl` | bibliography and PLOS citation style |

## Regenerate

```r
# PDF (needs a current LaTeX; rticles + tinytex)
rmarkdown::render("manuscript.Rmd")

# Word (no LaTeX)
rmarkdown::render("manuscript.Rmd",
                  output_format = rmarkdown::word_document(number_sections = TRUE),
                  output_file = "manuscript.docx")
```

The setup chunk does `pkgload::load_all("..")` and reads
`inst/extdata/*.rds`, so the manuscript's numbers cannot drift from the data.

**Note on the bundled PDF/tex.** They were produced with a `pandocbounded`
preamble shim (added in the YAML `header-includes`) and with the pandoc image
`alt=` option stripped, to compile under an older local LaTeX. On Overleaf or a
current TeX Live neither workaround is needed.
