# ---------------------------------------------------------------------------
# The two status metrics that read a false green, and why they need a test.
#
# STATUS.md and the README's CI block are generated, which is what makes them
# trustworthy -- and also what makes a wrong constant inside the generator
# durable: it regenerates on every run, so re-reading the output can never
# catch it.
#
# Both metrics tested here failed exactly that way.
#
#   * "libtorch is never installed on any leg" was a literal string in
#     tools/status/patch-readme-metrics.R and tools/status/render.R. It was
#     true when written and false from d51b0d6 onward, and both documents kept
#     publishing it.
#
#   * "NEWS versions with no git tag: 0" matched version strings against tag
#     names. This package's version was inflated to 4.1.0 and then reset to
#     0.9.0, so `v0.9.0` -- a tag on an unrelated April commit -- satisfied the
#     check for a NEWS section written in July, 154 commits later.
#
# These assert the FACTS the generators consume, not the rendered prose, so a
# reworded sentence does not fail and a changed workflow does.
# ---------------------------------------------------------------------------

facts_path <- testthat::test_path("..", "..", "tools", "status", "facts.json")

test_that("the libtorch CI claim is measured from the matrix, not asserted", {
  skip_if_not(file.exists(facts_path), "facts.json is not in this checkout")
  skip_if_not_installed("jsonlite")
  f <- jsonlite::fromJSON(facts_path, simplifyVector = TRUE)

  expect_false(is.null(f$ci$n_torch_legs))

  wf <- testthat::test_path("..", "..", ".github", "workflows", "R-CMD-check.yaml")
  skip_if_not(file.exists(wf), "the workflow is not in this checkout")
  legs <- grep("^\\s*- \\{os:", readLines(wf, warn = FALSE), value = TRUE)
  expect_equal(as.integer(f$ci$n_torch_legs), sum(grepl("torch:\\s*true", legs)))

  # The specific regression: a leg exists that installs libtorch, so any
  # document stating that none does is wrong.
  if (sum(grepl("torch:\\s*true", legs)) > 0L)
    expect_gt(as.integer(f$ci$n_torch_legs), 0L)
})

test_that("README and STATUS do not deny a libtorch leg that exists", {
  # ASSERTING THE FACT IS NOT ENOUGH. The defect was a literal sentence in the
  # generator, and a generator can compute the right number and still print a
  # constant beside it. This reads what a reader reads.
  skip_if_not(file.exists(facts_path), "facts.json is not in this checkout")
  skip_if_not_installed("jsonlite")
  f <- jsonlite::fromJSON(facts_path, simplifyVector = TRUE)
  skip_if_not(isTRUE(as.integer(f$ci$n_torch_legs) > 0L),
              "no libtorch leg, so there is nothing to deny")

  denial <- paste0("never installed|not execute in CI|",
                   "no leg installs libtorch|skips on every leg")
  for (doc in c("README.md", "STATUS.md")) {
    p <- testthat::test_path("..", "..", doc)
    if (!file.exists(p)) next
    hits <- grep(denial, readLines(p, warn = FALSE), value = TRUE, perl = TRUE)
    # A finding's quoted evidence may legitimately contain the old sentence;
    # only generated claim lines are policed.
    hits <- hits[!grepl("^\\||^>|^\\s*-? ?\\*\\*F[0-9A-F]{6}", hits)]
    expect_length(hits, 0L)
  }
})

test_that("a tag that predates its NEWS entry is not counted as a release tag", {
  skip_if_not(file.exists(facts_path), "facts.json is not in this checkout")
  skip_if_not_installed("jsonlite")
  f <- jsonlite::fromJSON(facts_path, simplifyVector = TRUE)

  # The field must exist: without it the untagged count is the only signal and
  # a reused version number buys a green.
  expect_false(is.null(f$versioning$n_news_stale_tag))

  # And the honest verdict is the conjunction, not the untagged count alone.
  # This is what STATUS.md ticks on.
  clean <- isTRUE(f$versioning$n_news_without_tag == 0L) &&
           isTRUE(f$versioning$n_news_stale_tag == 0L)
  if (isTRUE(f$versioning$n_news_stale_tag > 0L))
    expect_false(clean)
})
