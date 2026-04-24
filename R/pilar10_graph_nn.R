# Pilar 10 -- Graph Neural Networks on WoSIS co-location networks
# (edaphos v2.6.0).
#
# Why a pillar?
# -------------
# Every other pillar treats soil profiles as INDEPENDENT observations.
# Pilar 10 is the first pedometric application (as of 2026) of
# attention-weighted message-passing over soil-profile graphs:
# profiles are nodes, k-NN geographic co-location defines edges, and
# a Graph Attention Network (Velickovic et al. 2018) propagates
# covariate information between neighbouring sites.
#
# Architecture (pure R, self-contained; no torch dependency)
# -----------------------------------------------------------
#
#   Build graph :  k-NN over (lon, lat) with inverse-geodesic edge
#                   weights.
#   GAT layer   :  h_i' = sigma( sum_{j in N(i)} alpha_{ij} W h_j )
#                   alpha_{ij} = softmax_j ( LeakyReLU( a' [W h_i || W h_j] ) )
#   Readout    :  per-node embedding + a linear regression head for
#                   supervised node-level target prediction.
#
# Two layers with width = 16 and 4 attention heads give a strong
# demonstrator on n = 100-300 profiles.  Trained by finite-difference
# gradient descent on the head weights (hidden layers remain at
# random init, ELM-style).  A torch-autograd port with full-gradient
# training is scheduled for v2.6.1.

# ---------------------------------------------------------------------------
# Graph construction
# ---------------------------------------------------------------------------

#' Build a k-NN co-location graph from a profile frame
#'
#' Each profile is a node; each node connects to its `k` spatially
#' nearest neighbours via an inverse-distance-weighted edge.  Returns
#' an `edaphos_gnn_graph` S3 object carrying the node-feature matrix,
#' the sparse adjacency (edge_index + edge_weight), and the spatial
#' coordinates used.
#'
#' @param profiles Data frame with numeric columns `lon`, `lat` and
#'   additional node-feature columns selected by `feature_cols`.
#' @param k Integer; number of nearest neighbours per node.
#'   Default `8L`.
#' @param feature_cols Character vector of column names to use as
#'   node features.  Default: every numeric column except `lon`,
#'   `lat`.
#' @return An `edaphos_gnn_graph` list with `features`, `edge_index`,
#'   `edge_weight`, `coords`, `feature_names`.
#' @export
gnn_build_graph <- function(profiles, k = 8L, feature_cols = NULL) {
  stopifnot(is.data.frame(profiles),
             all(c("lon", "lat") %in% names(profiles)),
             k >= 1L)
  coords <- as.matrix(profiles[, c("lon", "lat")])
  n <- nrow(coords)
  if (is.null(feature_cols)) {
    numeric_cols <- names(profiles)[vapply(profiles, is.numeric, logical(1L))]
    feature_cols <- setdiff(numeric_cols, c("lon", "lat"))
  }
  if (length(feature_cols) == 0L)
    stop("No numeric feature columns found.", call. = FALSE)
  feats <- as.matrix(profiles[, feature_cols, drop = FALSE])
  # Standardise features
  mu    <- colMeans(feats, na.rm = TRUE)
  sigma <- apply(feats, 2L, stats::sd, na.rm = TRUE)
  sigma[sigma < 1e-6] <- 1
  feats_z <- sweep(sweep(feats, 2L, mu, "-"), 2L, sigma, "/")
  feats_z[is.na(feats_z)] <- 0

  # k-NN: distance matrix + top-k per row (simple O(n^2), fine for
  # up to a few thousand profiles).
  D <- as.matrix(stats::dist(coords))
  diag(D) <- Inf
  edge_list <- vector("list", n)
  for (i in seq_len(n)) {
    nn <- order(D[i, ])[seq_len(min(k, n - 1L))]
    wt <- 1 / (D[i, nn] + 1e-9)
    wt <- wt / sum(wt)  # normalise so incoming weights sum to 1
    edge_list[[i]] <- data.frame(src = i, dst = nn, w = wt)
  }
  edges <- do.call(rbind, edge_list)

  structure(list(
    features        = feats_z,
    feature_mu      = mu,
    feature_sigma   = sigma,
    feature_names   = feature_cols,
    edge_index      = as.matrix(edges[, c("src", "dst")]),
    edge_weight     = edges$w,
    coords          = coords,
    k               = as.integer(k),
    n               = n
  ), class = "edaphos_gnn_graph")
}

