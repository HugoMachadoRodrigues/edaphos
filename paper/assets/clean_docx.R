#!/usr/bin/env Rscript
# Strip every bookmark from a rendered .docx.
#
# pandoc emits bookmarkStart/bookmarkEnd anchors for headings, figures, tables
# and citation links. In Word these surface as stray fields in a submitted
# manuscript and serve no purpose there. A Lua filter removes most of them; the
# citeproc ones are added after the filter runs, so we clear the rest here.
args <- commandArgs(TRUE)
f <- if (length(args)) args[1] else "plos-manuscript.docx"
stopifnot(file.exists(f))
d <- file.path(tempdir(), "docxclean"); unlink(d, recursive = TRUE); dir.create(d)
utils::unzip(f, exdir = d)
p <- file.path(d, "word", "document.xml")
x <- readLines(p, warn = FALSE, encoding = "UTF-8")
x <- paste(x, collapse = "\n")
before <- lengths(regmatches(x, gregexpr("<w:bookmarkStart", x)))
x <- gsub("<w:bookmarkStart[^>]*/>", "", x)
x <- gsub("<w:bookmarkEnd[^>]*/>", "", x)
after <- lengths(regmatches(x, gregexpr("<w:bookmarkStart", x)))
con <- file(p, open = "wb"); writeBin(charToRaw(x), con); close(con)
old <- setwd(d); on.exit(setwd(old), add = TRUE)
out <- normalizePath(file.path(old, f), mustWork = FALSE)
unlink(out)
utils::zip(out, list.files(".", recursive = TRUE, all.files = TRUE, no.. = TRUE),
           flags = "-q -X")
setwd(old)
cat(sprintf("bookmarks %d -> %d in %s\n", before, after, basename(f)))
