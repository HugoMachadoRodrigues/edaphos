# Pilar 10 -- Graph Neural Networks on WoSIS co-location networks
# (v2.6.0 scope).
#
# Status: SCAFFOLD.
#
# Why a pillar?
# -------------
# Every existing edaphos pillar treats soil profiles as INDEPENDENT
# observations.  Pilar 5's feature-space diversity (cLHS) is the
# closest the package gets to "respecting neighbourhood structure",
# but it uses covariate distance, not profile adjacency.
#
# A graph neural network (Scarselli et al. 2009; Kipf & Welling 2017;
# Velickovic et al. 2018) naturally represents soil profiles as nodes
# and spatial co-location as edges, letting message-passing
# propagate information between geographically near profiles.  This
# is UNPRECEDENTED in Digital Soil Mapping literature.
#
# Target architecture for v2.6.0
# ------------------------------
# A Graph Attention Network (GAT) over a k-NN graph of WoSIS
# profiles:
#   - Node features = SoilGrids + WorldClim values at the profile
#   - Edge weights = inverse geodesic distance
#   - Target = topsoil SOC
#
# Bridge with Pilar 4: the GAT's node embeddings are *directly
# comparable* to MoCo v2 embeddings -- both are 64-dim vectors
# summarising a profile's local context.  Pilar 10 therefore gives
# us a classical-geospatial analogue of the foundation-model
# embedding stack, which closes an important "ML design space"
# comparison.
#
# TODO (v2.6.0)
# -------------
#  - [ ] `gnn_build_graph(profiles, k = 8L, ...)` -- k-NN edges via
#        `RANN::nn2`.
#  - [ ] `gnn_gat_module()` -- `torch` nn_module with 2 GAT layers.
#  - [ ] `gnn_fit(graph, targets, epochs, ...)`
#  - [ ] `gnn_embed(fit, new_profiles)` -- 64-dim representation per
#        node (comparable to `foundation_moco_embed`).
#  - [ ] `gnn_posterior()` -> `edaphos_posterior`.
#  - [ ] Benchmark: GAT vs ranger vs QRF vs MoCo-finetune on 1 095
#        Cerrado profiles.
#  - [ ] `vignettes/pilar10-graph-nn.Rmd`

#' Build a k-NN co-location graph from a WoSIS-style profile frame
#' (scaffold, v2.6.0)
#'
#' @description **Not yet implemented.**  Scheduled for v2.6.0.
#' @param profiles Data frame with `lon`, `lat` columns.
#' @param k Integer; number of nearest neighbours per node.
#' @param ... Reserved for backend-specific options.
#' @return (When implemented) An `edaphos_gnn_graph` S3 object.
#' @export
gnn_build_graph <- function(profiles, k = 8L, ...) {
  stop(
    "`gnn_build_graph()` is scheduled for edaphos v2.6.0 (Pilar 10 --\n",
    "Graph Neural Networks on WoSIS co-location).",
    call. = FALSE
  )
}

#' Fit a Graph Attention Network on the profile graph (scaffold,
#' v2.6.0)
#'
#' @description **Not yet implemented.**  Scheduled for v2.6.0.
#' @param graph An `edaphos_gnn_graph` from [`gnn_build_graph()`].
#' @param targets Numeric vector (one per node).
#' @param epochs Integer; training epochs.
#' @param ... Forwarded to the torch optimiser.
#' @export
gnn_fit <- function(graph, targets, epochs = 200L, ...) {
  stop("`gnn_fit()` is scheduled for edaphos v2.6.0 (Pilar 10).",
        call. = FALSE)
}
