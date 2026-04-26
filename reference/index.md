# Package index

## Pilar 1 — Causal AI

Backdoor adjustment, LLM-driven Knowledge Graphs, causal discovery,
effect posteriors.

- [`causal_4d_plot()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_4d_plot.md)
  : Plot a time-varying causal effect trajectory

- [`causal_adjustment_set()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_adjustment_set.md)
  : Suggest a backdoor-adjustment set from a DAG

- [`causal_augment_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_augment_dag.md)
  : Augment a base DAG with edges from a Knowledge Graph

- [`causal_augment_diff()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_augment_diff.md)
  : Diff between a base DAG and an augmented DAG

- [`causal_cerrado_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_cerrado_dag.md)
  :

  DAG tailored to the bundled Cerrado dataset (`br_cerrado`)

- [`causal_cerrado_real_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_cerrado_real_dag.md)
  : Real-data Cerrado pedogenetic DAG

- [`causal_clorpt_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_clorpt_dag.md)
  : Canonical CLORPT pedogenetic DAG

- [`causal_corpus_deduplicate()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_corpus_deduplicate.md)
  : Deduplicate a corpus by DOI or title

- [`causal_corpus_openalex()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_corpus_openalex.md)
  : Query the OpenAlex corpus

- [`causal_corpus_scielo()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_corpus_scielo.md)
  : Query the SciELO literature corpus

- [`causal_effect_bootstrap()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_effect_bootstrap.md)
  : Block-bootstrap the backdoor-adjusted direct effect

- [`causal_effect_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_effect_posterior.md)
  : Posterior distribution of a backdoor-adjusted direct effect

- [`causal_effect_time_varying()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_effect_time_varying.md)
  : Time-varying causal effect beta(t) over a sliding window

- [`causal_effect_trend_test()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_effect_trend_test.md)
  : Mann-Kendall trend test on a beta(t) trajectory

- [`causal_estimate_effect()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_estimate_effect.md)
  : Estimate a causal effect using DAG-guided backdoor adjustment

- [`causal_iv_first_stage()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_first_stage.md)
  : First-stage regression diagnostics for an IV design

- [`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md)
  : Two-stage least squares (2SLS) instrumental variable estimator

- [`causal_iv_from_embeddings()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_from_embeddings.md)
  : Fit 2SLS using foundation-model (or proxy) embeddings as instruments

- [`causal_iv_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_posterior.md)
  : Bootstrap posterior for a 2SLS effect as an edaphos_posterior

- [`causal_iv_sargan_test()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_sargan_test.md)
  : Sargan test for instrument over-identification

- [`causal_kg_add_edge()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_add_edge.md)
  : Add a causal edge to a pedogenetic Knowledge Graph

- [`causal_kg_alignment()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_alignment.md)
  : Align Knowledge-Graph node labels to a canonical vocabulary

- [`causal_kg_edges()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_edges.md)
  : Tidy edge list of a pedogenetic Knowledge Graph

- [`causal_kg_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_load.md)
  : Load a Knowledge Graph from disk

- [`causal_kg_new()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_new.md)
  : Create an empty pedogenetic Knowledge Graph

- [`causal_kg_rank_edges()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_rank_edges.md)
  : Rank Knowledge-Graph edges by evidence strength

- [`causal_kg_rename()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_rename.md)
  : Rename Knowledge-Graph nodes from an alignment mapping

- [`causal_kg_save()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_save.md)
  : Save a Knowledge Graph to disk

- [`causal_kg_to_dagitty()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_to_dagitty.md)
  :

  Export a Knowledge Graph to a `dagitty` DAG

- [`causal_kg_to_turtle()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_to_turtle.md)
  : Export a Knowledge Graph to RDF 1.1 Turtle

- [`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md)
  : Extract causal claims from text via an LLM backend

- [`causal_llm_ingest_abstract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_abstract.md)
  : Ingest an abstract into a pedogenetic Knowledge Graph

- [`causal_llm_ingest_abstract_voted()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_abstract_voted.md)
  : Ingest an abstract into a KG via multi-extractor voting

- [`causal_llm_ingest_corpus()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_corpus.md)
  : Ingest a corpus of abstracts into a Knowledge Graph (resumable)

- [`causal_llm_vote()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_vote.md)
  : Multi-extractor consensus over LLM-extracted causal claims

- [`causal_ontology_agrovoc()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc.md)
  : Query the AGROVOC SPARQL endpoint

