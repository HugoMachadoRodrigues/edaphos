#!/usr/bin/env Rscript
# Build a PLOS-compliant reference.docx for pandoc/rmarkdown word_document.
#
# Encodes the rules in the PLOS "Manuscript Body Formatting Guidelines"
# (modified April 2021), which the journal states verbatim:
#   * Level 1 heading: bold, 18 pt, sentence case (major sections)
#   * Level 2 heading: bold, 16 pt
#   * Level 3 heading: bold, 14 pt
#   * body submitted in DOUBLE-SPACED paragraph format
#   * continuous line numbering (the guidelines' own exemplar is line-numbered)
# Body font is Times New Roman 12 pt, PLOS's manuscript default.
#
# Run:  Rscript paper/assets/make_reference_docx.R
suppressPackageStartupMessages({ library(xml2) })

here   <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
ref    <- file.path(here, "reference.docx")
stopifnot(file.exists(ref))
work   <- file.path(tempdir(), "refdocx"); unlink(work, recursive = TRUE)
dir.create(work, recursive = TRUE)
utils::unzip(ref, exdir = work)

W <- "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
wq <- function(x) paste0("w:", x)

## ---- styles.xml ---------------------------------------------------------
sf <- file.path(work, "word", "styles.xml")
sx <- read_xml(sf)
ns <- xml_ns(sx)

set_attr <- function(node, name, value) xml_set_attr(node, paste0("w:", name), value)

# ensure a child element exists under `parent`, return it
ensure <- function(parent, tag) {
  n <- xml_find_first(parent, paste0("./w:", tag), ns)
  if (inherits(n, "xml_missing")) {
    n <- xml_add_child(parent, paste0("w:", tag))
  }
  n
}

style_by_id <- function(id) xml_find_first(sx, sprintf("//w:style[@w:styleId='%s']", id), ns)

# Heading levels: bold + exact size, no colour, keep-with-next.
heading_spec <- list(Heading1 = 36L, Heading2 = 32L, Heading3 = 28L,
                     Heading4 = 24L, Heading5 = 24L)
for (id in names(heading_spec)) {
  st <- style_by_id(id)
  if (inherits(st, "xml_missing")) next
  rPr <- ensure(st, "rPr")
  # drop any colour/italic the default theme applies
  for (bad in c("color", "i", "iCs", "smallCaps", "caps")) {
    n <- xml_find_first(rPr, paste0("./w:", bad), ns)
    if (!inherits(n, "xml_missing")) xml_remove(n)
  }
  b  <- ensure(rPr, "b");   set_attr(b,  "val", "true")
  bC <- ensure(rPr, "bCs"); set_attr(bC, "val", "true")
  sz <- ensure(rPr, "sz");   set_attr(sz,  "val", as.character(heading_spec[[id]]))
  szC<- ensure(rPr, "szCs"); set_attr(szC, "val", as.character(heading_spec[[id]]))
  rf <- ensure(rPr, "rFonts")
  for (a in c("ascii", "hAnsi", "cs")) set_attr(rf, a, "Times New Roman")
  pPr <- ensure(st, "pPr")
  sp  <- ensure(pPr, "spacing")
  set_attr(sp, "before", "240"); set_attr(sp, "after", "120")
  set_attr(sp, "line", "480"); set_attr(sp, "lineRule", "auto")
}

# Normal (body): Times New Roman 12 pt, double spaced.
st <- style_by_id("Normal")
if (!inherits(st, "xml_missing")) {
  rPr <- ensure(st, "rPr")
  rf  <- ensure(rPr, "rFonts")
  for (a in c("ascii", "hAnsi", "cs")) set_attr(rf, a, "Times New Roman")
  sz  <- ensure(rPr, "sz");   set_attr(sz,  "val", "24")   # 12 pt
  szC <- ensure(rPr, "szCs"); set_attr(szC, "val", "24")
  pPr <- ensure(st, "pPr")
  sp  <- ensure(pPr, "spacing")
  set_attr(sp, "line", "480"); set_attr(sp, "lineRule", "auto")  # double
  set_attr(sp, "after", "0")
}

# Also double-space the docDefaults so tables/captions inherit sensibly.
dd <- xml_find_first(sx, "//w:docDefaults//w:pPrDefault/w:pPr", ns)
if (!inherits(dd, "xml_missing")) {
  sp <- ensure(dd, "spacing")
  set_attr(sp, "line", "480"); set_attr(sp, "lineRule", "auto")
}
ddr <- xml_find_first(sx, "//w:docDefaults//w:rPrDefault/w:rPr", ns)
if (!inherits(ddr, "xml_missing")) {
  rf <- ensure(ddr, "rFonts")
  for (a in c("ascii", "hAnsi", "cs")) set_attr(rf, a, "Times New Roman")
  sz <- ensure(ddr, "sz"); set_attr(sz, "val", "24")
}
write_xml(sx, sf)

## ---- document.xml: continuous line numbers ------------------------------
df <- file.path(work, "word", "document.xml")
dx <- read_xml(df)
sect <- xml_find_first(dx, "//w:sectPr", xml_ns(dx))
if (!inherits(sect, "xml_missing")) {
  old <- xml_find_first(sect, "./w:lnNumType", xml_ns(dx))
  if (!inherits(old, "xml_missing")) xml_remove(old)
  ln <- xml_add_child(sect, "w:lnNumType")
  xml_set_attr(ln, "w:countBy", "1")
  xml_set_attr(ln, "w:restart", "continuous")
  xml_set_attr(ln, "w:distance", "360")
}
write_xml(dx, df)

## ---- rezip --------------------------------------------------------------
out <- file.path(normalizePath(here, mustWork = TRUE), "plos-reference.docx")
if (file.exists(out)) unlink(out)
old <- setwd(work); on.exit(setwd(old), add = TRUE)
files <- list.files(".", recursive = TRUE, all.files = TRUE, no.. = TRUE)
utils::zip(out, files, flags = "-q -X")
setwd(old)
cat(sprintf("wrote %s (%d bytes)\n", out, file.size(out)))
