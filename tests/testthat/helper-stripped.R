# Several tests used to verify that a shipped bundle's headline number was
# reproducible from the per-record rows shipped beside it. Those rows were
# third-party measurements and no longer ship, so that particular check cannot
# run from the tarball any more.
#
# Where a surviving aggregate still carries the claim, the test was repointed
# at it. Where the assertion was intrinsically about records -- an arithmetic
# identity between a stored bound and a stored truth, say -- the test skips
# through this helper rather than being deleted, so the repo keeps a record of
# what used to be checked and why it stopped.
#
# The check itself did not disappear: it moved into the generator under
# data-raw/, which still runs against a live fetch.
skip_if_stripped <- function(bundle, element) {
  testthat::skip(sprintf(
    paste("%s$%s was removed by data-raw/strip_third_party_records.R:",
          "it carried third-party measurements. The claim is now checked",
          "against the bundle's aggregate table; the per-record identity is",
          "verified in the generator, not from the shipped file."),
    bundle, element))
}