- [`causal_ontology_agrovoc_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align.md)
  : Live AGROVOC alignment for a vector of free-text terms

- [`causal_ontology_agrovoc_align_batch()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align_batch.md)
  : Concurrent AGROVOC alignment for a large vocabulary

- [`causal_ontology_cerrado()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_cerrado.md)
  : Canonical Cerrado pedometric vocabulary

- [`causal_ontology_envo()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_envo.md)
  : Load an ENVO ontology from a local .obo file

- [`causal_sensitivity_from_iv()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_from_iv.md)
  :

  Sensitivity analysis of an `edaphos_causal_iv` fit

- [`causal_sensitivity_from_lm()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_from_lm.md)
  :

  Sensitivity analysis of an `lm` backdoor fit

- [`causal_sensitivity_grid()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_grid.md)
  : Bias-adjustment grid for a Cinelli & Hazlett sensitivity contour

- [`causal_sensitivity_summary()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_sensitivity_summary.md)
  : Cinelli & Hazlett (2020) sensitivity summary for a causal effect

- [`causal_structure_learn()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_structure_learn.md)
  : Structure learning from horizon data -\> Knowledge Graph

- [`llm_annotation_export()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_annotation_export.md)
  : Export a reviewed JSONL into the canonical gold-standard format

- [`llm_annotation_launch()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_annotation_launch.md)
  : Launch the interactive gold-standard review app

- [`llm_annotation_to_zenodo()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_annotation_to_zenodo.md)
  : Package a reviewed gold-standard into a Zenodo-ready deposit bundle

- [`llm_annotation_validate()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_annotation_validate.md)
  : Validate a gold-standard JSONL file

- [`llm_annotation_vocabulary()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_annotation_vocabulary.md)
  : Canonical pedometric vocabulary for LLM-KG claims

- [`llm_benchmark_cost()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_benchmark_cost.md)
  : Estimate per-1 000-claim extraction cost

- [`llm_benchmark_kappa()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_benchmark_kappa.md)
  : Pairwise Cohen's kappa between backends on edge presence

- [`llm_benchmark_match()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_benchmark_match.md)
  : Match extracted LLM claims against a gold-standard set

- [`llm_benchmark_metrics()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_benchmark_metrics.md)
  : Compute precision / recall / F1 from a match table

- [`llm_benchmark_simulate()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_benchmark_simulate.md)
  : Simulate backend extractions from a gold-standard set

- [`llm_preannotate()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_preannotate.md)
  : Pre-annotate a corpus with an LLM to produce draft claims

