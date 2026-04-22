# edaphos 1.2.0 (in development)

## Pillar 4 — Foundation Models

### New features

* **Downstream fine-tuning API** for supervised heads on top of any
  self-supervised MoCo v2 / SimCLR encoder:
  `foundation_fit_classifier()` and `foundation_fit_regressor()`.
  Both support linear probing (`freeze_backbone = TRUE`) and full
  fine-tuning with a two-group learning-rate schedule
  (Kornblith, Shlens and Le 2019). Target normalisation is handled
  internally in the regressor.
* **Device dispatch** (`device = "cpu" | "mps" | "cuda"`) wired
  through `foundation_moco_pretrain_tiles()` and the fine-tuning
  API. Apple Silicon MPS and NVIDIA CUDA backends are exercised
  end-to-end.
* **Published pretrained encoders** distributed via **Zenodo**
  under CC-BY-4.0. Three new functions consume the registry:
  `foundation_weights_list()`,
  `foundation_weights_download()` (with SHA-256 verification and
  an on-disk cache under `tools::R_user_dir("edaphos")`), and
  `foundation_weights_load()` (rebuilds the in-memory
  `edaphos_foundation_moco` wrapper). The first published encoder,
  `edaphos-cerrado-moco-v1`, was pretrained on 50 000 Cerrado
  tiles (SoilGrids + WorldClim + SRTM) on an Apple M1 Max MPS.

### Bug fixes

* `foundation_moco_embed()` now forces the encoder into `eval()`
  mode before the forward pass so BatchNorm uses its saved
  `running_mean` / `running_var` instead of batch-level statistics.
  Previously the returned embeddings depended on the current batch
  composition and disagreed with any reloaded copy of the same
  encoder.
* `foundation_tile_source_soilgrids()` now accepts both the human-
  readable depth strings (`"0-5cm"`, `"5-15cm"`, …) documented in
  its `@param` block and the integer form that
  `geodata::soil_world()` expects internally.

# edaphos 1.1.0

## Pillar 2 — Physics-Informed ML

* **Bayesian posterior** over the pedogenetic-ODE parameters via
  `piml_profile_fit_bayesian()` — Laplace approximation (default)
  and adaptive random-walk Metropolis (Haario, Saksman and
  Tamminen 2001). Posterior predictive draws are returned by the
  new `predict.edaphos_piml_bayes()` method with optional
  observation-noise inclusion.
* **Deep-ensemble** approximation to the Neural-ODE predictive
  posterior via `piml_neural_ode_fit_ensemble()`
  (Lakshminarayanan, Pritzel and Blundell 2017).

## Pillar 5 — Autonomous Active Learning

* **BatchBALD** information-theoretic batch acquisition via
  `al_query_batchbald()` (Kirsch, van Amersfoort and Gal 2019).
  Greedy log-det selection with Schur-complement / Cholesky
  incremental updates; submodular, hence a (1 − 1/e) optimality
  guarantee.

## Pillar 1 — Causal AI

* **Structure learning** from horizon data via
  `causal_structure_learn()` (`bnlearn` bridge: `hc`, `tabu`,
  `pc-stable`, `mmhc` with optional bootstrap edge strengths).
* **Multi-extractor LLM voting** via `causal_llm_vote()` and
  `causal_llm_ingest_abstract_voted()` — majority / weighted /
  intersection rules over N independent LLM backends.

# edaphos 1.0.0

## Pillar 1 — Paper-scale knowledge graphs

* **Persistence** via `causal_kg_save()` / `causal_kg_load()`
  (portable RDS edge-list; survives `igraph` version bumps).
* **RDF 1.1 Turtle export** via `causal_kg_to_turtle()` — reified
  `rdf:Statement` per edge preserves confidence / evidence /
  source(s) / timestamp; pure-R emitter, no RDF library needed.
* **Multi-source edge ranking** via `causal_kg_rank_edges()` and a
  `summary.edaphos_causal_kg()` method.
* **Concurrent AGROVOC alignment** via
  `causal_ontology_agrovoc_align_batch()` with parallel HTTP
  dispatch through `httr2::req_perform_parallel()` and an
  idempotent on-disk cache.

# edaphos 0.9.0

## Pillar 6 — Quantum ML

* **Shot-based VQE** (`backend = "aer_shots"`) via
  `qiskit_aer.primitives.EstimatorV2`.
* **Full IBM Quantum Runtime dispatch** (`backend = "ibmq"`) with
  ISA transpilation and M3 / ZNE mitigation
  (Kim et al. 2023).
* **qiskit-nature bridge** — `quantum_hamiltonian_from_pyscf()`
  and curated presets for carboxylate, catechol ortho-diol and
  Fe(III)–formate organo-mineral motifs.

# edaphos 0.8.0

## Pillar 1 — Literature-scale extraction

* Paginated OpenAlex corpus client, `causal_corpus_deduplicate()`,
  resumable disk-cached `causal_llm_ingest_corpus()`, live AGROVOC
  SPARQL alignment with on-disk cache, 100-abstract bundled demo
  (`inst/extdata/cerrado_claims_real_corpus.jsonl`).
