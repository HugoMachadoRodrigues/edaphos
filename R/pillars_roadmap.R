#' Roadmap and status of the six pillars of edaphos
#'
#' Documentation-only landing page that summarises the scope of every
#' pillar, its current implementation status, and the governing
#' mathematical object. Use this together with the package overview —
#' [edaphos-package] — as the starting point for navigating the API.
#'
#' | Pillar | Namespace      | Status       | Governing object                                                                                                       |
#' |--------|----------------|--------------|------------------------------------------------------------------------------------------------------------------------|
#' | 1. Causal AI                     | `causal_*`     | scaffold    | Structural causal model \eqn{G = (V, E)} with backdoor-adjusted estimand \eqn{\beta_{x \to y}^{\text{do}}} (Pearl, 2009).         |
#' | 2. Physics-Informed ML           | `piml_*`       | implemented | Pedogenetic ODE \eqn{dy/dz = -\lambda_0 e^{-\mu z}(y - y_\infty)} and Neural ODE \eqn{dy/dz = f_\theta(z, y, \mathbf{x})}.         |
#' | 3. 4D Pedometry                  | `temporal_*`   | implemented | Stacked ConvLSTM (Shi et al., 2015) with seq-to-seq training, multi-step rollout and a mass-balance physics loss.             |
#' | 4. Foundation Models             | `foundation_*` | scaffold    | NT-Xent contrastive objective (Chen et al., 2020) on unlabelled raster patches.                                                |
#' | 5. Autonomous Active Learning    | `al_*`         | implemented | Hybrid policy \eqn{\pi(\mathbf{x}) = \alpha\,\tilde u(\mathbf{x}) + (1-\alpha)\,\tilde d(\mathbf{x})} with PIML-backed gate.  |
#' | 6. Quantum ML                    | `quantum_*`    | scaffold    | Pure-R ZZFeatureMap ([quantum_feature_map()]) + quantum-kernel Gram matrix ([quantum_kernel()]) + kernel ridge regression ([quantum_krr_fit()]). VQE for organo-mineral simulation is on the roadmap. |
#'
#' @name edaphos-roadmap
#' @keywords internal
NULL
