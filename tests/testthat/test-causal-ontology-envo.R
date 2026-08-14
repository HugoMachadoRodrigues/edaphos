# Tests for causal_ontology_envo() and the offline guards of
# causal_ontology_agrovoc().
#
# causal_ontology_envo() takes a *local* OBO path, so it is fully
# testable without network: we synthesise a tiny ENVO-shaped .obo and
# assert the parse plus the label -> term normalisation contract
# documented in R/causal_ontology.R:
#
#   term <- tolower(gsub("[^[:alnum:]]+", "_", trimws(label)))
#   term <- gsub("_+", "_", term); term <- gsub("^_|_$", "", term)
#
# i.e. lowercase, every run of non-alphanumerics collapsed to a single
# underscore, and no leading/trailing underscore.
#
# NOTE on the fixture: ontologyIndex's OBO reader treats "!" as the OBO
# comment character and only recognises a tag written as exactly
# "name: <value>" (extra spaces after the colon yield an NA name), so
# the stanzas below avoid both. Every other punctuation mark is fair
# game and is what exercises the regex.

.envo_fixture_labels <- c(
  "Cerrado (sensu stricto) Soil",  # spaces + parentheses + mixed case
  "pH (1:2.5 H2O) / KCl",          # several distinct punctuation runs
  "-- Ferralsol / Oxisol --",      # leading AND trailing punctuation
  "Gibbsite",                      # nothing to normalise but the case
  "Soil Organic Carbon, 0-30 cm"   # comma, hyphen, digits
)

.envo_fixture_ids <- c(
  "ENVO:00000001", "ENVO:00000002", "ENVO:00000003",
  "ENVO:00000004", "ENVO:00000005"
)

# The terms the documented normalisation must produce from the labels.
.envo_expected_terms <- c(
  "cerrado_sensu_stricto_soil",
  "ph_1_2_5_h2o_kcl",
  "ferralsol_oxisol",
  "gibbsite",
  "soil_organic_carbon_0_30_cm"
)

# Write a minimal but valid OBO file and return its path.
write_envo_fixture <- function(path = tempfile(fileext = ".obo")) {
  stanzas <- vapply(
    seq_along(.envo_fixture_ids),
    function(i) {
      body <- c("[Term]",
                paste0("id: ", .envo_fixture_ids[i]),
                paste0("name: ", .envo_fixture_labels[i]))
      # Give one term a parent so propagate_relationships = "is_a" has
      # something to chew on; it must not change the returned rows.
      if (i == 2L) body <- c(body, paste0("is_a: ", .envo_fixture_ids[1L]))
      paste(body, collapse = "\n")
    },
    character(1L)
  )
  writeLines(
    c("format-version: 1.2", "ontology: envo-test", "", stanzas),
    path
  )
  path
}

# ---- The missing-Suggests guard --------------------------------------------
# Kept first in the file on purpose: it can only fire while the
# ontologyIndex namespace has not yet been loaded into this session, and
# the parse tests below load it.

# Evaluate `code` with ontologyIndex hidden from the library search path.
# on.exit() restores .libPaths() however the frame unwinds -- normal
# return, a failing expectation, or a skip() -- so no later test in this
# file can inherit a truncated search path.
with_hidden_libs <- function(code) {
  old_libs <- .libPaths()
  on.exit(.libPaths(old_libs), add = TRUE)
  .libPaths(character(0))  # leaves only .Library
  code
}

test_that("causal_ontology_envo() stops with an install hint when ontologyIndex is unavailable", {
  skip_if("ontologyIndex" %in% loadedNamespaces(),
          "ontologyIndex is already loaded in this session")

  obo <- write_envo_fixture()

  err <- with_hidden_libs({
    skip_if(requireNamespace("ontologyIndex", quietly = TRUE),
            "ontologyIndex lives in .Library; cannot hide it without uninstalling")
    # Caught by hand rather than with expect_error(): testthat turns a
    # stray `packageNotFoundError` into a *skip*, so if the
    # requireNamespace() guard were deleted this test would quietly go
    # green-ish instead of failing. tryCatch() is innermost, so it sees
    # the condition first and we can assert on it directly.
    tryCatch(causal_ontology_envo(obo), error = function(e) e)
  })

  # The guard must win even though the file is perfectly readable: the
  # documented contract is "stops rather than falling back to a partial
  # parse".
  expect_s3_class(err, "error")
  # edaphos' own actionable error, not R's raw namespace failure.
  expect_false(inherits(err, "packageNotFoundError"))
  expect_match(conditionMessage(err), "Install the `ontologyIndex` package",
               fixed = TRUE)
})

# ---- Shape of the returned frame -------------------------------------------

