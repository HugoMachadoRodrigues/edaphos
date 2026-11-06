# ---------------------------------------------------------------------------
# Vignette diagrams are static SVGs, and each matches the DOT it came from.
#
# Two vignettes drew one diagram each with DiagrammeR::grViz(). An htmlwidget
# carries its JavaScript runtime into the self-contained vignette HTML: 2.1 MB
# per vignette for one diagram, which put the source tarball at 5.09 MB, over
# CRAN's 5 MB cap. The diagrams are now rendered once to SVG by
# tools/render-vignette-diagrams.R from vignettes/diagrams/*.gv.
# ---------------------------------------------------------------------------
vig_root <- function() {
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "DESCRIPTION")) &&
        dir.exists(file.path(d, "vignettes", "diagrams"))) return(d)
    up <- dirname(d); if (identical(up, d)) break; d <- up
  }
  NA_character_
}

test_that("every rendered SVG matches the DOT source it records", {
  root <- vig_root()
  skip_if(is.na(root), "not running from a source checkout")
  skip_if_not_installed("digest")
  gvs <- list.files(file.path(root, "vignettes", "diagrams"), "[.]gv$",
                    full.names = TRUE)
  expect_gt(length(gvs), 0L)
  for (gv in gvs) {
    svg <- file.path(root, "vignettes", "figures",
                     sub("[.]gv$", ".svg", basename(gv)))
    expect_true(file.exists(svg), info = basename(gv))
    src <- paste(readLines(gv, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    want <- digest::digest(src, algo = "sha256", serialize = FALSE)
    head <- paste(readLines(svg, n = 3L, warn = FALSE), collapse = " ")
    expect_true(grepl(want, head, fixed = TRUE),
                info = sprintf("%s was edited without re-running tools/render-vignette-diagrams.R",
                               basename(gv)))
  }
})

test_that("no vignette embeds a JavaScript widget runtime", {
  root <- vig_root()
  skip_if(is.na(root), "not running from a source checkout")
  rmd <- list.files(file.path(root, "vignettes"), "[.]Rmd$", full.names = TRUE)
  code <- unlist(lapply(rmd, function(f) {
    l <- readLines(f, warn = FALSE)
    # Only executable lines matter; prose may name the function.
    l[!grepl("^\\s*#", l) & !grepl("`[^`]*grViz[^`]*`", l)]
  }))
  expect_false(any(grepl("\\bgrViz\\s*\\(", code)),
               info = "render the diagram with tools/render-vignette-diagrams.R instead")
})
