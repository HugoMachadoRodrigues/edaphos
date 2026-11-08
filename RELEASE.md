# edaphos — public-release checklist

**This is the only release checklist.** A second one,
`RELEASE-CHECKLIST-v3.10.0.md`, was deleted rather than merged: it was
written for a version that never existed, asserted “code 100 % ready, CI
green”, pointed at a tarball at `/tmp/edaphos_release_tarballs/` that is
not there, and named `peaceiris/actions-gh-pages` when
`.github/workflows/pkgdown.yaml:61` uses
`JamesIves/github-pages-deploy-action@v4.5.0`. Two checklists that
disagree are worse than one that is merely incomplete, because a reader
cannot tell which is authoritative.

**This file carries no version number on purpose.** Both predecessors
were headed with one (v2.9.1 and v3.10.0) and both went stale the moment
the version moved; the version this applies to is whatever `DESCRIPTION`
says, currently 2.0.0.

## The version is 2.0.0, and why

`v3.10.0` and `v4.0.0` – tags for inflated versions `NEWS.md` withdrew
as unreproducible – were deleted, locally and on the remote. The commits
they marked are still in `main`’s history; only the labels are gone.

`v0.1.0` to `v1.6.0` were **not** deleted, and are not withdrawn: each
is a public GitHub Release, and each is archived on Zenodo with its own
DOI under the concept DOI `10.5281/zenodo.19683708` (measured
2026-11-04: seventeen versions, v0.9.0 = `10.5281/zenodo.19697669`,
v1.6.0 = `10.5281/zenodo.19710162`). A Zenodo DOI cannot be deleted. The
development version was numbered 0.9.0 until November 2026, which made
it a different package wearing a used number; deleting the `v0.9.0` tag
would not have freed the number, because the DOI would remain.

**Decided by the maintainer on 2026-11-04: the first release is 2.0.0**,
the major version above the last public release, which also signals the
breaking changes since 1.6.0. Nothing is deleted. `release-tag.yaml`
checks that `v2.0.0` is free, that `NEWS.md` has its heading, and that
NEWS no longer says “development version”; it defaults to a dry run.

------------------------------------------------------------------------

The four steps below are manual because each is a state-changing action
on a third-party service tied to the maintainer’s identity. They are
**not** the only remaining work: `STATUS.md` is the live list of open
defects, and it is not empty. The previous version of this sentence
claimed everything else “is already in place”, which was the kind of
assertion this package has spent a campaign removing.

The automated machinery assumes you are the package maintainer with (a)
a GitHub account with push rights to the repository, (b) a Zenodo
account linked to that GitHub repo, and (c) an R session with the
package installed.

------------------------------------------------------------------------

## 1. Deposit 2.0.0 on Zenodo

The README badge is the concept DOI, which always resolves to the latest
deposited version – today 1.6.0, not 0.2.0 as an earlier version of this
file said. Once 2.0.0 is deposited the same badge resolves to it.

The GitHub-Zenodo integration appears to be active: each of the
seventeen GitHub Releases from 0.1.0 to 1.6.0 has a Zenodo deposit dated
the same day. If it still is, **publishing the GitHub Release `v2.0.0`
deposits it automatically**, using the metadata in `.zenodo.json` – so
check that file first: version 2.0.0, a description of what ships.
Confirm on the Zenodo record that the deposit appeared under the concept
DOI.

If the integration is off, deposit by hand:

``` r

# From the package root, in an R session:
devtools::load_all(".")
edaphos_zenodo_release(
  output_dir = "tools/zenodo_release",
  title = sprintf(
    "edaphos %s — Digital Soil Mapping with Causal, Physics-Informed and Generative Methods",
    utils::packageVersion("edaphos")
  ),
  include_tarball = TRUE,   # requires devtools
  zip = TRUE
)
```

This produces **two deliverables**:

1.  `tools/zenodo_release/` — directory with `gold_standard` bundles,
    `metadata.json` (DataCite-ready), `manifest.csv` with SHA-256
    checksums, `ZENODO-README.md`, and the package tarball.
2.  `tools/zenodo_release.zip` — ready for direct upload.