- [`summary(`*`<edaphos_causal_kg>`*`)`](https://hugomachadorodrigues.github.io/edaphos/reference/summary.edaphos_causal_kg.md)
  : One-line summary of a Knowledge Graph

## Pilar 2 — Physics-Informed ML

Pedogenetic ODE, Bayesian posterior, Neural ODE + ensemble.

- [`piml_bayes_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_bayes_posterior.md)
  : Posterior predictive distribution from a Bayesian Pillar 2 fit
- [`piml_hierarchical_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_hierarchical_fit.md)
  : Hierarchical Neural ODE over multiple pedons (Pillar 2 × Pillar 5)
- [`piml_hierarchical_predict()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_hierarchical_predict.md)
  : Predict depth profiles for new locations from covariates
- [`piml_neural_ode_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit.md)
  : Fit a Neural ODE depth profile (Pillar 2, deep variant)
- [`piml_neural_ode_fit_ensemble()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit_ensemble.md)
  : Train a deep ensemble of Neural ODEs for uncertainty quantification
- [`piml_neural_ode_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_posterior.md)
  : Posterior predictive distribution from a Pillar 2 deep ensemble
- [`piml_neural_ode_predict()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_predict.md)
  : Predict a depth profile from a fitted Neural ODE
- [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)
  : Fit a Physics-Informed depth-profile model (Pillar 2)
- [`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md)
  : Bayesian posterior for the Pillar 2 pedogenetic ODE
- [`piml_profile_fit_group()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_group.md)
  : Fit the Pillar 2 profile model to a group of pedons independently
- [`piml_profile_predict()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_predict.md)
  : Forward-integrate a Physics-Informed depth profile
- [`piml_qkrr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_qkrr_fit.md)
  : Fit a Physics-Informed Quantum Kernel Ridge Regression
- [`piml_quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_quantum_kernel.md)
  : Physics-informed quantum kernel via ODE-residual fusion
- [`predict(`*`<edaphos_piml_bayes>`*`)`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_piml_bayes.md)
  : Posterior predictive distribution of a Bayesian Pillar 2 fit
- [`predict(`*`<edaphos_piml_neural_ode_ensemble>`*`)`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_piml_neural_ode_ensemble.md)
  : Predictive posterior from a Neural-ODE deep ensemble

## Pilar 3 — 4D Pedometry

ConvLSTM, rollout, mass-balance physics loss, stochastic EnKF.

- [`temporal_convlstm_cell()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_cell.md)
  : Build a standalone ConvLSTM cell (Pillar 3 primitive)
- [`temporal_convlstm_ensemble_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_ensemble_fit.md)
  : K-seed deep ensemble of stacked ConvLSTMs
- [`temporal_convlstm_ensemble_rollout()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_ensemble_rollout.md)
  : Roll every ensemble member forward and stack the forecasts
- [`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md)
  : Fit a stacked ConvLSTM on a 4D covariate cube
- [`temporal_convlstm_mcdropout_predict()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_mcdropout_predict.md)
  : MC-dropout predictive draws from a ConvLSTM fit
- [`temporal_convlstm_predict()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_predict.md)
  : Predict with a fitted stacked ConvLSTM
- [`temporal_convlstm_rollout()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_rollout.md)
  : Multi-step rollout forecast
- [`temporal_cube_to_tensor()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_cube_to_tensor.md)
  : Assemble a 4D input tensor-ready array from a synthetic cube
- [`temporal_kalman_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_kalman_update.md)
  : Ensemble Kalman update of a Pillar 3 forecast by new point
  observations
- [`temporal_piml_loss()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_piml_loss.md)
  : Physics-informed ConvLSTM mass-balance loss (Pilar 2 x Pilar 3)
- [`temporal_synth_soc_cube()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_synth_soc_cube.md)
  : Generate a synthetic 4D soil-dynamics cube (Pillar 3 helper)

## Pilar 4 — Foundation Models

SimCLR + MoCo v2 pretraining, Zenodo-hosted weights, raster extraction.

- [`foundation_build_cerrado_stack()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_build_cerrado_stack.md)
  : Build a minimal Cerrado raster stack for the v1.9.1 IV benchmark

- [`foundation_embed_at_coords()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_embed_at_coords.md)
  : Extract foundation-model embeddings at a set of query coordinates

- [`foundation_finetune_ensemble()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_finetune_ensemble.md)
  : Deep-ensemble fine-tune of a Pillar 4 foundation encoder

- [`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md)
  : Fine-tune or linearly probe a Pillar 4 encoder for classification

- [`foundation_fit_regressor()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_regressor.md)
  : Fine-tune or linearly probe a Pillar 4 encoder for regression

- [`foundation_mcdropout_predict()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_mcdropout_predict.md)
  : MC-dropout predictive draws from a fine-tuned Pillar 4 fit

- [`foundation_moco_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed.md)
  : Extract backbone embeddings from a fitted MoCo v2 encoder

- [`foundation_moco_embed_raster()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed_raster.md)
  : Apply a fitted MoCo v2 encoder over a full raster mosaic

- [`foundation_moco_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain.md)
  : Pillar 4 – MoCo v2 pre-training on raster covariate patches

- [`foundation_moco_pretrain_tiles()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain_tiles.md)
  : Dataset-backed MoCo v2 pre-training for planetary-scale corpora

- [`foundation_simclr_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_simclr_embed.md)
  : Extract embeddings from a pretrained SimCLR encoder

- [`foundation_simclr_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_simclr_pretrain.md)
  : SimCLR pre-training on raster covariate patches (Pillar 4 scaffold)

- [`foundation_tile_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_align.md)
  : Align multiple raster sources onto a common analysis grid

- [`foundation_tile_dataset()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_dataset.md)
  :

  Build a lazy patch dataset over a
  [`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)

- [`foundation_tile_source_era5()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_era5.md)
  : ERA5 source stub (needs Copernicus CDS key)

- [`foundation_tile_source_modis()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_modis.md)
  : MODIS source stub (needs NASA EarthData credentials)

- [`foundation_tile_source_soilgrids()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_soilgrids.md)
  : Fetch a SoilGrids 250 m stack over an AoI

- [`foundation_tile_source_srtm()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_srtm.md)
  : Fetch an SRTM elevation raster over an AoI

- [`foundation_tile_source_worldclim()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_worldclim.md)
  : Fetch a WorldClim 2.1 climate stack over an AoI

- [`foundation_weights_download()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_download.md)
  : Download a pretrained Pillar 4 encoder from Zenodo

- [`foundation_weights_list()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_list.md)
  : Catalogue of pretrained Pillar 4 encoders

- [`foundation_weights_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_load.md)
  :

  Load a pretrained encoder into an `edaphos_foundation_moco` wrapper

- [`predict(`*`<edaphos_foundation_classifier>`*`)`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_foundation_classifier.md)
  : Predict class probabilities / labels from a fine-tuned classifier

- [`predict(`*`<edaphos_foundation_regressor>`*`)`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_foundation_regressor.md)
  : Predict numeric targets from a fine-tuned regressor

- [`predict(`*`<edaphos_foundation_ensemble>`*`)`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_foundation_ensemble.md)
  : Predict with an edaphos_foundation_ensemble

## Pilar 5 — Active Learning

Hybrid policy, BatchBALD, physics gate, posterior calibration.

- [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md)
  : Fit a Quantile Regression Forest for Active Learning
- [`al_history()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_history.md)
  : Extract the learning curve from a fitted Active-Learning model
- [`al_initial_design()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_initial_design.md)
  : Initial sampling design via Conditioned Latin Hypercube (cLHS)
- [`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md)
  : Closed-loop Autonomous Active Learning for soil mapping
- [`al_physics_gate_piml()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml.md)
  : Build a physics gate from a PIML profile fit
- [`al_physics_gate_piml_hierarchical()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml_hierarchical.md)
  : Per-location physics gate backed by a hierarchical PIML fit
- [`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md)
  : Query the most informative unlabeled candidates
- [`al_query_batchbald()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_batchbald.md)
  : BatchBALD information-theoretic batch acquisition
- [`al_query_bhs()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_bhs.md)
  : Bayesian Hierarchical Active Learning (Pilar 7 x Pilar 5)
- [`al_query_causal()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_causal.md)
  : Causal Active Learning: query the next sample(s) that most reduce
  the uncertainty of a targeted causal effect
- [`al_query_diffusion()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_diffusion.md)
  : Diffusion-posterior-driven AL (Pilar 9 x Pilar 5)
- [`al_query_neural_operator()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_neural_operator.md)
  : Causal-driven AL via Neural Operator disagreement (Pilar 8 x Pilar
  5)
- [`al_query_temporal()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_temporal.md)
  : Temporal Active Learning: rank candidate cells by their Kalman gain
  norm after the latest EnKF assimilation
- [`al_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_update.md)
  : Append newly labeled samples and refit the model
- [`active_learning_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/active_learning_posterior.md)
  : Posterior predictive distribution of an edaphos Active-Learning fit

## Pilar 6 — Quantum ML

ZZFeatureMap, Quantum KRR, Qiskit VQE, organo-mineral Hamiltonians.

- [`quantum_feature_map()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_feature_map.md)
  : Quantum feature map (Pillar 6)

- [`quantum_hamiltonian()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian.md)
  : Build a quantum Hamiltonian from Pauli-string coefficients

- [`quantum_hamiltonian_from_pyscf()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_from_pyscf.md)
  : Build a quantum Hamiltonian from a molecular geometry

- [`quantum_hamiltonian_h2()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_h2.md)
  : Molecular H2 in the Bravyi-Kitaev-tapered 2-qubit basis

- [`quantum_hamiltonian_ising_1d()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_ising_1d.md)
  : Transverse-field Ising Hamiltonian on an n-qubit chain

- [`quantum_hamiltonian_organo_mineral()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_organo_mineral.md)
  : Toy organo-mineral Hamiltonian (4-qubit Fe + ligand coupling)

- [`quantum_hamiltonian_organo_mineral_nature()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_organo_mineral_nature.md)
  : Organo-mineral Hamiltonians derived from ab initio molecular models

- [`quantum_ibmq_available()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_available.md)
  : Check whether an IBM Quantum backend is reachable

- [`quantum_ibmq_backends()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_backends.md)
  : List IBM Quantum backends available to the current account

- [`quantum_ibmq_least_busy()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_least_busy.md)
  : Pick the least-busy operational IBM Quantum backend

- [`quantum_ibmq_submit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_submit.md)
  : Submit a single expectation-value PUB to IBM Quantum hardware

- [`quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_kernel.md)
  : Quantum kernel Gram matrix via ZZFeatureMap overlap

- [`quantum_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_fit.md)
  : Fit a Quantum Kernel Ridge Regression (Pillar 6)

- [`quantum_krr_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_posterior.md)
  : GP-equivalent posterior for a Quantum Kernel Ridge Regression fit

- [`quantum_nature_available()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_nature_available.md)
  : Check whether the qiskit-nature + PySCF stack is available

- [`quantum_nature_total_energy()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_nature_total_energy.md)
  : Total molecular energy from an active-space VQE result

- [`quantum_scale()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_scale.md)
  :

  Rescale a covariate matrix into `[lower, upper]` column-wise

- [`quantum_vqe_exact()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_exact.md)
  : Exact ground-state energy via classical diagonalisation

- [`quantum_vqe_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_fit.md)
  : Variational Quantum Eigensolver (Pillar 6 main entry point)

## Pilar 7 — Bayesian Hierarchical Spatial (v2.3.0+)

Gaussian process + Gibbs sampler (R fast-path / RcppArmadillo /
spBayes).

- [`bhs_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/bhs_fit.md)
  : Fit a Bayesian hierarchical spatial linear model (Pilar 7)
- [`predict(`*`<edaphos_bhs>`*`)`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_bhs.md)
  : Predict at new sites from a fitted Bayesian hierarchical spatial
  model

## Pilar 8 — Neural Operators (v2.4.0+)

DeepONet + FNO over depth function space.

- [`no_deeponet_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/no_deeponet_fit.md)
  : Fit a DeepONet for depth-profile operators
- [`no_fno_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/no_fno_fit.md)
  : Fit a 1-D Fourier Neural Operator for depth-profile operators

## Pilar 9 — Diffusion Models (v2.5.0+)

DDPM with cosine schedule + ancestral sampling.

- [`dm_cosine_schedule()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_cosine_schedule.md)
  : Build a DDPM noise schedule
- [`dm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_fit.md)
  : Train a tiny DDPM on a collection of soil-map patches
- [`dm_sample()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_sample.md)
  : Sample new soil-map patches from a trained DDPM

## Pilar 10 — Graph Attention Networks (v2.6.0+)

k-NN co-location graphs + multi-head attention; v3.6.0 sparse.

- [`gnn_build_graph()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_build_graph.md)
  : Build a k-NN co-location graph from a profile frame
- [`gnn_causal_discovery()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_causal_discovery.md)
  : Graph-based causal discovery (Pilar 10 x Pilar 1)
- [`gnn_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_embed.md)
  : Node-level embeddings from a fitted GAT
- [`gnn_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_fit.md)
  : Fit a Graph Attention Network on a WoSIS-style co-location graph

## Cross-pillar bridges (v1.9.x + v2.0.0 + v3.0.0)

Foundation embeddings as causal instruments; quantum kernels over
foundation embeddings; six v3.0.0 bridges (P7/8/9 x P5 + P10 x P1 + P2 x
P3 + P6 x P10).

- [`qf_embed_reduce()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_embed_reduce.md)
  : Reduce foundation-model embeddings to PCs and scale to quantum range
- [`qf_kernel_compare()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_kernel_compare.md)
  : Compare quantum, RBF, and linear kernels on the same feature set
- [`qf_krr_benchmark()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_krr_benchmark.md)
  : Benchmark quantum-foundation KRR against classical baselines
- [`qf_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_krr_fit.md)
  : Quantum Kernel Ridge Regression on foundation embeddings
- [`qf_krr_on_gat_embeddings()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_krr_on_gat_embeddings.md)
  : Quantum KRR over GAT node embeddings (Pilar 6 x Pilar 10)
- [`al_query_batchbald()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_batchbald.md)
  : BatchBALD information-theoretic batch acquisition
- [`al_query_bhs()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_bhs.md)
  : Bayesian Hierarchical Active Learning (Pilar 7 x Pilar 5)
- [`al_query_causal()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_causal.md)
  : Causal Active Learning: query the next sample(s) that most reduce
  the uncertainty of a targeted causal effect
- [`al_query_diffusion()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_diffusion.md)
  : Diffusion-posterior-driven AL (Pilar 9 x Pilar 5)
- [`al_query_neural_operator()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_neural_operator.md)
  : Causal-driven AL via Neural Operator disagreement (Pilar 8 x Pilar
  5)
- [`al_query_temporal()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_temporal.md)
  : Temporal Active Learning: rank candidate cells by their Kalman gain
  norm after the latest EnKF assimilation
- [`gnn_causal_discovery()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_causal_discovery.md)
  : Graph-based causal discovery (Pilar 10 x Pilar 1)
- [`temporal_piml_loss()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_piml_loss.md)
  : Physics-informed ConvLSTM mass-balance loss (Pilar 2 x Pilar 3)

## Unified uncertainty API (v1.6.0)

Common edaphos_posterior class + single calibration diagnostic.

- [`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md)
  :

  Calibration diagnostics for an `edaphos_posterior`

- [`uncertainty_plot_reliability()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_plot_reliability.md)
  : Reliability diagram from a calibration result

- [`edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_posterior.md)
  : Unified posterior object for the edaphos pillars

- [`as_edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/as_edaphos_posterior.md)
  :

  Coerce a native pillar object to `edaphos_posterior`

- [`autoplot.edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/autoplot.edaphos_posterior.md)
  :

  Default ggplot for an `edaphos_posterior`

- [`edaphos_bias()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_bias.md)
  : Mean bias (observed minus predicted)

- [`edaphos_ece()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_ece.md)
  : Expected calibration error (ECE) for a regression reliability
  diagram

- [`edaphos_interval_score()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_interval_score.md)
  : Interval score (Gneiting and Raftery 2007)

- [`edaphos_mae()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_mae.md)
  : Mean absolute error

- [`edaphos_metrics_summary()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_metrics_summary.md)
  : Summarise a pointwise + interval prediction against observations

- [`edaphos_picp()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_picp.md)
  : Prediction-interval coverage probability (PICP)

- [`edaphos_r2()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_r2.md)
  : Coefficient of determination (Nash-Sutcliffe efficiency)

- [`edaphos_rmse()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_rmse.md)
  : Root-mean-square error

- [`edaphos_zenodo_release()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_zenodo_release.md)
  : Build a Zenodo-ready release bundle for the edaphos package

## Benchmark wrappers (v3.1.0)

Plug-and-play wrappers for the 6-pilar WoSIS Cerrado benchmark.

- [`benchmark_fit_p10_gat()`](https://hugomachadorodrigues.github.io/edaphos/reference/benchmark_fit_p10_gat.md)
  : Benchmark wrapper: Pilar 10 – GAT seed-ensemble on k-NN graph
- [`benchmark_fit_p1_causal()`](https://hugomachadorodrigues.github.io/edaphos/reference/benchmark_fit_p1_causal.md)
  : Benchmark wrapper: Pilar 1 – DAG-adjusted OLS + parametric bootstrap
- [`benchmark_fit_p6_quantum()`](https://hugomachadorodrigues.github.io/edaphos/reference/benchmark_fit_p6_quantum.md)
  : Benchmark wrapper: Pilar 6 – bootstrap-ensembled quantum KRR

## LLM-KG production pipeline (v3.10.0)

Resumable 10k+ abstract orchestrator + Ollama pre-flight.

- [`llm_kg_ollama_check()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_kg_ollama_check.md)
  : Check whether a local Ollama server is reachable
- [`llm_kg_pipeline_run()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_kg_pipeline_run.md)
  : Run the Pilar 1 LLM-KG pipeline on a (potentially large) corpus

## Bundled datasets

- [`br_cerrado`](https://hugomachadorodrigues.github.io/edaphos/reference/br_cerrado.md)
  : Synthetic Cerrado soil sample for edaphos vignettes
- [`br_amazon`](https://hugomachadorodrigues.github.io/edaphos/reference/br_amazon.md)
  : Synthetic Amazon-rainforest soil sample (NW Brazil)
- [`br_pantanal`](https://hugomachadorodrigues.github.io/edaphos/reference/br_pantanal.md)
  : Synthetic Pantanal-wetland soil sample (MS, Brazil)

## Package roadmap

- [`edaphos-roadmap`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos-roadmap.md)
  : Roadmap and status of the six pillars of edaphos