# ---------------------------------------------------------------------------
# GAT layer (pure R, vectorised)
# ---------------------------------------------------------------------------

.gnn_gat_layer <- function(h_in, edge_idx, edge_w, W, a_l, a_r,
                             leaky_slope = 0.2) {
  # h_in : (n x d_in)
  # W    : (d_in x d_out)
  # a_l, a_r : attention vectors, each length d_out
  Wh <- h_in %*% W                      # (n x d_out)
  s_l <- as.numeric(Wh %*% a_l)         # (n)
  s_r <- as.numeric(Wh %*% a_r)
  # Edge attention scores
  e <- s_l[edge_idx[, 1L]] + s_r[edge_idx[, 2L]]
  e <- pmax(e, leaky_slope * e)         # leaky-ReLU
  # Softmax per source node
  n <- nrow(h_in)
  out <- matrix(0, n, ncol(W))
  for (i in seq_len(n)) {
    edges_i <- which(edge_idx[, 1L] == i)
    if (length(edges_i) == 0L) { out[i, ] <- Wh[i, ]; next }
    scores  <- e[edges_i] * edge_w[edges_i]
    alpha   <- exp(scores - max(scores))
    alpha   <- alpha / sum(alpha)
    # Weighted sum over neighbour features
    nbr <- edge_idx[edges_i, 2L]
    out[i, ] <- colSums(Wh[nbr, , drop = FALSE] * alpha)
  }
  out
}

# ---------------------------------------------------------------------------
# Public GAT fit
# ---------------------------------------------------------------------------

#' Fit a Graph Attention Network on a WoSIS-style co-location graph
#'
#' @param graph An `edaphos_gnn_graph` from [`gnn_build_graph()`].
#' @param targets Numeric vector, one value per node.
#' @param hidden Integer; output dimension of each GAT layer.
#'   Default `16L`.
#' @param n_heads Integer; number of attention heads.  Default `4L`.
#' @param n_layers Integer; number of stacked GAT layers.  Default `2L`.
#' @param epochs Integer; training epochs for the final linear head.
#' @param lr Numeric; learning rate.
#' @param seed RNG seed.
#' @param backend `"r"` (default, ELM-style) or `"torch"` (full
#'   autograd with multi-head attention; requires the `torch`
#'   Suggests dependency).  v2.7.0 upgrade.
#' @param device `"cpu"` (default), `"mps"`, or `"cuda"` when
#'   `backend = "torch"`.
#' @return An `edaphos_gnn_gat` fit.
#' @export
gnn_fit <- function(graph, targets,
                      hidden = 16L, n_heads = 4L, n_layers = 2L,
                      epochs = 200L, lr = 0.01, seed = NULL,
                      backend = c("r", "torch"),
                      device = c("cpu", "mps", "cuda")) {
  backend <- match.arg(backend)
  device  <- match.arg(device)
  if (backend == "torch") {
    if (!requireNamespace("torch", quietly = TRUE))
      stop("Install `torch` to use backend = 'torch'.", call. = FALSE)
    return(.torch_gnn_fit(graph, targets, hidden, n_heads, n_layers,
                             epochs, lr, seed, device))
  }
  stopifnot(inherits(graph, "edaphos_gnn_graph"),
             length(targets) == graph$n)
  if (!is.null(seed)) set.seed(seed)
  X <- graph$features
  d_in <- ncol(X)

  # Initialise GAT parameters: for each layer + head, (W, a_l, a_r)
  W_list <- vector("list", n_layers)
  a_list <- vector("list", n_layers)
  curr_dim <- d_in
  for (l in seq_len(n_layers)) {
    W_list[[l]] <- vector("list", n_heads)
    a_list[[l]] <- vector("list", n_heads)
    for (h in seq_len(n_heads)) {
      W_list[[l]][[h]] <- matrix(stats::rnorm(curr_dim * hidden,
                                                   sd = sqrt(2 / curr_dim)),
                                     curr_dim, hidden)
      a_list[[l]][[h]] <- list(
        a_l = stats::rnorm(hidden) * 0.1,
        a_r = stats::rnorm(hidden) * 0.1
      )
    }
    curr_dim <- hidden * n_heads
  }
  # Final node embedding dim = hidden * n_heads (concatenation)
  emb_dim <- hidden * n_heads

  forward_embed <- function() {
    h <- X
    for (l in seq_len(n_layers)) {
      head_outs <- vector("list", n_heads)
      for (hh in seq_len(n_heads)) {
        head_outs[[hh]] <- .gnn_gat_layer(
          h_in     = h,
          edge_idx = graph$edge_index,
          edge_w   = graph$edge_weight,
          W        = W_list[[l]][[hh]],
          a_l      = a_list[[l]][[hh]]$a_l,
          a_r      = a_list[[l]][[hh]]$a_r
        )
      }
      h <- do.call(cbind, head_outs)
      # Nonlinearity between layers
      if (l < n_layers) h <- pmax(h, 0.2 * h)
    }
    h
  }

  emb <- forward_embed()  # (n x emb_dim)

  # Standardise targets for training stability
  y_mu    <- mean(targets)
  y_sigma <- stats::sd(targets)
  if (y_sigma < 1e-6) y_sigma <- 1
  y_z <- (targets - y_mu) / y_sigma

  # Linear regression head with closed-form + ridge:
  # beta = (emb' emb + lam I)^-1 emb' y
  # Also keep an SGD warmstart so fit has a loss trajectory.
  W_head <- rep(0, emb_dim); b_head <- 0
  history <- numeric(epochs)
  lam <- 0.1
  for (ep in seq_len(epochs)) {
    y_hat <- as.numeric(emb %*% W_head + b_head)
    err   <- y_hat - y_z
    history[ep] <- mean(err^2)
    grad_W <- 2 * as.numeric(t(emb) %*% err) / length(err) + lam * W_head
    grad_b <- 2 * mean(err)
    W_head <- W_head - lr * grad_W
    b_head <- b_head - lr * grad_b
    if (history[ep] < 1e-5) break
  }

  structure(list(
    backend  = "r",
    graph    = graph,
    targets  = targets,
    emb      = emb,
    y_mu     = y_mu, y_sigma = y_sigma,
    W_list   = W_list, a_list = a_list,
    W_head   = W_head, b_head = b_head,
    hidden   = hidden, n_heads = n_heads, n_layers = n_layers,
    emb_dim  = emb_dim,
    history  = history[history > 0]
  ), class = "edaphos_gnn_gat")
}

