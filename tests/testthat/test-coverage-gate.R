# ---------------------------------------------------------------------------
# The coverage badge must mean something, and must measure the same package
# the check workflow does.
#
# Two defects sat behind one badge. There was no codecov configuration at all,
# so nothing enforced anything: coverage could fall to zero and the workflow
# would stay green. And test-coverage.yaml set no TORCH_INSTALL while
# R-CMD-check.yaml has a leg that does, so the two workflows measured
# different packages -- 26 of 74 files under R/ mention torch and carry 39% of
# its lines, and with libtorch absent every torch-gated test skips and those
# lines are reported as untested. The number was not low because the code is
# untested; it is low because the job measuring it could not run the tests.
#
# These assert the configuration, not a coverage percentage: the percentage is
# Codecov's to compute, and pinning it here would be a second source of truth.
# ---------------------------------------------------------------------------

repo_root <- function() {
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "DESCRIPTION")) &&
        dir.exists(file.path(d, ".github")))
      return(d)
    up <- dirname(d)
    if (identical(up, d)) break
    d <- up
  }
  NA_character_
}

test_that("a codecov configuration exists and gates something", {
  root <- repo_root()
  skip_if(is.na(root), "not running from a source checkout")
  skip_if_not_installed("yaml")

  cands <- file.path(root, c("codecov.yml", ".codecov.yml",
                             ".github/codecov.yml"))
  found <- cands[file.exists(cands)]
  expect_gt(length(found), 0L)

  cfg <- yaml::read_yaml(found[1])
  st <- cfg$coverage$status
  expect_false(is.null(st))
  # Both a project-level and a patch-level rule: without the patch rule,
  # new untested code is diluted by the existing average.
  expect_false(is.null(st$project))
  expect_false(is.null(st$patch))
})

test_that("the coverage job installs libtorch, like the check job's torch leg", {
  root <- repo_root()
  skip_if(is.na(root), "not running from a source checkout")
  cov <- file.path(root, ".github", "workflows", "test-coverage.yaml")
  chk <- file.path(root, ".github", "workflows", "R-CMD-check.yaml")
  skip_if_not(file.exists(cov) && file.exists(chk), "workflows not present")

  cl <- readLines(cov, warn = FALSE)
  # It must set TORCH_INSTALL at all -- the defect was saying nothing.
  expect_true(any(grepl("TORCH_INSTALL", cl)))
  # And actually install the runtime, not merely ask for it.
  expect_true(any(grepl("install_torch", cl, fixed = TRUE)))

  # The two workflows should share a cache key, or the ~2 GB download is
  # paid twice per run.
  key_of <- function(f) {
    x <- readLines(f, warn = FALSE)
    i <- grep("^\\s*key:\\s*libtorch-", x)
    if (!length(i)) NA_character_ else trimws(sub(".*key:", "", x[i[1]]))
  }
  expect_identical(key_of(cov), key_of(chk))
})
