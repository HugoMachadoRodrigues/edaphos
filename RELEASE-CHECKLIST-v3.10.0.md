# Release checklist for edaphos v3.10.0

Status as of this commit: code 100 % ready, CI green, all
artefacts regenerated.  The four steps below require YOUR hand
on the controls because they are state-changing actions on
third-party services tied to your personal identity (CRAN, GitHub,
ORCID/Zenodo).

---

## 1. CRAN submission

The package source tarball is already built at:

  /tmp/edaphos_release_tarballs/edaphos_3.10.0.tar.gz   (17 MB)

To submit, open R in the package root and run:

```r
devtools::submit_cran()
```

This will:

  1. Re-build the source tarball (or re-use the existing one).
  2. Open `cran-comments.md` for a final review pass.
  3. Pop up the CRAN web form pre-filled with your maintainer
     details.
  4. Ask you to confirm "Do you want to submit?".  Type **YES**.

CRAN will then email you within 24 hours with the auto-check
results.  If anything fails, fix and resubmit; otherwise the
package will appear at <https://cran.r-project.org/package=edaphos>
within ~48 hours.

---

## 2. rOpenSci pre-submission

Open <https://github.com/ropensci/software-review/issues/new?template=editor_review.md>
and paste the contents of:

  inst/rosc/submission.md

Submit the issue.  An rOpenSci editor will reply within ~3 days
with a scope check and either accept-for-review or
decline-with-suggestions.

---

## 3. Zenodo concept-DOI new version

The bundle is already built at:

  tools/zenodo_release.zip   (22.2 MB, 24 files)

Steps:

  1. Open <https://zenodo.org/deposit/19683708> (the current
     concept DOI for edaphos).
  2. Click the **New version** button.
  3. Upload `tools/zenodo_release.zip` as the only file.
  4. Update the version field to `v3.10.0`.
  5. Update the description with the v3.10.0 highlights from
     `NEWS.md` (calibrated PICP, Rcpp Gibbs, sparse GAT, regional
     datasets, error messages, docs reorg, LLM-KG harness).
  6. Click **Publish** -- this mints a new version DOI under the
     same concept DOI.

The new DOI will appear as `10.5281/zenodo.<n>` and is
automatically linked to the concept DOI badge in the README.

---

## 4. GitHub Pages source change

Currently, GH Pages is set to **legacy Jekyll mode** (source =
`main` / `/`), which fails to render the .Rmd files in
`vignettes/` and `articles/`.  The pkgdown workflow already
deploys a properly rendered site to the `gh-pages` branch on every
push to `main`.

**One-click fix**:

  1. Open <https://github.com/HugoMachadoRodrigues/edaphos/settings/pages>.
  2. Under **Build and deployment**, change **Source** from
     "Deploy from a branch" with `main` / `/` to either:
     - **GitHub Actions** (recommended -- uses the pkgdown
       workflow's deployment artefact directly), OR
     - **Deploy from a branch** with **branch = `gh-pages`,
       folder = `/`** (works with the existing peaceiris/
       actions-gh-pages step in `.github/workflows/pkgdown.yaml`).
  3. Save.

The site will be live at
<https://hugomachadorodrigues.github.io/edaphos/> within ~1 minute
of the next push (or immediately if you trigger a workflow_dispatch
on the `pkgdown.yaml` workflow).

---

## What I (the AI) cannot do for you

* CRAN submission requires interactive confirmation tied to your
  CRAN maintainer email.
* rOpenSci issues are publishing actions on a public forum; the
  package author should be the one filing.
* Zenodo upload is a state-changing action on an archival service
  tied to your ORCID.
* GH Pages source change is a repository settings change
  (modifying access controls / public surface).

The four steps above are the residual human-in-the-loop.  After
they are done, edaphos v3.10.0 will be live on CRAN +
documentation site + Zenodo, and queued for rOpenSci peer review.
