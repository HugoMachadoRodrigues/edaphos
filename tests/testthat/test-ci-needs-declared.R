# ---------------------------------------------------------------------------
# `needs:` in a workflow has to point at something.
#
# r-lib/actions/setup-r-dependencies reads `needs: X` as "also install
# whatever DESCRIPTION lists under Config/Needs/X". Three workflows declared
# needs: website, needs: check and needs: coverage while DESCRIPTION had no
# Config/Needs field at all, so all three resolved to nothing.
#
# The consequence was nil -- each workflow also listed its packages under
# extra-packages, so the jobs worked -- which is why it went unnoticed. It is
# still worth closing: a `needs:` that silently resolves to an empty set is a
# declaration a reader trusts and a machine ignores, and the day someone
# removes a line from extra-packages expecting Config/Needs to cover it, the
# job breaks for a reason nothing explains.
# ---------------------------------------------------------------------------

test_that("every needs: in a workflow has a matching Config/Needs in DESCRIPTION", {
  root <- NA_character_
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "DESCRIPTION")) &&
        dir.exists(file.path(d, ".github"))) { root <- d; break }
    up <- dirname(d); if (identical(up, d)) break; d <- up
  }
  skip_if(is.na(root), "not running from a source checkout")

  wfs <- list.files(file.path(root, ".github", "workflows"), "[.]ya?ml$",
                    full.names = TRUE)
  skip_if(!length(wfs), "no workflows")

  needed <- unique(unlist(lapply(wfs, function(f) {
    x <- grep("^\\s*needs:\\s*", readLines(f, warn = FALSE), value = TRUE)
    trimws(sub("^\\s*needs:\\s*", "", x))
  })))
  needed <- needed[nzchar(needed)]
  skip_if(!length(needed), "no needs: declarations")

  fields <- colnames(read.dcf(file.path(root, "DESCRIPTION")))
  missing <- needed[!paste0("Config/Needs/", needed) %in% fields]

  expect_equal(missing, character(0),
               info = paste("these needs: resolve to nothing, because",
                            "DESCRIPTION declares no Config/Needs field for them:",
                            paste(missing, collapse = ", ")))
})
