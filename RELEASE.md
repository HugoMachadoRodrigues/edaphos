# edaphos — public-release checklist (v2.9.1)

This file lists the **four remaining manual actions** a maintainer must
execute to complete a public release.  Everything else (code, tests,
metadata, bundle generation, pkgdown config, CRAN comments, rOpenSci
submission template) is already in place.

The automated machinery assumes you are the package maintainer with
(a) a GitHub account with push rights to the repository,
(b) a Zenodo account linked to that GitHub repo, and
(c) an R session with the package installed.

---

## 1. Update the Zenodo concept DOI for v2.9.0+

The badge in README currently resolves to **v0.2.0** because the
concept DOI was minted early.  To bring it up to date:

```r
# From the package root, in an R session:
devtools::load_all(".")
edaphos_zenodo_release(
  output_dir = "tools/zenodo_release",
  title = sprintf(
    "edaphos %s — Disruptive algorithms for Digital Soil Mapping",
    utils::packageVersion("edaphos")
  ),
  include_tarball = TRUE,   # requires devtools
  zip = TRUE
)
```

This produces **two deliverables**:

1. `tools/zenodo_release/` — directory with `gold_standard` bundles,
   `metadata.json` (DataCite-ready), `manifest.csv` with SHA-256
   checksums, `ZENODO-README.md`, and the package tarball.
2. `tools/zenodo_release.zip` — ready for direct upload.

**Manual steps** on zenodo.org:
1. Open <https://zenodo.org/deposit/new>.
2. Drag-and-drop `zenodo_release.zip` (or the individual files).
3. Copy fields from `metadata.json` into the Zenodo web form
   (title, creators with ORCID, keywords, description, license =
   MIT).
4. On the "Related/alternate identifiers" panel, add
   `isNewVersionOf: 10.5281/zenodo.19683708` so the concept DOI
   aggregates across versions.
5. Click **Publish**.
6. Copy the minted version DOI into `CITATION.cff` under
   `identifiers:` as a new entry, and also update
   `.zenodo.json` if it still points to an older DOI.

---

## 2. Enable GitHub Pages for the pkgdown site

The workflow `.github/workflows/pkgdown.yaml` is already wired; it
deploys `docs/` to the `gh-pages` branch on every push to `main`.
Enable the site **one time**:

1. Open <https://github.com/HugoMachadoRodrigues/edaphos/settings/pages>.
2. Under "Build and deployment" / "Source", pick **Deploy from a
   branch**.
3. Choose branch **`gh-pages`** and folder **`/ (root)`**.
4. Save.

Within ~90 seconds the site is live at
<https://hugomachadorodrigues.github.io/edaphos/>.  Every subsequent
push auto-rebuilds.  Remove or reduce the badge staleness-warning in
the README once live.

---

## 3. Submit to CRAN

The `cran-comments.md` file at the repo root contains the standard
CRAN submission context (test environments, optional-dependency
rationale, etc.).  Before submitting:

```r
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

CRAN's policy requires **at most 24 MB of installed package**,
**no "large files"** in `inst/` (the 1.9 MB
`benchmark_wosis_p4_p5_p7.rds` is below the implicit ceiling but
worth measuring: `tools::checkRdaFiles("inst/extdata/")` on a
resaved version could shrink further with `compress = "xz"`).

After submission you get an automated email from CRAN within a few
hours.  Any **WARNING** must be fixed and re-submitted; **NOTEs**
that are honest trade-offs (e.g. "checking for future file
timestamps") can be explained in the `cran-comments.md` text.

---

## 4. Open an rOpenSci pre-submission inquiry

The full template is in **`inst/rosc/submission.md`**.  To submit:

1. Open <https://github.com/ropensci/software-review/issues/new/choose>.
2. Pick **"Pre-submission inquiry"**.
3. Paste the content of `inst/rosc/submission.md` into the issue.
4. Wait for an editor response (typically 3–7 days).  If scope is
   accepted, you move to a regular **Software Review** issue.

The package qualifies for rOpenSci's "Statistical software" category
(Bayesian / spatial / machine learning).  Editors may ask for:

* Coverage metrics (use `covr::package_coverage()` before submitting
  to pre-empt the question).
* A link to a CRAN submission (do #3 first).
* A clear statement of scope vs. alternatives -- already present in
  `inst/rosc/submission.md` section "Closest analogues on CRAN /
  rOpenSci".

---

## Post-release

Once all four steps are executed:

* Update the README badge row:
  - Replace the v0.2.0-era Zenodo DOI badge with the new
    version-specific DOI.
  - Add CRAN status and pkgdown-site badges.
* Close the roadmap items `v3.0.0: CRAN + rOpenSci submission` in
  the README roadmap table.
* Post a brief announcement on the Pedometrics community lists
  (AG-Pedo, linkedin/pedometrics.org, X) pointing at the Zenodo DOI.

These four manual steps are the **only** remaining blockers between
the current local state and full public release.