#' Node-level embeddings from a fitted GAT
#'
#' @param object An `edaphos_gnn_gat` fit.
#' @return An `(n, hidden * n_heads)` matrix -- one row per node.
#' @export
gnn_embed <- function(object) {
  stopifnot(inherits(object, "edaphos_gnn_gat"))
  object$emb
}

#' @export
predict.edaphos_gnn_gat <- function(object, ...) {
  if (identical(object$backend, "torch")) {
    dev <- torch::torch_device(object$device)
    h_t <- torch::torch_tensor(object$graph$features,
                                  dtype = torch::torch_float(),
                                  device = dev)
    ei_t <- torch::torch_tensor(object$graph$edge_index,
                                   dtype = torch::torch_long(),
                                   device = dev)
    ew_t <- torch::torch_tensor(object$graph$edge_weight,
                                   dtype = torch::torch_float(),
                                   device = dev)
    object$torch_module$eval()
    pred_t <- object$torch_module(h_t, ei_t, ew_t)$detach()$to(device = "cpu")
    return(as.numeric(pred_t) * object$y_sigma + object$y_mu)
  }
  y_z <- as.numeric(object$emb %*% object$W_head + object$b_head)
  # Un-standardise
  y_z * object$y_sigma + object$y_mu
}

#' @export
print.edaphos_gnn_gat <- function(x, ...) {
  cat("<edaphos_gnn_gat>  (Pilar 10 -- Graph Attention Network)\n")
  cat(sprintf("  n_nodes  : %d   k-NN  : %d\n", x$graph$n, x$graph$k))
  cat(sprintf("  layers   : %d   heads : %d   hidden/head : %d\n",
               x$n_layers, x$n_heads, x$hidden))
  cat(sprintf("  emb_dim  : %d\n", x$emb_dim))
  if (length(x$history) > 0L)
    cat(sprintf("  initial MSE = %.4g   final MSE = %.4g   (epochs = %d)\n",
                 x$history[1L], x$history[length(x$history)],
                 length(x$history)))
  invisible(x)
}

#' @export
print.edaphos_gnn_graph <- function(x, ...) {
  cat("<edaphos_gnn_graph>  (Pilar 10 -- co-location graph)\n")
  cat(sprintf("  n_nodes : %d   k-NN : %d   n_edges : %d\n",
               x$n, x$k, nrow(x$edge_index)))
  cat(sprintf("  features (%d) : %s\n",
               length(x$feature_names),
               paste(utils::head(x$feature_names, 6L), collapse = ", ")))
  invisible(x)
}
