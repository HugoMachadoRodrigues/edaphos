# edaphos cheatsheets

One-page references for each of the 10 research pillars.  Use these
to remember the key API surface; see `vignette("getting-started")`
or the per-pillar vignettes for narrative tutorials.

| Pillar | Theme                                | Cheatsheet         |
|------:|--------------------------------------|--------------------|
|   1   | Causal AI (DAGs + LLM-KG)            | [pillar1.md](pillar1.md)  |
|   2   | Physics-Informed ML (depth ODE)      | [pillar2.md](pillar2.md)  |
|   3   | 4D Pedometry (ConvLSTM + EnKF)       | [pillar3.md](pillar3.md)  |
|   4   | Foundation Models (SimCLR / MoCo)    | [pillar4.md](pillar4.md)  |
|   5   | Active Learning                      | [pillar5.md](pillar5.md)  |
|   6   | Quantum ML (ZZFeatureMap KRR)        | [pillar6.md](pillar6.md)  |
|   7   | Bayesian Hierarchical Spatial        | [pillar7.md](pillar7.md)  |
|   8   | Neural Operators (DeepONet / FNO)    | [pillar8.md](pillar8.md)  |
|   9   | Diffusion Models (DDPM)              | [pillar9.md](pillar9.md)  |
|  10   | Graph Attention Networks             | [pillar10.md](pillar10.md) |

These cheatsheets are not shipped in the package tarball
(`.Rbuildignore` excludes the `cheatsheets/` directory). They live in
the GitHub repository; the pkgdown site links to them from its navbar
("Cheatsheets") but does not render them.
