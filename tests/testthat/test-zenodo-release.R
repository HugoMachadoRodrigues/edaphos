# ---------------------------------------------------------------------------
# edaphos_zenodo_release() and llm_annotation_launch()
#
# Both are exported, both had \dontrun examples, and until this file neither
# was touched by a single test. The release helper is the more dangerous of
# the two: it unlink()s output_dir before it writes, it is the last thing that
# runs before a DOI is minted, and the manifest it emits is the only record
# that says the bundles in the deposit are the bundles that were in the
# package. A silent defect in it publishes wrong checksums under a permanent
# identifier, which is exactly the class of error you cannot retract.
#
# WHAT IS ASSERTED, AND WHY IT IS NOT DECORATION. The checksum test recomputes
# SHA-256 for every manifest row and compares. That is the assertion a real
# defect breaks: copy the wrong file, hash the source instead of the copy,
# write the manifest before the copy finishes, and this fails. Asserting only
# that manifest.csv "exists and has rows" would survive all three.
#
# llm_annotation_launch() blocks in shiny::runApp() and is NEVER called here
# on a path that could reach it -- see the note above its own tests.
# ---------------------------------------------------------------------------

# --- helpers ---------------------------------------------------------------

# The rds/jsonl artefacts the release is supposed to carry, derived without
# reusing the function's own regex, so a broken pattern cannot hide behind a
# matching expectation.
shipped_bundles <- function() {
  src <- system.file("extdata", package = "edaphos")
  if (!nzchar(src) || !dir.exists(src)) return(character())
  all <- list.files(src)
  all[tolower(tools::file_ext(all)) %in% c("rds", "jsonl")]
}

# Build one bundle for the assertions below. include_tarball = FALSE keeps
# devtools::build() -- which compiles whatever package sits in getwd(), not
# anything in output_dir -- out of the test run; zip = FALSE keeps utils::zip()
# and its setwd() out of it.
build_release <- function(dir, ...) {
  suppressMessages(
    edaphos_zenodo_release(dir, include_tarball = FALSE, zip = FALSE, ...))
}


# --- edaphos_zenodo_release(): input validation -----------------------------

test_that("edaphos_zenodo_release() refuses a malformed output_dir before touching the disk", {
  tmp <- withr::local_tempdir()

  # is.character() and length() == 1L, in that order.
  expect_error(build_release(42), "is\\.character\\(output_dir\\)")
  expect_error(build_release(character()), "length\\(output_dir\\)")
  expect_error(build_release(c(file.path(tmp, "a"), file.path(tmp, "b"))),
               "length\\(output_dir\\)")

  # The guard is the first statement in the body and unlink() is the second,
  # so a rejected call must leave the filesystem exactly as it found it. If
  # the stopifnot ever moves below the unlink(), a two-element output_dir
  # would delete "a" and this stays green only because nothing was created --
  # so assert emptiness, which also fails if a partial bundle was written.
  expect_equal(list.files(tmp, recursive = TRUE), character())
})


# --- edaphos_zenodo_release(): the bundle it documents ----------------------

test_that("edaphos_zenodo_release() writes the directory its documentation promises", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "release")

  expect_identical(build_release(out), out)   # returned invisibly
  expect_true(dir.exists(out))

  # The four things the function always produces.
  expect_true(dir.exists(file.path(out, "bundles")))
  for (f in c("metadata.json", "manifest.csv", "ZENODO-README.md")) {
    expect_true(file.exists(file.path(out, f)), info = f)
  }

  # bundles/ is every shipped .rds/.jsonl and nothing else: setequal fails
  # both on a missing artefact and on a stray file that got swept in.
  expect_setequal(list.files(file.path(out, "bundles")), shipped_bundles())
  expect_gt(length(shipped_bundles()), 0)

  # CITATION.cff / NEWS.md / README.md are copied only if they can be found
  # (getwd() first, then the installed package), so their presence depends on
  # whether the tests run from a source checkout. Not asserted as required --
  # asserted as non-empty when present, which is what a broken file.copy()
  # would produce.
  for (f in intersect(c("CITATION.cff", "NEWS.md", "README.md"),
                      list.files(out))) {
    expect_gt(file.size(file.path(out, f)), 0)
  }
})

