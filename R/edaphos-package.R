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
#'     OpenAlex ([causal_corpus_openalex()]) produce abstract-ready
#'     data frames for the same pipeline; ontology alignment against
#'     a curated Cerrado vocabulary (subset of AGROVOC + ENVO) or
#'     live AGROVOC SPARQL is provided by [causal_kg_alignment()] and
#'     [causal_kg_rename()].}
#'   \item{\strong{2. Physics-Informed ML.}}{Parametric pedogenetic
#'     Ordinary Differential Equation integrated by `deSolve` —
#'     [piml_profile_fit()]; Neural ODE with differentiable Runge-Kutta
#'     integrator on `torch` — [piml_neural_ode_fit()]; hierarchical
#'     covariate-conditioned Neural ODE jointly fit across pedons —
#'     [piml_hierarchical_fit()].}
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
#'     queue and a raster-specific augmentation stack (channel
#'     dropout, spatial cutout, per-channel brightness jitter,
#'     additive noise).}
#'   \item{\strong{5. Autonomous Active Learning.}}{Closed-loop sampling
#'     policy combining Quantile-Regression-Forest uncertainty,
#'     feature-space diversity and logistical cost — [al_loop()],
#'     [al_query()], [al_initial_design()], [al_fit()],
#'     [al_update()]; with both global and per-location Physics-
#'     Informed rejection gates — [al_physics_gate_piml()],
#'     [al_physics_gate_piml_hierarchical()].}
#'   \item{\strong{6. Quantum ML.}}{Pure-R state-vector simulator of
#'     the ZZFeatureMap encoding (Havlicek et al., 2019) with a
#'     quantum-kernel Gram matrix [quantum_kernel()] and a
#'     closed-form Kernel Ridge Regression wrapper
#'     [quantum_krr_fit()]. A full Qiskit-backed Variational Quantum
#'     Eigensolver bridge ([quantum_hamiltonian()],
#'     [quantum_hamiltonian_h2()],
#'     [quantum_hamiltonian_organo_mineral()],
#'     [quantum_vqe_fit()], [quantum_vqe_exact()]) runs on
#'     `qiskit-aer` out of the box, with preflight probes for real
#'     IBM-Q hardware via [quantum_ibmq_available()] and
#'     [quantum_ibmq_backends()].}
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
