# edaphos – Introduction and Scientific Motivation

This file is the **high-density narrative** that complements the
README’s “at-a-glance” pitch and the per-pilar cheatsheets in
`cheatsheets/`. Read this when you want the WHY before the HOW.

> *From Greek **edaphos** – “soil, ground.”*

------------------------------------------------------------------------

## Why edaphos exists: the scientific gap

Zhang and Wadoux (2026) ask a deceptively simple question: **Can Digital
Soil Mapping Be Causal?** Their answer:

> *“In principle, yes – but only if the DSM model specifies the
> mechanisms and processes that link soil-forming factors to soil
> properties, rather than relying on associations themselves.”*

They identify three conditions that must be met for causal inference
from observational data (and soil surveys are almost always
observational):

1.  **An explicit causal model** – a DAG over the variables of interest.
2.  **Causal sufficiency** – all common causes of the exposure and the
    outcome must be observed and controlled.
3.  **Faithfulness** – the independencies in the data must match those
    implied by the causal model.

And they distinguish two competing views of causality:

| View          | Logic                                                                            | DSM challenge                                                    |
|---------------|----------------------------------------------------------------------------------|------------------------------------------------------------------|
| Successionist | Regularities / repeatable associations                                           | Simpson’s paradox; spurious associations; no temporal sequencing |
| Generative    | Soil-forming factors act through explicit processes that produce soil properties | Requires process-informed models; satisfies condition 1          |

`edaphos` operationalises the **generative paradigm** end-to-end.

------------------------------------------------------------------------

## The ten research pillars

Each pillar confronts a specific methodological gap of the contemporary
DSM literature. See `cheatsheets/` for one-page API references and
`vignettes/` for narrative tutorials.

|  \# | Pillar                        | Gap addressed                                                            |
|----:|-------------------------------|--------------------------------------------------------------------------|
|   1 | Causal AI                     | Conflation of variable importance with causal effect                     |
|   2 | Physics-Informed ML           | Black-box predictors that ignore pedogenetic depth dynamics              |
|   3 | 4D Pedometry                  | Static maps that ignore spatio-temporal evolution                        |
|   4 | Foundation Models             | Reliance on labelled data only, ignoring vast unlabelled raster archives |
|   5 | Active Learning               | Fixed sampling designs blind to model-uncertainty geography              |
|   6 | Quantum ML                    | Classical kernels saturate at high-dimensional covariate stacks          |
|   7 | Bayesian Hierarchical Spatial | Frequentist GP without honest predictive intervals                       |
|   8 | Neural Operators              | Profile prediction discretised to a fixed depth grid                     |
|   9 | Diffusion Models              | Generative simulators absent from the DSM toolbox                        |
|  10 | Graph Attention Networks      | Independence assumption between profiles ignores co-location structure   |

------------------------------------------------------------------------

## Cross-pillar bridges (v3.0.0)

Six bridges compose two pillars into a single API:

| Bridge                                                                                                               | Pillars  | Purpose                                                 |
|----------------------------------------------------------------------------------------------------------------------|----------|---------------------------------------------------------|
| [`al_query_neural_operator()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_neural_operator.md) | P8 x P5  | Operator-vs-ODE disagreement as AL priority             |
| [`al_query_diffusion()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_diffusion.md)             | P9 x P5  | DDPM posterior-spread as AL priority                    |
| [`al_query_bhs()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_bhs.md)                         | P7 x P5  | Thompson-sampling AL via BHS posterior                  |
| [`gnn_causal_discovery()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_causal_discovery.md)         | P10 x P1 | GAT embeddings as nuisance conditioners in DAG learning |
| [`temporal_piml_loss()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_piml_loss.md)             | P2 x P3  | ODE-derived mass-balance loss for ConvLSTM              |
| [`qf_krr_on_gat_embeddings()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_krr_on_gat_embeddings.md) | P6 x P10 | Quantum kernel over GAT node embeddings                 |

------------------------------------------------------------------------

## Unified uncertainty API (v1.6.0)

Every pillar’s predictive output funnels through a single S3 class:

``` r
post <- as_edaphos_posterior(any_pilar_fit)
uncertainty_calibrate(post, truth = test$y)
# -> CRPS, PICP_50/80/90/95, MPIW_50/80/90/95
```

This is what makes the head-to-head benchmarks in `inst/extdata/`
possible: P4/P5/P6/P7/P10 are scored on the same calibration metrics on
the same 5 spatial folds.

------------------------------------------------------------------------

## Honest readout (v3.4.0)

The 1 095-profile WoSIS Cerrado benchmark
(`inst/extdata/benchmark_wosis_6pilar.rds`):

| Method            |  RMSE |   R^2 | PICP_90 | MPIW_90 | CRPS |
|-------------------|------:|------:|--------:|--------:|-----:|
| **P1 Causal+OLS** | 13.94 | 0.082 |   0.953 |    46.9 | 6.80 |
| P4 Foundation+QRF | 14.07 | 0.033 |   0.889 |    37.6 | 5.93 |
| P5 QRF            | 14.12 | 0.064 |   0.879 |    37.2 | 5.85 |
| P7 BHS            | 14.13 | 0.070 |   0.812 |    36.7 | 6.97 |
| P6 Quantum KRR    | 14.55 | 0.000 |   0.601 |    16.7 | 7.43 |
| P10 GAT ensemble  | 15.18 | 0.000 |   0.825 |    35.6 | 8.11 |

- RMSE lies in a tight 13.9 - 15.2 g/kg band: the Cerrado subset does
  not discriminate between architectures on point accuracy.
- Calibration (PICP_90) splits the field at the v3.4.0 calibrated
  posteriors – everyone is now within 0.6-0.95 of nominal 0.9.
- P1 Causal+OLS is the single best RMSE + R^2 + CRPS performer at
  negligible cost (~0.7 s / fold) – a useful interpretable baseline.

P2, P3, P8, P9 target depth profiles, temporal stacks, and raster
patches respectively; they have their own task-appropriate benchmarks in
`vignettes/`.

------------------------------------------------------------------------

## Where to go next

- [`vignette("getting-started")`](https://hugomachadorodrigues.github.io/edaphos/articles/getting-started.md)
  – 200-line tour of all 10 pilares.
- `cheatsheets/` – one-page references per pilar.
- [`vignette("uncertainty-unified")`](https://hugomachadorodrigues.github.io/edaphos/articles/uncertainty-unified.md)
  – the cross-pilar `edaphos_posterior` contract.
- [`vignette("capstone-cerrado-campaign")`](https://hugomachadorodrigues.github.io/edaphos/articles/capstone-cerrado-campaign.md)
  – end-to-end Cerrado sampling-campaign narrative integrating all
  pillars.

------------------------------------------------------------------------

## Citation

``` bibtex
@misc{rodrigues2026edaphos,
  author       = {Rodrigues, Hugo},
  title        = {{edaphos}: Disruptive Algorithms for Digital Soil Mapping},
  year         = {2026},
  howpublished = {GitHub + Zenodo},
  doi          = {10.5281/zenodo.19683708}
}
```