test_that("metadata.json parses and carries the DataCite fields the function claims", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "release")
  build_release(out)

  meta <- jsonlite::read_json(file.path(out, "metadata.json"))$metadata
  expect_type(meta, "list")

  version <- as.character(utils::packageVersion("edaphos"))
  expect_identical(meta$upload_type,  "software")
  expect_identical(meta$access_right, "open")
  expect_identical(meta$license,      "mit")
  expect_identical(meta$version,      version)

  # The default title has to name the package and the version it deposits;
  # a stale hard-coded version here is the defect the deposit cannot survive.
  expect_match(meta$title, "^edaphos ", fixed = FALSE)
  expect_true(grepl(version, meta$title, fixed = TRUE))
  expect_match(meta$description, "Digital Soil Mapping", fixed = TRUE)

  # Default creator: Zenodo wants "Family, Given".
  expect_length(meta$creators, 1L)
  expect_identical(meta$creators[[1]]$name, "Rodrigues, Hugo")
  expect_identical(meta$creators[[1]]$orcid, "0000-0002-8070-8126")
  expect_true(nzchar(meta$creators[[1]]$affiliation))

  expect_identical(unlist(meta$keywords),
                   c("digital soil mapping", "causal inference",
                     "foundation models", "quantum machine learning",
                     "Cerrado", "pedometrics"))

  # The concept DOI every version of the deposit hangs off.
  expect_length(meta$related_identifiers, 1L)
  expect_identical(meta$related_identifiers[[1]]$relation, "isVersionOf")
  expect_identical(meta$related_identifiers[[1]]$identifier,
                   "10.5281/zenodo.19683708")
  expect_identical(meta$related_identifiers[[1]]$scheme, "doi")
})

test_that("caller-supplied title, keywords and authors reach metadata.json", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "release")

  # Second author deliberately has no ORCID and no affiliation: the function
  # drops those keys per-creator rather than emitting NA, and Zenodo rejects
  # a creator whose orcid is the string "NA".
  authors <- data.frame(
    family_name = c("Silva", "Souza"),
    given_name  = c("Ana", "Bruno"),
    orcid       = c("0000-0001-2345-6789", NA_character_),
    affiliation = c("Embrapa", NA_character_),
    stringsAsFactors = FALSE
  )
  build_release(out, title = "custom deposit title",
                keywords = c("pedology", "test"), authors = authors)

  meta <- jsonlite::read_json(file.path(out, "metadata.json"))$metadata
  expect_identical(meta$title, "custom deposit title")
  expect_identical(unlist(meta$keywords), c("pedology", "test"))

  expect_length(meta$creators, 2L)
  expect_named(meta$creators[[1]], c("name", "orcid", "affiliation"))
  expect_identical(meta$creators[[1]]$name, "Silva, Ana")
  expect_identical(meta$creators[[1]]$orcid, "0000-0001-2345-6789")
  expect_identical(meta$creators[[2]]$name, "Souza, Bruno")
  # expect_named, NOT expect_null(meta$creators[[2]]$orcid): jsonlite writes a
  # missing ORCID as `"orcid": null`, and read_json turns that back into a
  # named element holding NULL -- so expect_null() is satisfied by the very
  # output the branch exists to prevent. Only the key set can tell an omitted
  # field from a null one. (Verified: dropping the is.na() branch keeps
  # expect_null green and turns this red.)
  expect_named(meta$creators[[2]], "name")

  # The README is generated from the same title.
  expect_match(readLines(file.path(out, "ZENODO-README.md"))[1],
               "custom deposit title", fixed = TRUE)
})


# --- edaphos_zenodo_release(): the manifest is the deposit's evidence -------

test_that("manifest.csv lists the files actually written, with matching SHA-256 checksums", {
  skip_if_not_installed("digest")   # without it the sha256 column is all NA
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "release")
  build_release(out)

  man <- utils::read.csv(file.path(out, "manifest.csv"),
                         stringsAsFactors = FALSE)
  expect_named(man, c("path", "bytes", "sha256"))
  expect_gt(nrow(man), 0)

  # No phantom rows: every path in the manifest is a file in the bundle.
  expect_true(all(file.exists(file.path(out, man$path))))
  expect_equal(man$bytes, unname(file.size(file.path(out, man$path))))

  # Every bundle and the metadata block are accounted for.
  expect_true(all(file.path("bundles", shipped_bundles()) %in% man$path))
  expect_true("metadata.json" %in% man$path)

  # THE ASSERTION THIS FILE EXISTS FOR. Recompute every checksum from the file
  # that is actually in the bundle. A copy that silently truncated, a hash
  # taken of the source rather than the copy, a manifest written before the
  # copy: each shows up here and nowhere else.
  recomputed <- vapply(file.path(out, man$path),
                       function(p) digest::digest(file = p, algo = "sha256"),
                       character(1), USE.NAMES = FALSE)
  expect_identical(man$sha256, recomputed)

  # DOCUMENTED GAP, PINNED ON PURPOSE. ZENODO-README.md advertises "SHA-256
  # checksums for every file", but the manifest is built from a listing taken
  # before manifest.csv and ZENODO-README.md exist, so those two are the only
  # files in the bundle with no checksum. That is stated in the function's own
  # examples. If the ordering is ever fixed this test fails -- which is the
  # point: the claim in the README and the contents of the table have to move
  # together.
  expect_setequal(setdiff(list.files(out, recursive = TRUE), man$path),
                  c("manifest.csv", "ZENODO-README.md"))
})


# --- edaphos_zenodo_release(): the optional artefacts stay optional ---------

test_that("include_tarball = FALSE and zip = FALSE produce no tarball and no archive", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "release")
  build_release(out)

  expect_equal(list.files(out, pattern = "\\.tar\\.gz$", recursive = TRUE),
               character())
  expect_false(file.exists(paste0(out, ".zip")))
  # Nothing was written beside the bundle either (utils::zip() setwd()s to the
  # parent, so a leaked archive lands here).
  expect_equal(list.files(tmp), "release")
})