test_that("causal_ontology_envo() returns one id/term/label row per [Term] stanza", {
  skip_if_not_installed("ontologyIndex")

  obo <- write_envo_fixture()
  out <- causal_ontology_envo(obo)

  expect_s3_class(out, "data.frame")
  # Documented columns, in the documented order.
  expect_identical(names(out), c("id", "term", "label"))
  # One row per stanza: nothing dropped, nothing invented by the
  # is_a propagation.
  expect_identical(nrow(out), length(.envo_fixture_ids))
  # Persistent ENVO ids survive verbatim -- this is the whole point of
  # preferring ENVO over the hand-curated Cerrado vocabulary.
  expect_identical(out$id, .envo_fixture_ids)
  # Characters, not factors.
  expect_type(out$id, "character")
  expect_type(out$term, "character")
  expect_type(out$label, "character")
})

test_that("causal_ontology_envo() keeps the raw OBO name in `label`", {
  skip_if_not_installed("ontologyIndex")

  obo <- write_envo_fixture()
  out <- causal_ontology_envo(obo)

  # `label` must be the un-normalised name, otherwise the frame cannot
  # be reported back to a human. Would fail if `label` were ever
  # overwritten with the normalised `term`.
  expect_identical(out$label, .envo_fixture_labels)
  expect_false(identical(out$label, out$term))
})

# ---- The normalisation contract --------------------------------------------

test_that("causal_ontology_envo() normalises labels to lower_snake_case terms", {
  skip_if_not_installed("ontologyIndex")

  obo <- write_envo_fixture()
  out <- causal_ontology_envo(obo)

  # Element-wise, so a mis-aligned vapply/order bug is caught too.
  expect_identical(out$term, .envo_expected_terms)

  # And each rule spelled out on the row that exercises it, so a
  # failure says which part of the regex broke.

  # Lowercasing (breaks if tolower() is dropped).
  expect_identical(out$term[out$id == "ENVO:00000004"], "gibbsite")

  # Spaces and parentheses both become underscores, and " (" -- a run of
  # two non-alphanumerics -- collapses to exactly one.
  expect_identical(out$term[out$id == "ENVO:00000001"],
                   "cerrado_sensu_stricto_soil")

  # ":" "." "/" and spaces all normalise; digits are kept.
  expect_identical(out$term[out$id == "ENVO:00000002"], "ph_1_2_5_h2o_kcl")

  # Leading "-- " and trailing " --" are stripped, not turned into
  # edge underscores (breaks if gsub("^_|_$", "", term) is dropped).
  expect_identical(out$term[out$id == "ENVO:00000003"], "ferralsol_oxisol")

  # Comma and hyphen normalise; adjacent digits are not merged.
  expect_identical(out$term[out$id == "ENVO:00000005"],
                   "soil_organic_carbon_0_30_cm")
})

test_that("causal_ontology_envo() terms satisfy the lower_snake_case invariants", {
  skip_if_not_installed("ontologyIndex")

  obo <- write_envo_fixture()
  out <- causal_ontology_envo(obo)

  # Output alphabet: lowercase alphanumerics and "_" only. Fails if the
  # character class stops matching some punctuation, or if tolower()
  # goes away.
  expect_false(any(grepl("[^a-z0-9_]", out$term)))
  # Runs collapse to a single underscore.
  expect_false(any(grepl("__", out$term)))
  # No edge underscores.
  expect_false(any(grepl("^_|_$", out$term)))
  # Nothing collapsed to the empty string.
  expect_true(all(nzchar(out$term)))
})

# ---- Input guard ------------------------------------------------------------

test_that("causal_ontology_envo() refuses a path that does not exist", {
  skip_if_not_installed("ontologyIndex")

  missing <- file.path(tempdir(), "definitely-not-here-9f3a1c.obo")
  expect_false(file.exists(missing))
  # stopifnot(file.exists(path)) -- without it, ontologyIndex would
  # raise a much less obvious connection error.
  expect_error(causal_ontology_envo(missing), "file\\.exists\\(path\\)")
})

# ---- causal_ontology_agrovoc(): the part that needs no network ---------------
# The SPARQL round trip cannot be tested offline, but the argument
# checks run before any request object is built, so they can.

test_that("causal_ontology_agrovoc() validates `query` before touching the network", {
  # A non-character query would be pasted into the SPARQL FILTER as-is.
  expect_error(causal_ontology_agrovoc(42), "is\\.character\\(query\\)")
  # A vector would silently query only the first element.
  expect_error(causal_ontology_agrovoc(c("clay", "sand")),
               "length\\(query\\) == 1")
  expect_error(causal_ontology_agrovoc(character(0)),
               "length\\(query\\) == 1")
  # An empty query makes CONTAINS() match every concept in AGROVOC.
  expect_error(causal_ontology_agrovoc(""), "nzchar\\(query\\)")
})