**Manual steps** on zenodo.org: 1. Open
<https://zenodo.org/deposit/new>. 2. Drag-and-drop `zenodo_release.zip`
(or the individual files). 3. Copy fields from `metadata.json` into the
Zenodo web form (title, creators with ORCID, keywords, description,
license = MIT). 4. On the “Related/alternate identifiers” panel, add
`isNewVersionOf: 10.5281/zenodo.19683708` so the concept DOI aggregates
across versions. 5. Click **Publish**. 6. Copy the minted version DOI
into `CITATION.cff` under `identifiers:` as a new entry, and also update
`.zenodo.json` if it still points to an older DOI.

------------------------------------------------------------------------

## 2. Enable GitHub Pages for the pkgdown site

The workflow `.github/workflows/pkgdown.yaml` is already wired; it
deploys to the `gh-pages` branch on every push to `main`, using
`JamesIves/github-pages-deploy-action`, pinned to the commit of v4.5.0.

Before enabling the site, note that the pkgdown build was **broken**
until the correctness campaign fixed it: the reference index aborted on
an unindexed `spatial_block_folds`, five vignettes were missing from the
articles index, and four navbar entries pointed at a top-level
`articles/` directory that pkgdown does not render. Both indices build
now; run
[`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html)
locally once before turning Pages on. Enable the site **one time**:

1.  Open
    <https://github.com/HugoMachadoRodrigues/edaphos/settings/pages>.
2.  Under “Build and deployment” / “Source”, pick **Deploy from a
    branch**.
3.  Choose branch **`gh-pages`** and folder **`/ (root)`**.
4.  Save.

Within ~90 seconds the site is live at
<https://hugomachadorodrigues.github.io/edaphos/>. Every subsequent push
auto-rebuilds. Remove or reduce the badge staleness-warning in the
README once live.

------------------------------------------------------------------------

## 3. Submit to CRAN

The `cran-comments.md` file at the repo root contains the standard CRAN
submission context (test environments, optional-dependency rationale,
etc.). Before submitting:

``` r

# Final checks
devtools::check(document = FALSE, vignettes = FALSE,
                 args = c("--as-cran"))
devtools::check_rhub()        # cross-platform: rhub builders
devtools::check_win_devel()   # Windows-devel smoke test

# Submit
devtools::release()
# or:
devtools::submit_cran()
```

CRAN’s policy caps the **source tarball at 5 MB**, which is the binding
constraint here: `R CMD build` currently produces about 5.3 MB, most of
it base64 figure data inside the built vignettes. Measure it before
submitting rather than assuming, and see `STATUS.md` for where the
remaining room is. (This paragraph used to cite a 1.9 MB
`benchmark_wosis_p4_p5_p7.rds`; that bundle is 37 KB.)

After submission you get an automated email from CRAN within a few
hours. Any **WARNING** must be fixed and re-submitted; **NOTEs** that
are honest trade-offs (e.g. “checking for future file timestamps”) can
be explained in the `cran-comments.md` text.

------------------------------------------------------------------------

## 4. Open an rOpenSci pre-submission inquiry

The full template is in **`inst/rosc/submission.md`**. To submit:

1.  Open
    <https://github.com/ropensci/software-review/issues/new/choose>.
2.  Pick **“Pre-submission inquiry”**.
3.  Paste the content of `inst/rosc/submission.md` into the issue.
4.  Wait for an editor response (typically 3–7 days). If scope is
    accepted, you move to a regular **Software Review** issue.

The package qualifies for rOpenSci’s “Statistical software” category
(Bayesian / spatial / machine learning). Editors may ask for:

- Coverage metrics (use
  [`covr::package_coverage()`](https://covr.r-lib.org/reference/package_coverage.html)
  before submitting to pre-empt the question).
- A link to a CRAN submission (do \#3 first).
- A clear statement of scope vs. alternatives – already present in
  `inst/rosc/submission.md` section “Closest analogues on CRAN /
  rOpenSci”.

------------------------------------------------------------------------

## Post-release

Once all four steps are executed:

- Record the 2.0.0 version DOI: add it to `CITATION.cff` under
  `identifiers:`, set `date-released`, and add it beside the concept-DOI
  badge in the README. Keep the concept-DOI badge: it resolves to the
  latest version by design.
- Add CRAN status and pkgdown-site badges.
- Mark “CRAN and rOpenSci submission of 2.0.0” done in the README’s
  “Releases and roadmap” section.
- Post a brief announcement on the Pedometrics community lists (AG-Pedo,
  linkedin/pedometrics.org, X) pointing at the Zenodo DOI.

These four steps are the manual, third-party half of a release. The
other half is whatever `STATUS.md` still lists as open.
