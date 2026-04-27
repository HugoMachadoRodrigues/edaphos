# Security policy for edaphos

## Reporting a vulnerability

If you discover a security vulnerability in **edaphos**, please do
**NOT** open a public GitHub issue. Instead, send a private email to:

**<rodrigues.machado.hugo@gmail.com>**

Include in your report:

- A description of the vulnerability (what is at risk?).
- Reproduction steps (a minimal example or pointer to the affected
  function).
- The version of `edaphos` you tested against
  (`packageVersion("edaphos")`).
- Your assessment of severity (e.g. CVSS-style: low / medium / high /
  critical).
- Optional: a suggested fix.

## Acknowledgement timeline

| Step                                   | Target turnaround                 |
|----------------------------------------|-----------------------------------|
| Acknowledge receipt                    | Within 3 business days            |
| Initial assessment                     | Within 7 business days            |
| Patch release (when severity warrants) | 2-6 weeks depending on complexity |
| Public disclosure                      | After patched release on CRAN     |

## Scope

In scope:

- Code in this repository (`R/`, `src/`, `inst/`, `data/`, `tests/`).
- The pkgdown site (<https://hugomachadorodrigues.github.io/edaphos/>).
- CI workflows under `.github/workflows/`.

Out of scope (please report directly to the upstream maintainer):

- Vulnerabilities in dependencies (Rcpp, RcppArmadillo, torch, terra,
  dagitty, bnlearn, ranger, …).
- Vulnerabilities in CRAN / GitHub / Zenodo / OpenAlex platforms
  themselves.

## Confidentiality

All reports are treated as confidential. Reporters who request
attribution in the patch release notes will be named (with permission).
Anonymous reports are equally welcome and will be acknowledged
generically.

## Bounty

`edaphos` is a research-grade open-source package with no commercial
backer; we do not run a bug-bounty programme. Significant disclosures
will be acknowledged in the README and any associated peer-reviewed
publication.
