#' edaphos: Disruptive Algorithms for Digital Soil Mapping
#'
#' From Greek \eqn{\epsilon\delta\alpha\phi o\varsigma} — "soil, ground."
#'
#' @description
#' `edaphos` is a research-oriented R package that implements frontier
#' algorithms for Digital Soil Mapping (DSM) beyond the regression-tree
#' state of the art (McBratney, Mendon\enc{ç}{c}a Santos and Minasny,
#' 2003; Wadoux, Minasny and McBratney, 2020). Its contributions are
#' organised across **six research pillars**, each confronting a specific
#' methodological gap of the contemporary literature and equipped with a
#' vignette that derives the governing object from first principles.
#'
#' @section Six research pillars:
#'
#' \describe{
#'   \item{\strong{1. Causal AI.}}{DAG-backed backdoor adjustment via
#'     `dagitty` — [causal_clorpt_dag()], [causal_cerrado_dag()],
#'     [causal_adjustment_set()], [causal_estimate_effect()] — with
#'     an optional non-linear BART estimator via the `dbarts` Suggests
#'     dependency. An LLM-driven Knowledge-Graph extraction pipeline
#'     on top of `httr2` ([causal_kg_new()], [causal_llm_extract()],
#'     [causal_llm_ingest_corpus()], [causal_augment_dag()]) supports
#'     Ollama (Gemma 4), OpenAI and Anthropic backends. Corpus
#'     ingestion clients for SciELO ([causal_corpus_scielo()]) and
#'     OpenAlex ([causal_corpus_openalex()]) transparently page
#'     through their upstream APIs for multi-thousand-abstract pulls,
#'     deduplicated by DOI / title via
#'     [causal_corpus_deduplicate()]. Production-grade ingestion
#'     over corpora of tens of thousands of abstracts is handled by
#'     [causal_llm_ingest_corpus()]'s `cache_dir` and `max_retries`
#'     arguments (resumable, idempotent, exponential backoff).
#'     Ontology alignment against the curated Cerrado vocabulary or
#'     **live FAO AGROVOC SPARQL**
#'     ([causal_ontology_agrovoc_align()],
#'     `causal_kg_alignment(vocab = "agrovoc")`) is provided with
#'     on-disk caching, and a **concurrent batched alignment**
#'     ([causal_ontology_agrovoc_align_batch()]) dispatches up to
#'     `max_active` parallel HTTP requests so a 10 k-node KG
#'     resolves in minutes instead of hours. Paper-scale KGs are
#'     persisted and audited via [causal_kg_save()] /
#'     [causal_kg_load()] (portable RDS edge-list),
#'     [causal_kg_to_turtle()] (W3C RDF 1.1 Turtle export with
#'     reified provenance per edge), [causal_kg_rank_edges()]
#'     (multi-source ranking by `n_sources` +
#'     `mean_confidence` + `agrovoc_support`) and a
#'     `summary()` method that reports node / edge / source counts,
#'     confidence distribution and DAG-ness. **Multi-extractor voting**
#'     ([causal_llm_vote()],
#'     [causal_llm_ingest_abstract_voted()]) runs N LLM backends on
#'     the same abstract and resolves disagreements by majority,
#'     weighted or intersection rules. **Bottom-up structure learning**
#'     ([causal_structure_learn()]) recovers a DAG directly from
#'     horizon data through a `bnlearn` bridge (hc, tabu,
#'     pc-stable, mmhc) with optional bootstrap edge confidence,
#'     producing an `edaphos_causal_kg` that can be unioned with the
#'     LLM-derived Knowledge Graph.}
#'   \item{\strong{2. Physics-Informed ML.}}{Parametric pedogenetic
#'     Ordinary Differential Equation integrated by `deSolve` —
#'     [piml_profile_fit()]; Neural ODE with differentiable Runge-Kutta
#'     integrator on `torch` — [piml_neural_ode_fit()]; hierarchical
#'     covariate-conditioned Neural ODE jointly fit across pedons —
#'     [piml_hierarchical_fit()]. A **Bayesian posterior** over
#'     \eqn{(\lambda_0, \mu, y_\infty, y_0)} is returned by
#'     [piml_profile_fit_bayesian()] via a Laplace approximation (the
#'     default) or an adaptive random-walk Metropolis sampler. The
#'     Neural-ODE variant is paired with
#'     [piml_neural_ode_fit_ensemble()], a deep ensemble whose
#'     empirical spread approximates the Bayesian predictive
#'     posterior with no extra torch machinery.}
#'   \item{\strong{3. 4D Pedometry.}}{Multi-layer stacked Convolutional
#'     LSTM with sequence-to-one and sequence-to-sequence training —
#'     [temporal_convlstm_fit()]; multi-step rollout forecasting —
#'     [temporal_convlstm_rollout()]; optional mass-balance physics
#'     loss; reproducible synthetic SOC dynamics cube generator —
#'     [temporal_synth_soc_cube()].}
#'   \item{\strong{4. Foundation Models.}}{SimCLR scaffold
#'     ([foundation_simclr_pretrain()], [foundation_simclr_embed()])
#'     plus a **MoCo v2** upgrade ([foundation_moco_pretrain()],
#'     [foundation_moco_embed()]) with momentum encoder, dictionary
#'     queue and a raster-specific augmentation stack. A
#'     **planetary-scale tile pipeline**
#'     ([foundation_tile_source_soilgrids()],
#'     [foundation_tile_source_worldclim()],
#'     [foundation_tile_source_srtm()],
#'     [foundation_tile_align()],
#'     [foundation_tile_dataset()]) streams patches lazily from
#'     multi-source `terra::SpatRaster` mosaics;
#'     [foundation_moco_pretrain_tiles()] trains with checkpointing
#'     and on-device dispatch (`device = "cpu" | "mps" | "cuda"`),
#'     and [foundation_moco_embed_raster()] projects the trained
#'     encoder over an entire AoI. A **downstream fine-tuning API**
#'     ([foundation_fit_classifier()],
#'     [foundation_fit_regressor()]) wraps the head construction,
#'     training loop, validation split and target normalisation
#'     behind a single call and supports both linear probing and
#'     full fine-tuning with a two-group learning-rate schedule.
#'     **Public pretrained weights** are distributed via Zenodo:
#'     [foundation_weights_list()] catalogues the registry,
#'     [foundation_weights_download()] fetches the artefact with
#'     SHA-256 verification and caches it under
#'     `tools::R_user_dir("edaphos")`, and
#'     [foundation_weights_load()] rebuilds the
#'     `edaphos_foundation_moco` wrapper from the saved state dict.}
#'   \item{\strong{5. Autonomous Active Learning.}}{Closed-loop sampling
#'     policy combining Quantile-Regression-Forest uncertainty,
#'     feature-space diversity and logistical cost — [al_loop()],
#'     [al_query()], [al_initial_design()], [al_fit()],
#'     [al_update()]; with both global and per-location Physics-
#'     Informed rejection gates — [al_physics_gate_piml()],
#'     [al_physics_gate_piml_hierarchical()]. Information-theoretic
#'     batch acquisition is provided by [al_query_batchbald()],
#'     which maximises the mutual information between the batch and
#'     the model parameters via a greedy log-det submodular objective
#'     (Kirsch, van Amersfoort and Gal 2019).}
#'   \item{\strong{6. Quantum ML.}}{Pure-R state-vector simulator of
#'     the ZZFeatureMap encoding (Havlicek et al., 2019) with a
#'     quantum-kernel Gram matrix [quantum_kernel()] and a
#'     closed-form Kernel Ridge Regression wrapper
#'     [quantum_krr_fit()]. A full Qiskit-backed Variational Quantum
#'     Eigensolver bridge ([quantum_hamiltonian()],
#'     [quantum_hamiltonian_h2()],
#'     [quantum_hamiltonian_organo_mineral()],
#'     [quantum_vqe_fit()], [quantum_vqe_exact()]) runs on
#'     `qiskit-aer` out of the box with three interchangeable back
#'     ends: exact statevector, **shot-based Aer** with SPSA and
#'     optional noise models, and **full IBM Quantum Runtime
#'     dispatch** ([quantum_ibmq_submit()],
#'     [quantum_ibmq_available()],
#'     [quantum_ibmq_backends()],
#'     [quantum_ibmq_least_busy()]) with M3 readout and ZNE
#'     gate-folding mitigation (Kim et al., 2023). A **qiskit-nature
#'     bridge** ([quantum_hamiltonian_from_pyscf()],
#'     [quantum_hamiltonian_organo_mineral_nature()],
#'     [quantum_nature_total_energy()]) lifts a user-supplied XYZ
#'     geometry through a PySCF RHF reference, frozen-core
#'     reduction, ActiveSpace projection and a `ParityMapper` with
#'     Z2 tapering, producing a qubit Hamiltonian ready for VQE
#'     minimisation. Curated presets cover the three canonical
#'     organo-mineral motifs: the carboxylate (`"formic_acid"`), the
#'     ortho-diol (`"methanediol"`), and a monodentate Fe(III)–
#'     carboxylate coordination complex (`"ferric_formate"`).}
#' }
#'
#' @section Vignettes:
#' Each pillar ships a mathematically-derived vignette with examples on
#' real or reproducible synthetic data. Entry points:
#' \code{vignette("pilar1-causal", package = "edaphos")},
#' \code{vignette("pilar2-piml-profile", package = "edaphos")},
#' \code{vignette("pilar3-4d-soc", package = "edaphos")},
#' \code{vignette("pilar4-simclr-embeddings", package = "edaphos")},
#' \code{vignette("pilar5-active-learning", package = "edaphos")},
#' \code{vignette("pilar5-soilgrids-br", package = "edaphos")},
#' \code{vignette("pilar6-quantum", package = "edaphos")}.
#'
#' @references
#' McBratney, A. B., Mendon\enc{ç}{c}a Santos, M. L. and Minasny, B.
#' (2003). On digital soil mapping. *Geoderma* **117**, 3-52.
#'
#' Wadoux, A. M. J.-C., Minasny, B. and McBratney, A. B. (2020). Machine
#' learning for digital soil mapping: applications, challenges and
#' suggested solutions. *Earth-Science Reviews* **210**, 103359.
#'
#' @keywords internal
"_PACKAGE"