test_that("edaphos_zenodo_release() deletes output_dir before writing into it", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "release")
  dir.create(out)
  writeLines("not a release artefact", file.path(out, "keep_me.txt"))
  dir.create(file.path(out, "subdir"))

  build_release(out)

  # Documented, destructive, and the reason the examples warn never to point
  # output_dir at a directory holding anything else.
  expect_false(file.exists(file.path(out, "keep_me.txt")))
  expect_false(dir.exists(file.path(out, "subdir")))
  expect_true(file.exists(file.path(out, "metadata.json")))
})


# ---------------------------------------------------------------------------
# llm_annotation_launch()
#
# WHAT IS NOT TESTED, AND WHY. The function ends in shiny::runApp(app_dir),
# which blocks until the browser tab closes. It offers no seam that returns an
# app object instead of running one -- no `shiny::shinyAppDir()` return, no
# `run = FALSE` argument -- and the UI/server live in a separate file
# (inst/shiny-apps/annotation/app.R) that runApp() sources itself. So the
# app's behaviour is unreachable from a test without launching it, and none of
# these tests calls the function on arguments that could reach runApp():
# every call below either fails at the stopifnot() or is diverted at the
# dependency guard.
# ---------------------------------------------------------------------------

# Returns llm_annotation_launch() with its closure environment swapped for one
# that shadows requireNamespace(). The real function body still runs -- only
# the availability answer changes. Needed because all four Shiny-stack
# packages are installed in this environment, and testthat::local_mocked_bindings()
# cannot help: requireNamespace() is a base binding the edaphos namespace does
# not own, and the namespace is locked, so nothing can be added to it.
launch_seeing_missing <- function(missing) {
  f <- llm_annotation_launch
  env <- new.env(parent = asNamespace("edaphos"))
  env$requireNamespace <- function(package, ...) !(package %in% missing)
  environment(f) <- env
  f
}

test_that("llm_annotation_launch() rejects a draft path that does not exist", {
  tmp <- withr::local_tempdir()

  expect_error(llm_annotation_launch(file.path(tmp, "no_such_draft.jsonl")),
               "file\\.exists\\(draft_path\\)")
  expect_error(llm_annotation_launch(), "draft_path.*missing")

  # The check is the first statement in the body, so a rejected call cannot
  # have reached options() -- let alone runApp().
  expect_null(getOption("edaphos.annotation.draft"))
})

test_that("llm_annotation_launch() stops on the first missing Shiny dependency", {
  tmp <- withr::local_tempdir()
  draft <- file.path(tmp, "draft.jsonl")
  writeLines('{"abstract_id":"CER_A","claims":[]}', draft)

  # Safety net: if the dependency guard is ever removed, the calls below would
  # reach runApp() and block the suite forever. An elapsed limit turns that
  # hang into a failure. Reset explicitly -- transient = TRUE only expires at
  # the end of the top-level task, which is the whole test file.
  withr::defer(setTimeLimit())
  setTimeLimit(elapsed = 30, transient = TRUE)

  # Each package is named in its own message, and the loop stops at the first
  # one that is unavailable. Every case leaves at least one package missing,
  # so runApp() is never reached.
  expect_error(launch_seeing_missing("shiny")(draft),
               "Install 'shiny' to launch the annotation app.", fixed = TRUE)
  expect_error(launch_seeing_missing("DT")(draft),
               "Install 'DT' to launch the annotation app.", fixed = TRUE)
  expect_error(launch_seeing_missing("bslib")(draft),
               "Install 'bslib' to launch the annotation app.", fixed = TRUE)
  expect_error(launch_seeing_missing("shinyjs")(draft),
               "Install 'shinyjs' to launch the annotation app.", fixed = TRUE)

  # shiny is checked first, so a run missing everything still names shiny.
  expect_error(
    launch_seeing_missing(c("shiny", "DT", "bslib", "shinyjs"))(draft),
    "Install 'shiny' to launch the annotation app.", fixed = TRUE)

  # The guard runs before the options() side effect, so an aborted launch
  # leaves no annotation paths behind for a later, unrelated call to pick up.
  withr::local_options(edaphos.annotation.draft = "sentinel")
  expect_error(launch_seeing_missing("shiny")(draft), "Install 'shiny'")
  expect_identical(getOption("edaphos.annotation.draft"), "sentinel")
})

test_that("the annotation app directory the launcher resolves is actually shipped", {
  # Not app behaviour -- the precondition the launcher checks before its
  # dependency guard. If inst/shiny-apps/annotation/app.R is moved or dropped
  # from the build, llm_annotation_launch() stops with "annotation Shiny app
  # directory not found" for every user, and nothing else in the suite notices.
  app_dir <- system.file("shiny-apps", "annotation", package = "edaphos")
  expect_true(nzchar(app_dir) && dir.exists(app_dir))
  expect_true(file.exists(file.path(app_dir, "app.R")))
})
