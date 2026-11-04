# Pillar 1 — Causal AI

DAG-based backdoor adjustment + LLM-extracted Knowledge Graphs for
pedogenetic causal inference.

## Core API

```r
# Build a Knowledge Graph from a list of abstracts (LLM-driven)
kg <- causal_kg_new()
kg <- causal_augment_dag(kg, abstract = "...", backend = "ollama")

# Or learn a DAG from data (bnlearn)
kg_data <- causal_structure_learn(
  data      = my_df,
  variables = c("map_mm", "elev", "soc"),
  method    = "hc",
  whitelist = data.frame(from = c("map_mm"), to = c("soc"))
)

# Identify a backdoor-adjustment set
adj <- causal_adjustment_set(my_dag, exposure = "map_mm",
                              outcome  = "soc")

# Effect estimation with a posterior
post <- causal_effect_posterior(
  data = my_df, dag = my_dag,
  exposure = "map_mm", outcome = "soc",
  estimator = "lm", B = 500L
)
uncertainty_calibrate(post, truth = NULL)  # diagnostics
```

## Bridge: `gnn_causal_discovery()` (Pillar 10 × Pillar 1)

Augments the feature frame with GAT node embeddings as nuisance
conditioners for `causal_structure_learn()`; returned DAG is
restricted to the user features.

## Key references

* Pearl (2009) *Causality* — backdoor criterion.
* Scutari (2010) bnlearn JSS — score- and constraint-based search.
* Cinelli & Hazlett (2020) — sensitivity bounds.

## See also

* `vignette("getting-started")` — Pillar 1 in 2 minutes.
* `vignette("pillar1-causal")` — full tutorial on synthetic data.
* `vignette("causal-discovery-trio")` — Pillar 1 × P5 × P7 bridge.
* `articles/pillar1-causal-real.Rmd` — case study on 1 095 WoSIS profiles.
