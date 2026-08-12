# ---------------------------------------------------------------------------
# Is every shipped bundle still the one its script would produce?
#
# THE DEFECT THIS EXISTS FOR. inst/extdata/case_cerrado_results.rds published a
# conclusion for four months that its own -- already fixed -- defect had
# produced. The fix landed in data-raw/case_cerrado_run.R; the bundle was never
# re-run; its stamped version and date sat frozen at 1.3.1 / 2026-04-23 and
# said nothing. Both halves of the published sentence were wrong. It was found
# by reading, not by any check, because no test read a provenance field at all.
#
# WHY A HASH AND NOT A DATE. A build date cannot answer "has the script changed
# since?". File mtimes are not in git and differ in every clone. A hash of the
# producing script's CONTENT, stored at build time and recomputed here, can.
#
# STAGED, DELIBERATELY. 23 of 29 bundles predate this contract and carry no
# block. Failing on them would mean turning the test off, which is how checks
# die. So: a bundle WITHOUT provenance is reported and skipped; a bundle WITH
# it must be consistent, and that set only grows. The count is asserted below
# so the migration cannot quietly go backwards.
# ---------------------------------------------------------------------------

extdata_dir <- function() {
  p <- system.file("extdata", package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata")
  p
}

pkg_root <- function() {
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "DESCRIPTION")) &&
        dir.exists(file.path(d, "data-raw"))) return(d)
    up <- dirname(d); if (identical(up, d)) break; d <- up
  }
  NA_character_
}

all_bundles <- function() {
  d <- extdata_dir()
  skip_if_not(dir.exists(d), "extdata not available")
  list.files(d, pattern = "[.]rds$", full.names = TRUE)
}

test_that("every bundle carrying provenance is consistent with its script", {
  root <- pkg_root()
  skip_if(is.na(root), "not running from a source checkout; data-raw is absent")

  bundles <- all_bundles()
  expect_gt(length(bundles), 20L)

  stale <- character(0); missing_script <- character(0); ok <- character(0)
  for (f in bundles) {
    b <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(b) || !is.list(b) || is.null(b$provenance)) next
    v <- edaphos_provenance_check(b, root = root)
    if (isTRUE(v$ok)) ok <- c(ok, basename(f))
    else if (grepl("not in this checkout", v$reason %||% ""))
      missing_script <- c(missing_script, paste0(basename(f), ": ", v$reason))
    else if (isFALSE(v$ok))
      stale <- c(stale, paste0(basename(f), ": ", v$reason))
  }

  expect_equal(missing_script, character(0))
  # The assertion the case_cerrado defect would have failed.
  expect_equal(stale, character(0))
  expect_gt(length(ok), 0L)
})

test_that("the provenance block has the shape the contract promises", {
  root <- pkg_root()
  skip_if(is.na(root), "not running from a source checkout")
  n_with <- 0L
  for (f in all_bundles()) {
    b <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(b) || !is.list(b) || is.null(b$provenance)) next
    n_with <- n_with + 1L
    p <- b$provenance
    for (fld in c("script", "script_sha256", "hash_algo",
                  "package_version", "r_version", "built_at"))
      expect_true(fld %in% names(p),
                  info = paste(basename(f), "lacks", fld))
    expect_true(startsWith(p$script, "data-raw/"), info = basename(f))
    expect_true(nchar(p$script_sha256) > 16L, info = basename(f))
  }
  expect_gt(n_with, 0L)
})

test_that("the migration does not go backwards", {
  skip_on_cran()
  root <- pkg_root(); skip_if(is.na(root), "not running from a source checkout")
  n <- sum(vapply(all_bundles(), function(f) {
    b <- tryCatch(readRDS(f), error = function(e) NULL)
    is.list(b) && !is.null(b$provenance)
  }, TRUE))
  # 6 bundles carried the block when the contract landed. This number is a
  # ratchet: it may rise as scripts are re-run, and a drop means a bundle was
  # rebuilt by something that skipped edaphos_provenance().
  expect_gte(n, 6L)
})

test_that("the check distinguishes stale from unbindable", {
  # These are different states wanting different remedies, and collapsing them
  # would make the staged migration impossible: an un-migrated bundle would
  # look like a defect.
  expect_true(is.na(edaphos_provenance_check(list(x = 1))$ok))

  p <- edaphos_provenance(script = "data-raw/piml_ptf_bulk_density.R")
  skip_if(is.na(p$script_sha256), "producing script not in this checkout")
  expect_true(isTRUE(edaphos_provenance_check(list(provenance = p),
                                              root = pkg_root())$ok))
  p$script_sha256 <- strrep("0", 64L)
  v <- edaphos_provenance_check(list(provenance = p), root = pkg_root())
  expect_false(v$ok)
  expect_match(v$reason, "has changed")
})
