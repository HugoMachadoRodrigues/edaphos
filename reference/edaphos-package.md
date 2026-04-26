# edaphos: Disruptive Algorithms for Digital Soil Mapping

`edaphos` is a research-oriented R package that implements frontier
algorithms for Digital Soil Mapping (DSM) beyond the regression-tree
state of the art (McBratney, Mendonça Santos and Minasny, 2003; Wadoux,
Minasny and McBratney, 2020). Its contributions are organised across
**six research pillars**, each confronting a specific methodological gap
of the contemporary literature and equipped with a vignette that derives
the governing object from first principles.

## Details

From Greek \\\epsilon\delta\alpha\phi o\varsigma\\ — "soil, ground."

## Six research pillars

- **1. Causal AI.**:

  DAG-backed backdoor adjustment via `dagitty` —
  [`causal_clorpt_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_clorpt_dag.md),
  [`causal_cerrado_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_cerrado_dag.md),
  [`causal_adjustment_set()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_adjustment_set.md),
  [`causal_estimate_effect()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_estimate_effect.md)
  — with an optional non-linear BART estimator via the `dbarts` Suggests
  dependency. An LLM-driven Knowledge-Graph extraction pipeline on top
  of `httr2`
  ([`causal_kg_new()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_new.md),
  [`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md),
  [`causal_llm_ingest_corpus()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_corpus.md),
  [`causal_augment_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_augment_dag.md))
  supports Ollama (Gemma 4), OpenAI and Anthropic backends. Corpus
  ingestion clients for SciELO
  ([`causal_corpus_scielo()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_corpus_scielo.md))
  and OpenAlex
  ([`causal_corpus_openalex()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_corpus_openalex.md))
  transparently page through their upstream APIs for
  multi-thousand-abstract pulls, deduplicated by DOI / title via
  [`causal_corpus_deduplicate()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_corpus_deduplicate.md).
  Production-grade ingestion over corpora of tens of thousands of
  abstracts is handled by
  [`causal_llm_ingest_corpus()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_corpus.md)'s
  `cache_dir` and `max_retries` arguments (resumable, idempotent,
  exponential backoff). Ontology alignment against the curated Cerrado
  vocabulary or **live FAO AGROVOC SPARQL**
  ([`causal_ontology_agrovoc_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align.md),
  `causal_kg_alignment(vocab = "agrovoc")`) is provided with on-disk
  caching, and a **concurrent batched alignment**
  ([`causal_ontology_agrovoc_align_batch()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align_batch.md))
  dispatches up to `max_active` parallel HTTP requests so a 10 k-node KG
  resolves in minutes instead of hours. Paper-scale KGs are persisted
  and audited via
  [`causal_kg_save()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_save.md)
  /
  [`causal_kg_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_load.md)
  (portable RDS edge-list),
  [`causal_kg_to_turtle()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_to_turtle.md)
  (W3C RDF 1.1 Turtle export with reified provenance per edge),
  [`causal_kg_rank_edges()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_rank_edges.md)
  (multi-source ranking by `n_sources` + `mean_confidence` +
  `agrovoc_support`) and a
  [`summary()`](https://rdrr.io/r/base/summary.html) method that reports
  node / edge / source counts, confidence distribution and DAG-ness.
  **Multi-extractor voting**
  ([`causal_llm_vote()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_vote.md),
  [`causal_llm_ingest_abstract_voted()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_abstract_voted.md))
  runs N LLM backends on the same abstract and resolves disagreements by
  majority, weighted or intersection rules. **Bottom-up structure
  learning**
  ([`causal_structure_learn()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_structure_learn.md))
  recovers a DAG directly from horizon data through a `bnlearn` bridge
  (hc, tabu, pc-stable, mmhc) with optional bootstrap edge confidence,
  producing an `edaphos_causal_kg` that can be unioned with the
  LLM-derived Knowledge Graph.

- **2. Physics-Informed ML.**:

  Parametric pedogenetic Ordinary Differential Equation integrated by
  `deSolve` —
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md);
  Neural ODE with differentiable Runge-Kutta integrator on `torch` —
  [`piml_neural_ode_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit.md);
  hierarchical covariate-conditioned Neural ODE jointly fit across
  pedons —
  [`piml_hierarchical_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_hierarchical_fit.md).
  A **Bayesian posterior** over \\(\lambda_0, \mu, y\_\infty, y_0)\\ is
  returned by
  [`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md)
  via a Laplace approximation (the default) or an adaptive random-walk
  Metropolis sampler. The Neural-ODE variant is paired with
  [`piml_neural_ode_fit_ensemble()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit_ensemble.md),
  a deep ensemble whose empirical spread approximates the Bayesian
  predictive posterior with no extra torch machinery.

- **3. 4D Pedometry.**:

  Multi-layer stacked Convolutional LSTM with sequence-to-one and
  sequence-to-sequence training —
  [`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md);
  multi-step rollout forecasting —
  [`temporal_convlstm_rollout()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_rollout.md);
  optional mass-balance physics loss; reproducible synthetic SOC
  dynamics cube generator —
  [`temporal_synth_soc_cube()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_synth_soc_cube.md).

- **4. Foundation Models.**:

  SimCLR scaffold
  ([`foundation_simclr_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_simclr_pretrain.md),
  [`foundation_simclr_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_simclr_embed.md))
  plus a **MoCo v2** upgrade
  ([`foundation_moco_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain.md),
  [`foundation_moco_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed.md))
  with momentum encoder, dictionary queue and a raster-specific
  augmentation stack. A **planetary-scale tile pipeline**
  ([`foundation_tile_source_soilgrids()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_soilgrids.md),
  [`foundation_tile_source_worldclim()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_worldclim.md),
  [`foundation_tile_source_srtm()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_srtm.md),
  [`foundation_tile_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_align.md),
  [`foundation_tile_dataset()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_dataset.md))
  streams patches lazily from multi-source
  [`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  mosaics;
  [`foundation_moco_pretrain_tiles()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain_tiles.md)
  trains with checkpointing and on-device dispatch
  (`device = "cpu" | "mps" | "cuda"`), and
  [`foundation_moco_embed_raster()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed_raster.md)
  projects the trained encoder over an entire AoI. A **downstream
  fine-tuning API**
  ([`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md),
  [`foundation_fit_regressor()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_regressor.md))
  wraps the head construction, training loop, validation split and
  target normalisation behind a single call and supports both linear
  probing and full fine-tuning with a two-group learning-rate schedule.
  **Public pretrained weights** are distributed via Zenodo:
  [`foundation_weights_list()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_list.md)
  catalogues the registry,
  [`foundation_weights_download()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_download.md)
  fetches the artefact with SHA-256 verification and caches it under
  `tools::R_user_dir("edaphos")`, and
  [`foundation_weights_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_load.md)
  rebuilds the `edaphos_foundation_moco` wrapper from the saved state
  dict.

- **5. Autonomous Active Learning.**:

  Closed-loop sampling policy combining Quantile-Regression-Forest
  uncertainty, feature-space diversity and logistical cost —
  [`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md),
  [`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md),
  [`al_initial_design()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_initial_design.md),
  [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md),
  [`al_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_update.md);
  with both global and per-location Physics- Informed rejection gates —
  [`al_physics_gate_piml()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml.md),
  [`al_physics_gate_piml_hierarchical()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml_hierarchical.md).
  Information-theoretic batch acquisition is provided by
  [`al_query_batchbald()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_batchbald.md),
  which maximises the mutual information between the batch and the model
  parameters via a greedy log-det submodular objective (Kirsch, van
  Amersfoort and Gal 2019).

- **6. Quantum ML.**:

  Pure-R state-vector simulator of the ZZFeatureMap encoding (Havlicek
  et al., 2019) with a quantum-kernel Gram matrix
  [`quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_kernel.md)
  and a closed-form Kernel Ridge Regression wrapper
  [`quantum_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_fit.md).
  A full Qiskit-backed Variational Quantum Eigensolver bridge
  ([`quantum_hamiltonian()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian.md),
  [`quantum_hamiltonian_h2()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_h2.md),
  [`quantum_hamiltonian_organo_mineral()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_organo_mineral.md),
  [`quantum_vqe_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_fit.md),
  [`quantum_vqe_exact()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_exact.md))
  runs on `qiskit-aer` out of the box with three interchangeable back
  ends: exact statevector, **shot-based Aer** with SPSA and optional
  noise models, and **full IBM Quantum Runtime dispatch**
  ([`quantum_ibmq_submit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_submit.md),
  [`quantum_ibmq_available()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_available.md),
  [`quantum_ibmq_backends()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_backends.md),
  [`quantum_ibmq_least_busy()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_least_busy.md))
  with M3 readout and ZNE gate-folding mitigation (Kim et al., 2023). A
  **qiskit-nature bridge**
  ([`quantum_hamiltonian_from_pyscf()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_from_pyscf.md),
  [`quantum_hamiltonian_organo_mineral_nature()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_organo_mineral_nature.md),
  [`quantum_nature_total_energy()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_nature_total_energy.md))
  lifts a user-supplied XYZ geometry through a PySCF RHF reference,
  frozen-core reduction, ActiveSpace projection and a `ParityMapper`
  with Z2 tapering, producing a qubit Hamiltonian ready for VQE
  minimisation. Curated presets cover the three canonical organo-mineral
  motifs: the carboxylate (`"formic_acid"`), the ortho-diol
  (`"methanediol"`), and a monodentate Fe(III)– carboxylate coordination
  complex (`"ferric_formate"`).

## Vignettes

Each pillar ships a mathematically-derived vignette with examples on
real or reproducible synthetic data. Entry points:
[`vignette("pilar1-causal", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar1-causal.md),
[`vignette("pilar2-piml-profile", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar2-piml-profile.md),
[`vignette("pilar3-4d-soc", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar3-4d-soc.md),
[`vignette("pilar4-simclr-embeddings", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar4-simclr-embeddings.md),
[`vignette("pilar5-active-learning", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar5-active-learning.md),
`vignette("pilar5-soilgrids-br", package = "edaphos")`,
[`vignette("pilar6-quantum", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar6-quantum.md).
The end-to-end honest benchmark on 1212 real Brazilian WoSIS Cerrado
profiles lives in
[`vignette("case-cerrado-end-to-end", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/case-cerrado-end-to-end.md).

## References

McBratney, A. B., Mendonça Santos, M. L. and Minasny, B. (2003). On
digital soil mapping. *Geoderma* **117**, 3-52.

Wadoux, A. M. J.-C., Minasny, B. and McBratney, A. B. (2020). Machine
learning for digital soil mapping: applications, challenges and
suggested solutions. *Earth-Science Reviews* **210**, 103359.

## See also

Useful links:

- <https://github.com/HugoMachadoRodrigues/edaphos>

- Report bugs at
  <https://github.com/HugoMachadoRodrigues/edaphos/issues>

## Author

**Maintainer**: Hugo Rodrigues <rodrigues.machado.hugo@gmail.com>
([ORCID](https://orcid.org/0000-0002-8070-8126))
