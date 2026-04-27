---
name: Feature request
about: Propose a new function, bridge, or pillar feature
title: "[feature] "
labels: ["enhancement", "triage"]
assignees: []
---

## Motivation

<!-- Which scientific gap or pedometric workflow does this address?
If it relates to one of the 10 pillars, mention which (Pilar 1
Causal AI, Pilar 7 BHS, Pilar 10 GAT, ...). -->

## Proposed API

```r
# Sketch the function signature + return type:
my_new_function(arg1, arg2, ..., backend = c("r", "torch"))
#> -> a list / data.frame / edaphos_posterior
```

## Why an existing function does not cover this

<!-- e.g. "bhs_fit() handles spatial GP but not spatio-temporal
GP", or "the v3.0.0 al_query_diffusion bridge is for raster
patches; we need a P9×P1 bridge for KG-conditioned diffusion". -->

## Reference / prior art

<!-- Citations to papers / packages / Stack Overflow threads that
inform the design. -->

## Are you willing to send a PR?

* [ ] Yes, after a design discussion
* [ ] Yes, I have a draft already
* [ ] No, but happy to test
