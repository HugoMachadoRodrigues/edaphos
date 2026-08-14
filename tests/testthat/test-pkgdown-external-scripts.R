# ---------------------------------------------------------------------------
# Third-party JavaScript on the published site must be pinned and verified.
#
# _pkgdown.yml injected <script src=".../mermaid@11/..."> into the head of
# every page, with no integrity attribute. Two problems, and each makes the
# other worse: `@11` is a floating major tag, so the bytes change whenever
# upstream publishes, and nothing checked what arrived. SECURITY.md:37 puts
# the pkgdown site in scope, so a third party's ability to change the
# JavaScript on every page of it is an exposure the project has declared it
# cares about.
#
# THE TWO FIXES ARE NOT SEPARABLE. An integrity hash on a floating tag breaks
# the site the moment upstream publishes; a pinned version without a hash
# still trusts whatever the CDN returns. This asserts both together, and
# specifically rejects the combination that looks safe and is not.
# ---------------------------------------------------------------------------

test_that("every external script in _pkgdown.yml is version-pinned and hashed", {
  root <- NA_character_
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "_pkgdown.yml"))) { root <- d; break }
    up <- dirname(d); if (identical(up, d)) break; d <- up
  }
  skip_if(is.na(root), "_pkgdown.yml not in this checkout")

  txt <- readLines(file.path(root, "_pkgdown.yml"), warn = FALSE)
  # Ignore comment lines: the block explaining the fix quotes a URL.
  txt <- txt[!grepl("^\\s*(#|<!--)", txt)]
  one <- paste(txt, collapse = "\n")

  tags <- regmatches(one, gregexpr("<script[^>]*src=[^>]*>", one))[[1]]
  skip_if(!length(tags), "no external scripts declared")

  for (tg in tags) {
    src <- sub('.*src="([^"]+)".*', "\\1", tg)
    # Local assets are the project's own and need neither.
    if (!grepl("^https?://", src)) next

    expect_true(grepl("integrity=", tg, fixed = TRUE),
                info = paste("no integrity attribute on", src))
    expect_true(grepl("crossorigin=", tg, fixed = TRUE),
                info = paste("integrity without crossorigin is ignored by",
                             "browsers for cross-origin requests:", src))

    # A hash is worthless against a moving target. Require a full
    # major.minor.patch in the URL, not `@11` or `@latest`.
    ver <- regmatches(src, regexpr("@[0-9]+(\\.[0-9]+)*", src))
    expect_true(length(ver) == 1L &&
                  grepl("^@[0-9]+\\.[0-9]+\\.[0-9]+", ver),
                info = paste("version is not fully pinned, so the integrity",
                             "hash will break when upstream publishes:", src))
  }
})
