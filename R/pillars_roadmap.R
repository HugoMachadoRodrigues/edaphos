#' Roadmap and status of the six pillars of edaphos
#'
#' Documentation-only landing page that summarises the scope of every
#' pillar, its current implementation status, and the governing
#' mathematical object. Use this together with the package overview —
#' [edaphos-package] — as the starting point for navigating the API.
#'
#' | Pillar | Namespace      | Status       | Governing object                                                                                                       |
#' |--------|----------------|--------------|------------------------------------------------------------------------------------------------------------------------|
#' | 1. Causal AI                     | `causal_*`     | implemented | Structural causal model \eqn{G = (V, E)} with backdoor-adjusted estimand \eqn{\beta_{x \to y}^{\text{do}}} (Pearl, 2009); LM and BART estimators; LLM-driven Knowledge-Graph pipeline ([causal_kg_new()], [causal_llm_extract()], [causal_augment_dag()]) supporting Ollama / OpenAI / Anthropic; corpus clients for SciELO / OpenAlex and ontology alignment against a curated AGROVOC + ENVO Cerrado vocabulary. |
#' | 2. Physics-Informed ML           | `piml_*`       | implemented | Pedogenetic ODE \eqn{dy/dz = -\lambda_0 e^{-\mu z}(y - y_\infty)} and Neural ODE \eqn{dy/dz = f_\theta(z, y, \mathbf{x})}.         |
#' | 3. 4D Pedometry                  | `temporal_*`   | implemented | Stacked ConvLSTM (Shi et al., 2015) with seq-to-seq training, multi-step rollout and a mass-balance physics loss.             |
#' | 4. Foundation Models             | `foundation_*` | implemented | SimCLR scaffold ([foundation_simclr_pretrain()]), MoCo v2 ([foundation_moco_pretrain()]) with momentum encoder + dictionary queue + raster-specific augmentations, and a **planetary-scale tile pipeline** ([foundation_tile_source_soilgrids()], [foundation_tile_align()], [foundation_tile_dataset()], [foundation_moco_pretrain_tiles()], [foundation_moco_embed_raster()]). |
#' | 5. Autonomous Active Learning    | `al_*`         | implemented | Hybrid policy \eqn{\pi(\mathbf{x}) = \alpha\,\tilde u(\mathbf{x}) + (1-\alpha)\,\tilde d(\mathbf{x})} with PIML-backed gate.  |
#' | 6. Quantum ML                    | `quantum_*`    | implemented | Pure-R ZZFeatureMap ([quantum_feature_map()]) + quantum-kernel Gram matrix ([quantum_kernel()]) + kernel ridge regression ([quantum_krr_fit()]), **and** a Qiskit-backed VQE bridge ([quantum_hamiltonian()], [quantum_hamiltonian_h2()], [quantum_hamiltonian_organo_mineral()], [quantum_vqe_fit()], [quantum_vqe_exact()]) for ground-state energy estimation of toy organo-mineral Hamiltonians with optional IBM-Q hardware preflight ([quantum_ibmq_available()]). |
#'
#' @name edaphos-roadmap
#' @keywords internal
NULL
