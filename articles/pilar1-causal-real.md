# Pilar 1 on real data — identified causal effects on Cerrado SOC

## 1. Why this vignette exists

The original Pillar 1 vignette
([`vignette("pilar1-causal")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar1-causal.md))
derives the backdoor-adjustment machinery from Pearl 2009 and
demonstrates it on the `br_cerrado` synthetic dataset that ships with
the package. As of **v1.4.0** the Pillar 1 story runs on **real
Brazilian Cerrado data**: 1 095 WoSIS topsoil profiles from the
`wosis_latest` layer ([Batjes et al. 2024](#ref-Batjes2024wosis)), the
same dataset the v1.3.1 case-study benchmark consumes. The three
quantities below are publishable causal estimates, not pedagogic toys.

    #> 
    #> Attaching package: 'dplyr'
    #> The following objects are masked from 'package:stats':
    #> 
    #>     filter, lag
    #> The following objects are masked from 'package:base':
    #> 
    #>     intersect, setdiff, setequal, union

> **The results in this article have been withdrawn.** They were
> computed from `causal_cerrado_real.rds`, a bundle of 1,095 real WoSIS
> profiles that stopped shipping with `edaphos` on 2026-08-28 because it
> carried third-party soil measurements. The package can no longer
> reproduce them, so the article stops here rather than display numbers
> that nothing in it backs. See `PROVENANCE.md` in the repository.

Batjes, N. H., L. Calisto, and L. M. de Sousa. 2024. “Providing
Quality-Assessed and Standardised Soil Data to Support Global Mapping
and Modelling (WoSIS Snapshot 2023).” *Earth System Science Data* 16:
4735–65. <https://doi.org/10.5194/essd-16-4735-2024>.
