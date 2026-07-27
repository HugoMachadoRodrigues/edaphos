## Documentation cross-references must point at things that exist.
##
## Two drifts this catches, both of which shipped in v4.0.0:
##   * `vignette("pilar5-soilgrids-br")` was advertised from
##     R/edaphos-package.R and the README; no such vignette exists.
##     The README named three more that do not exist either.
##   * The roadmap and package overview link functions with [fn()].  A
##     renamed or never-exported function leaves a dead link that
##     roxygen resolves to nothing and no test noticed.
##
## These run from the package source tree, so they are skipped when the
## sources are absent (e.g. checking an installed binary).

.pkg_root <- function() {
  for (p in c(".", "..", "../..", "../../..")) {
    if (file.exists(file.path(p, "DESCRIPTION")) &&
        dir.exists(file.path(p, "vignettes"))) return(normalizePath(p))
  }
  NA_character_
}

test_that("every vignette() reference in R/ and README resolves to a file", {
  root <- .pkg_root()
  skip_if(is.na(root), "package source tree not available")

  have <- sub("\\.Rmd$", "",
              list.files(file.path(root, "vignettes"), pattern = "\\.Rmd$"))
  expect_gt(length(have), 0L)

  sources <- c(
    list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE),
    file.path(root, "README.md")
  )
  sources <- sources[file.exists(sources)]

  refs <- unique(unlist(lapply(sources, function(f) {
    txt <- readLines(f, warn = FALSE)
    m <- regmatches(txt, gregexpr('vignette\\("[A-Za-z0-9._-]+"', txt))
    gsub('^vignette\\("|"$', "", unlist(m))
  })))

  missing <- setdiff(refs, have)
  expect_equal(missing, character(0),
               info = paste("vignette() references with no .Rmd:",
                            paste(missing, collapse = ", ")))
})

test_that("every [fn()] link in the roadmap and overview resolves", {
  root <- .pkg_root()
  skip_if(is.na(root), "package source tree not available")

  ns <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
  exported <- gsub("`", "",
                   sub("[)]$", "", sub("^export[(]", "",
                       grep("^export[(]", ns, value = TRUE))))
  s3 <- gsub(",", ".", sub("[)]$", "", sub("^S3method[(]", "",
             grep("^S3method[(]", ns, value = TRUE))))

  files <- file.path(root, "R",
                     c("pillars_roadmap.R", "edaphos-package.R"))
  files <- files[file.exists(files)]
  skip_if(length(files) == 0L, "roadmap sources not available")

  src  <- unlist(lapply(files, readLines, warn = FALSE))
  refs <- unique(unlist(regmatches(
    src, gregexpr("\\[[a-zA-Z_.][a-zA-Z0-9_.]*[(][)]\\]", src))))
  refs <- gsub("^\\[|[(][)]\\]$", "", refs)
  expect_gt(length(refs), 20L)

  in_base <- function(r) {
    any(vapply(c("base", "stats", "utils", "graphics"),
               function(p) exists(r, envir = asNamespace(p), inherits = FALSE),
               logical(1)))
  }
  dead <- refs[!vapply(refs, function(r)
    r %in% exported || r %in% s3 || in_base(r), logical(1))]

  expect_equal(dead, character(0),
               info = paste("cross-references that resolve to nothing:",
                            paste(dead, collapse = ", ")))
})

test_that("the ten-pillar claim is consistent across DESCRIPTION and docs", {
  root <- .pkg_root()
  skip_if(is.na(root), "package source tree not available")

  desc <- paste(readLines(file.path(root, "DESCRIPTION"), warn = FALSE),
                collapse = " ")
  expect_match(desc, "ten research pillars")

  # No shipped documentation may still advertise six as a *current*
  # claim.  Changelog rows describing what a past release contained are
  # historically accurate and stay, so a line is exempt when it carries
  # an explicit historical qualifier.
  docs <- c(list.files(file.path(root, "R"), pattern = "\\.R$",
                       full.names = TRUE),
            file.path(root, "README.md"))
  docs <- docs[file.exists(docs)]

  historical <- "v[0-9]+\\.[0-9]+\\.[0-9]+|existed|then-six|that release"

  offenders <- Filter(function(f) {
    hits <- grep("six pillars|six research pillars",
                 readLines(f, warn = FALSE), value = TRUE,
                 ignore.case = TRUE)
    any(!grepl(historical, hits, ignore.case = TRUE))
  }, docs)

  expect_equal(basename(offenders), character(0),
               info = paste("still claims six pillars:",
                            paste(basename(offenders), collapse = ", ")))

  # Each of the ten pillars needs a vignette on disk.
  have <- list.files(file.path(root, "vignettes"), pattern = "\\.Rmd$")
  for (i in 1:10)
    expect_true(any(grepl(sprintf("^pilar%d-", i), have)),
                info = sprintf("no vignette for pillar %d", i))
})
