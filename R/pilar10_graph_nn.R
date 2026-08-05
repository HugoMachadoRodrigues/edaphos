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
#   Build graph :  k-NN over (lon, lat) with inverse-great-circle edge
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
#' @param edges How neighbours are chosen. `"spatial"` (default) uses
#'   geographic k-NN; `"feature"` uses k-NN in standardised covariate space;
#'   `"hybrid"` is the union of both.
#'
#'   Which one is best is not obvious, and the answer changed once the model
#'   was fixed. Under spatially blocked validation a purely spatial graph
#'   connects a held-out node almost exclusively to other held-out nodes
#'   (measured on the Cerrado benchmark folds: 99.9 % of a node's 8 nearest
#'   geographic neighbours are also held out, against 73.7 % for feature-space
#'   edges). While the regression head was trained by gradient descent and a
#'   profile's own covariates reached the readout only through the smoothing
#'   aggregation, that starved the network and feature-space edges were clearly
#'   better. With the closed-form readout and the input skip
#'   (`readout_skip = TRUE`) a node already has direct access to its own
#'   covariates, and the spatial neighbourhood then contributes the one thing
#'   it genuinely carries -- spatial structure.
#'
#'   Nested cross-validation on the Cerrado benchmark
#'   (`data-raw/pilar10_gat_tuning.R`, bundle
#'   `inst/extdata/pilar10_gat_tuning.rds`) selected `"spatial"` in 3 of 5
#'   outer folds and `"hybrid"` in the other 2, never `"feature"` -- and the
#'   selection never saw the evaluated folds. Hence `"spatial"` is the
#'   default. Treat the choice as a hyperparameter and tune it: none of the
#'   three dominates.
#' @param self_loops Logical; add an edge from every node to itself.
#'   Default `TRUE`. k-NN never returns a node as its own neighbour, so
#'   without a self-loop the aggregation builds each node's representation
#'   purely from OTHER profiles and a profile's own covariates never reach
#'   its own prediction. Graphs built before this argument existed had no
#'   self-loops.
#' @param feature_cols Character vector of column names to use as
#'   node features.  Default: every numeric column except `lon`,
#'   `lat`.
#' @return An `edaphos_gnn_graph` list with `features`, `edge_index`,
#'   `edge_weight`, `coords`, `feature_names`.
#' @examples
#' data(br_cerrado)
#' set.seed(1)
#'
#' # gnn_build_graph() expects coordinates under `lon` / `lat`.
#' sub <- br_cerrado[sample(nrow(br_cerrado), 120L), ]
#' names(sub)[names(sub) == "x"] <- "lon"
#' names(sub)[names(sub) == "y"] <- "lat"
#'
#' g <- gnn_build_graph(sub, k = 5L,
#'                      feature_cols = c("elev", "slope", "twi"))
#' # `edge_index` is one EDGE PER ROW (src, dst), so the edge count is
#' # nrow(); ncol() is always 2.  With self-loops on there are
#' # n * (k + 1) = 720 of them.
#' c(n_nodes = g$n, n_edges = nrow(g$edge_index))
#'
#' # "spatial" links nearest neighbours in geographic space; "feature"
#' # links pedologically similar profiles however far apart they lie.
#' gf <- gnn_build_graph(sub, k = 5L,
#'                       feature_cols = c("elev", "slope", "twi"),
#'                       edges = "feature")
#' identical(g$edge_index, gf$edge_index)
#' @export
gnn_build_graph <- function(profiles, k = 8L, feature_cols = NULL,
                              edges = c("spatial", "feature", "hybrid"),
                              self_loops = TRUE) {
  edges <- match.arg(edges)
  .assert_type(is.data.frame(profiles), "profiles", "a data frame",
                  paste0("an object of class '", class(profiles)[1L], "'"))
  missing_lonlat <- setdiff(c("lon", "lat"), names(profiles))
  if (length(missing_lonlat) > 0L) {
    .stopf("`profiles` is missing coordinate column(s): %s.",
            paste(missing_lonlat, collapse = ", "),
            hint = "Rename your coords to 'lon'/'lat' before calling gnn_build_graph().")
  }
  if (!is.numeric(k) || length(k) != 1L || k < 1L) {
    .stopf("`k` must be a positive integer scalar, got %s of length %d.",
            class(k)[1L], length(k),
            hint = "Try k = 8L for a typical WoSIS-Cerrado workload.")
  }
  coords <- as.matrix(profiles[, c("lon", "lat")])
  n <- nrow(coords)
  if (is.null(feature_cols)) {
    numeric_cols <- names(profiles)[vapply(profiles, is.numeric, logical(1L))]
    feature_cols <- setdiff(numeric_cols, c("lon", "lat"))
  }
  if (length(feature_cols) == 0L) {
    .stopf("No numeric feature columns found in `profiles`.",
            hint = "Either pass `feature_cols = c(\"col1\", ...)` explicitly, or convert at least one covariate column to numeric.")
  }
  feats <- as.matrix(profiles[, feature_cols, drop = FALSE])
  # Standardise features
  mu    <- colMeans(feats, na.rm = TRUE)
  sigma <- apply(feats, 2L, stats::sd, na.rm = TRUE)
  sigma[sigma < 1e-6] <- 1
  feats_z <- sweep(sweep(feats, 2L, mu, "-"), 2L, sigma, "/")
  feats_z[is.na(feats_z)] <- 0

  # Edge construction.
  #
  # `spatial` (the original behaviour) joins each node to its k geographically
  # nearest neighbours.  That is the natural choice for interpolation, but it
  # is pathological under spatially BLOCKED cross-validation: a held-out node's
  # neighbours are then almost all other held-out nodes, so message passing has
  # no labelled information to carry and the network cannot do better than a
  # constant.  Measured on the Cerrado benchmark folds, 96-100 % of a test
  # node's 8 nearest neighbours are other test nodes.
  #
  # `feature` joins each node to its k nearest neighbours in standardised
  # covariate space instead, so a held-out node can attend to pedologically
  # similar labelled profiles wherever they are.  `hybrid` takes the union.
  # DISTANCE. The spatial branch must use great-circle distance in km, not
  # Euclidean distance on raw degrees. The file header calls the edge weight
  # "inverse-geodesic" and it was not: stats::dist() on (lon, lat) treats a
  # degree of longitude as equal to a degree of latitude, which over the
  # Cerrado's 22 degrees of latitude understates east-west separation by up to
  # 7%. The feature branch stays Euclidean, because standardised covariate
  # space has no geometry to respect.
  gc_km <- .gc_km
  knn_from <- function(M, geodesic = FALSE) {
    D <- if (geodesic) gc_km(M) else as.matrix(stats::dist(M))
    diag(D) <- Inf
    out <- vector("list", n)
    for (i in seq_len(n)) {
      nn <- order(D[i, ])[seq_len(min(k, n - 1L))]
      out[[i]] <- data.frame(src = i, dst = nn, d = D[i, nn])
    }
    do.call(rbind, out)
  }
  # Spatial edges carry distances in KILOMETRES; feature edges carry
  # standardised-covariate distances. Mixing the two in `hybrid` mixes units,
  # which the inverse-distance weight then compares -- recorded in `d_units`
  # so a consumer can see it rather than infer it.
  e_raw <- switch(edges,
    spatial = knn_from(coords, geodesic = TRUE),
    feature = knn_from(feats_z),
    hybrid  = unique(rbind(knn_from(coords, geodesic = TRUE),
                           knn_from(feats_z))))

  # SELF-LOOPS.  The aggregation is out_i = sum_j alpha_ij Wh_j over the
  # neighbours of i.  k-NN excludes i from its own neighbour list, so without
  # an explicit self-loop a node's representation is built ENTIRELY from other
  # profiles and its own covariates never reach its own prediction -- the model
  # is structurally unable to use the most informative feature it has.
  # Velickovic et al. (2018) include self-loops for exactly this reason; the
  # graph built through v3.10.0 did not, which is the dominant reason Pillar 10
  # scored near zero on every benchmark it appeared in.
  # Distance 0 gives the self-edge the largest inverse-distance prior, so it is
  # capped at the smallest observed neighbour distance to keep the softmax from
  # saturating on it.
  if (isTRUE(self_loops)) {
    d_self <- stats::ave(e_raw$d, e_raw$src, FUN = function(z) min(z[z > 0]))
    self_e <- data.frame(src = seq_len(n), dst = seq_len(n),
                          d = tapply(d_self, e_raw$src, function(z) z[1])[
                                as.character(seq_len(n))])
    self_e$d[!is.finite(self_e$d)] <- 1
    e_raw <- rbind(e_raw, self_e)
  }

  # inverse-distance weights, normalised per source node
  e_raw$w <- 1 / (e_raw$d + 1e-9)
  e_raw$w <- e_raw$w / stats::ave(e_raw$w, e_raw$src, FUN = sum)
  edges_df <- e_raw[order(e_raw$src, e_raw$dst), ]

  structure(list(
    features        = feats_z,
    feature_mu      = mu,
    feature_sigma   = sigma,
    feature_names   = feature_cols,
    edge_index      = as.matrix(edges_df[, c("src", "dst")]),
    edge_weight     = edges_df$w,
    edge_type       = edges,
    coords          = coords,
    k               = as.integer(k),
    n               = n
  ), class = "edaphos_gnn_graph")
}

# ---------------------------------------------------------------------------
# GAT layer (pure R, vectorised)
# ---------------------------------------------------------------------------

# Vectorised, sparse-matrix GAT layer (v3.6.0).  Replaces the v2.6.0
# per-node `for (i in seq_len(n))` softmax loop with a single
# group-wise softmax on the edge vector + a sparse matrix multiply.
#
# Equivalent to the v2.6.0 implementation up to floating-point
# round-off (verified in tests/testthat/test-pilar10-gat-sparse.R).
# Performance: ~10-30x faster on n in [100, 1000] thanks to one
# `Matrix::sparseMatrix` build + one `A %*% Wh` matmul per layer
# instead of n linear scans through `edge_idx`.
.gnn_gat_layer <- function(h_in, edge_idx, edge_w, W, a_l, a_r,
                             leaky_slope = 0.2) {
  # h_in : (n x d_in)
  # W    : (d_in x d_out)
  # a_l, a_r : attention vectors, each length d_out
  n   <- nrow(h_in)
  Wh  <- h_in %*% W                      # (n x d_out)
  s_l <- as.numeric(Wh %*% a_l)
  s_r <- as.numeric(Wh %*% a_r)

  src <- edge_idx[, 1L]
  dst <- edge_idx[, 2L]
  e   <- s_l[src] + s_r[dst]
  e   <- pmax(e, leaky_slope * e)        # leaky-ReLU

  # Group-wise softmax over edges sharing a source node.  Match the
  # v2.6.0 ordering: edge_w (the inverse-distance prior) MULTIPLIES
  # the score INSIDE the exponent, not the post-softmax alpha.
  scores     <- e * edge_w
  scores_max <- stats::ave(scores, src, FUN = max)
  e_exp      <- exp(scores - scores_max)
  e_sum      <- stats::ave(e_exp, src, FUN = sum)
  alpha      <- e_exp / pmax(e_sum, .Machine$double.eps)

  # Sparse aggregation: A[i, j] = alpha_{ij}.  Out = A %*% Wh.
  if (requireNamespace("Matrix", quietly = TRUE)) {
    A <- Matrix::sparseMatrix(i = src, j = dst, x = alpha,
                                dims = c(n, n))
    out <- as.matrix(A %*% Wh)
  } else {
    # Dense fallback when `Matrix` is not available (defensive --
    # `Matrix` ships with R-recommended).
    A <- matrix(0, n, n)
    A[cbind(src, dst)] <- alpha
    out <- A %*% Wh
  }

  # Isolated nodes (no outgoing edges) keep their pre-aggregation Wh.
  has_edge <- tabulate(src, nbins = n) > 0L
  if (!all(has_edge)) out[!has_edge, ] <- Wh[!has_edge, , drop = FALSE]
  out
}


# ---------------------------------------------------------------------------
# GAT training engine (pure R, analytic gradients)
# ---------------------------------------------------------------------------
#
# Through v3.10.0 the "r" backend initialised the attention parameters W, a_l
# and a_r at random and never updated them: only the linear head was fitted.
# That is a random-feature graph encoder, not a Graph Attention Network, and
# it cannot learn which neighbours matter -- the thing GAT exists to do.
#
# The functions below implement the forward pass with a cache and the exact
# reverse-mode gradient of the loss with respect to every parameter, so the
# "r" backend now trains the same model the torch backend does, without
# requiring libtorch.  Every gradient is checked against central finite
# differences in tests/testthat/test-pilar10-gat-grad.R.
#
# Layer forward (one head), matching .gnn_gat_layer():
#   Wh    = h %*% W
#   pre_e = (Wh %*% a_l)[src] + (Wh %*% a_r)[dst]
#   e     = leaky(pre_e)                       (slope 0.2)
#   alpha = softmax_over_src(e * edge_w)
#   out_i = sum_j alpha_ij Wh_j                (isolated nodes keep Wh_i)

.gat_leaky <- function(x, slope = 0.2) pmax(x, slope * x)
.gat_dleaky <- function(x, slope = 0.2) ifelse(x > 0, 1, slope)

# grouped sum: for each edge, the sum of `v` over edges sharing the same src
.gat_group_sum <- function(v, src, n) {
  tot <- numeric(n)
  tot[] <- 0
  tot <- as.numeric(rowsum(v, group = src, reorder = FALSE))
  idx <- match(src, unique(src))
  tot[idx]
}

.gat_layer_forward <- function(h_in, edge_idx, edge_w, W, a_l, a_r,
                                slope = 0.2) {
  n   <- nrow(h_in)
  Wh  <- h_in %*% W
  s_l <- as.numeric(Wh %*% a_l)
  s_r <- as.numeric(Wh %*% a_r)
  src <- edge_idx[, 1L]; dst <- edge_idx[, 2L]
  pre <- s_l[src] + s_r[dst]
  e   <- .gat_leaky(pre, slope)
  scores <- e * edge_w
  smax   <- stats::ave(scores, src, FUN = max)
  e_exp  <- exp(scores - smax)
  e_sum  <- stats::ave(e_exp, src, FUN = sum)
  alpha  <- e_exp / pmax(e_sum, .Machine$double.eps)

  out <- matrix(0, n, ncol(Wh))
  # out[i, ] = sum_j alpha_ij Wh[j, ]
  agg <- rowsum(alpha * Wh[dst, , drop = FALSE], group = src, reorder = FALSE)
  out[as.integer(rownames(agg)), ] <- agg
  has_edge <- tabulate(src, nbins = n) > 0L
  if (!all(has_edge)) out[!has_edge, ] <- Wh[!has_edge, , drop = FALSE]

  list(out = out, Wh = Wh, pre = pre, alpha = alpha, has_edge = has_edge,
       src = src, dst = dst, edge_w = edge_w, h_in = h_in, W = W,
       a_l = a_l, a_r = a_r, slope = slope)
}

.gat_layer_backward <- function(cache, g_out) {
  n   <- nrow(cache$h_in); d_out <- ncol(cache$Wh)
  src <- cache$src; dst <- cache$dst; alpha <- cache$alpha
  g_Wh <- matrix(0, n, d_out)

  # isolated nodes bypass the aggregation entirely
  iso <- !cache$has_edge
  if (any(iso)) g_Wh[iso, ] <- g_out[iso, , drop = FALSE]
  g_out_e <- g_out
  if (any(iso)) g_out_e[iso, ] <- 0

  # d/d alpha_e and the aggregation path into Wh[dst]
  g_alpha <- rowSums(g_out_e[src, , drop = FALSE] * cache$Wh[dst, , drop = FALSE])
  contrib <- alpha * g_out_e[src, , drop = FALSE]
  acc <- rowsum(contrib, group = dst, reorder = FALSE)
  g_Wh[as.integer(rownames(acc)), ] <- g_Wh[as.integer(rownames(acc)), ] + acc

  # softmax backward within each src group
  wsum   <- stats::ave(alpha * g_alpha, src, FUN = sum)
  g_sc   <- alpha * (g_alpha - wsum)
  g_e    <- g_sc * cache$edge_w
  g_pre  <- g_e * .gat_dleaky(cache$pre, cache$slope)

  # scatter into s_l (by src) and s_r (by dst)
  g_sl <- numeric(n); g_sr <- numeric(n)
  t1 <- rowsum(g_pre, group = src, reorder = FALSE)
  g_sl[as.integer(rownames(t1))] <- as.numeric(t1)
  t2 <- rowsum(g_pre, group = dst, reorder = FALSE)
  g_sr[as.integer(rownames(t2))] <- as.numeric(t2)

  g_a_l <- as.numeric(t(cache$Wh) %*% g_sl)
  g_a_r <- as.numeric(t(cache$Wh) %*% g_sr)
  g_Wh  <- g_Wh + outer(g_sl, cache$a_l) + outer(g_sr, cache$a_r)

  list(g_W   = t(cache$h_in) %*% g_Wh,
       g_a_l = g_a_l, g_a_r = g_a_r,
       g_h   = g_Wh %*% t(cache$W))
}

# Forward pass with cache.  Exposed as an internal so the gradient check in
# tests/testthat/test-pilar10-gat-grad.R exercises the SAME code the fit uses,
# rather than a re-implementation that could agree with a shared mistake.
.gat_forward_all <- function(X, graph, Wl, al, n_layers, n_heads,
                              residual = TRUE, average_heads = TRUE) {

    h <- X
    caches <- vector("list", n_layers)
    for (l in seq_len(n_layers)) {
      hc <- vector("list", n_heads)
      for (hh in seq_len(n_heads))
        hc[[hh]] <- .gat_layer_forward(h, graph$edge_index, graph$edge_weight,
                                        Wl[[l]][[hh]], al[[l]][[hh]]$a_l,
                                        al[[l]][[hh]]$a_r)
      last <- l == n_layers
      # Velickovic et al. concatenate heads on hidden layers and AVERAGE them
      # on the output layer; the previous code concatenated everywhere.
      out <- if (last && average_heads)
        Reduce(`+`, lapply(hc, `[[`, "out")) / n_heads
      else do.call(cbind, lapply(hc, `[[`, "out"))
      pre_act <- out
      # Residual connection when the shapes allow it: without it a 2-layer
      # attention stack has to relearn the identity before it can add anything.
      did_res <- residual && ncol(out) == ncol(h)
      if (did_res) out <- out + h
      caches[[l]] <- list(heads = hc, pre_act = pre_act, h_in = h,
                           did_res = did_res, averaged = last && average_heads)
      if (!last) out <- pmax(out, 0.2 * out)   # leaky between layers
      h <- out
    }
    list(emb = h, caches = caches)
}

.gat_backward_all <- function(caches, g_emb, n_layers, n_heads, hidden) {

    g   <- g_emb
    g_W <- vector("list", n_layers)
    g_a <- vector("list", n_layers)
    for (l in rev(seq_len(n_layers))) {
      cc <- caches[[l]]
      if (l < n_layers) g <- g * ifelse(cc$pre_act > 0, 1, 0.2)
      g_skip <- if (isTRUE(cc$did_res)) g else NULL
      g_W[[l]] <- vector("list", n_heads)
      g_a[[l]] <- vector("list", n_heads)
      g_h <- matrix(0, nrow(cc$h_in), ncol(cc$h_in))
      for (hh in seq_len(n_heads)) {
        g_head <- if (isTRUE(cc$averaged)) g / n_heads
                  else g[, ((hh - 1L) * hidden + 1L):(hh * hidden), drop = FALSE]
        b <- .gat_layer_backward(cc$heads[[hh]], g_head)
        g_W[[l]][[hh]] <- b$g_W
        g_a[[l]][[hh]] <- list(a_l = b$g_a_l, a_r = b$g_a_r)
        g_h <- g_h + b$g_h
      }
      if (!is.null(g_skip)) g_h <- g_h + g_skip
      g <- g_h
    }
    list(g_W = g_W, g_a = g_a)
}

# ---------------------------------------------------------------------------
# Public GAT fit
# ---------------------------------------------------------------------------

#' Fit a Graph Attention Network on a WoSIS-style co-location graph
#'
#' @param weight_decay Numeric; L2 penalty applied to the attention
#'   projections `W`. Default `1e-4`.
#' @param residual Logical; add a skip connection around each layer whose
#'   input and output widths match. Default `TRUE`.
#' @param average_heads Logical; average the attention heads on the output
#'   layer (the convention of Velickovic et al. 2018) instead of
#'   concatenating them. Default `TRUE`.
#' @param readout_skip Logical; concatenate the raw node features to the
#'   final embedding before the regression head, so the head sees a profile's
#'   own covariates un-smoothed as well as its neighbourhood summary.
#'   Default `TRUE`. With this off the graph layers must reconstruct the input
#'   through the aggregation, and a plain linear model on the same covariates
#'   can outperform the network.
#' @param val_frac Numeric in (0, 1); fraction of the training nodes held out
#'   internally to select the stopping epoch. Default `0.2`.
#' @param train_mask Optional logical vector of length `graph$n` selecting the
#'   nodes whose target is observed.  The graph is used in full for message
#'   passing, but the regression head is fitted -- and the targets are
#'   standardised -- on these nodes only.  Defaults to `!is.na(targets)`, so
#'   held-out nodes can simply be passed as `NA` rather than given an invented
#'   value.
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
#'
#' @references
#' Veli\enc{č}{c}kovi\enc{ć}{c}, P., Cucurull, G., Casanova, A., Romero,
#' A., Li\enc{ò}{o}, P. and Bengio, Y. (2018). Graph Attention Networks.
#' *International Conference on Learning Representations*.
#'
#' Kipf, T. N. and Welling, M. (2017). Semi-Supervised Classification
#' with Graph Convolutional Networks. *International Conference on
#' Learning Representations*.
#' @examples
#' data(br_cerrado)
#' set.seed(10)
#'
#' # gnn_build_graph() wants the coordinates under `lon` / `lat`.
#' sub <- br_cerrado[sample(nrow(br_cerrado), 150L), ]
#' names(sub)[names(sub) == "x"] <- "lon"
#' names(sub)[names(sub) == "y"] <- "lat"
#' g <- gnn_build_graph(sub, k = 6L,
#'                      feature_cols = c("elev", "slope", "twi", "map_mm"))
#'
#' # Hold every third profile out by setting its target to NA: the
#' # default train_mask is !is.na(targets), so those nodes still pass
#' # messages to their neighbours but never enter the loss.
#' test  <- rep(c(FALSE, FALSE, TRUE), length.out = nrow(sub))
#' y     <- sub$soc
#' y_obs <- y; y_obs[test] <- NA
#'
#' fit <- gnn_fit(g, y_obs, hidden = 8L, n_heads = 2L, n_layers = 2L,
#'                epochs = 60L, seed = 1L)
#' c(n_train = fit$n_train, n_val = fit$n_val,
#'   epochs_run = length(fit$history), best_epoch = fit$best_epoch)
#'
#' # Score the held-out nodes against an achievable null -- the
#' # TRAINING mean -- and against OLS on the same four covariates.
#' null_mean <- mean(y[!test])
#' nse <- function(pred)
#'   1 - sum((pred - y[test])^2) / sum((y[test] - null_mean)^2)
#' ols <- lm(soc ~ elev + slope + twi + map_mm, data = sub[!test, ])
#' round(c(gat = nse(predict(fit)[test]),
#'         ols = nse(predict(ols, sub[test, ]))), 4)
#'
#' # Before crediting the graph, read `best_epoch`.  It is 1 here: no
#' # epoch of attention training beat the initialisation on the
#' # internal validation split, so what came back is the random-init
#' # encoder plus the closed-form ridge head -- and the four raw
#' # covariates the readout skip hands that head do nearly all of it.
#' fit_ns <- gnn_fit(g, y_obs, hidden = 8L, n_heads = 2L, n_layers = 2L,
#'                   epochs = 60L, seed = 1L, readout_skip = FALSE)
#' round(c(with_skip = nse(predict(fit)[test]),
#'         without   = nse(predict(fit_ns)[test])), 4)
#'
#' # Inventing a target for the held-out nodes instead of masking them
#' # -- the training mean is the usual choice -- fits the head to
#' # reproduce that invented value and drags the test set towards it.
#' y_imp <- y; y_imp[test] <- null_mean
#' fit_imp <- gnn_fit(g, y_imp, hidden = 8L, n_heads = 2L, n_layers = 2L,
#'                    epochs = 60L, seed = 1L)
#' round(c(masked = nse(predict(fit)[test]),
#'         invented = nse(predict(fit_imp)[test])), 4)
#'
#' # `history` is the TRAINING loss and the printed "final MSE" is its
#' # last entry.  Neither describes the parameters you got back, which
#' # come from `best_epoch` on the validation split.
#' round(c(train_at_best = fit$history[fit$best_epoch],
#'         train_min     = min(fit$history),
#'         train_at_end  = fit$history[length(fit$history)]), 4)
#' @export
gnn_fit <- function(graph, targets, train_mask = NULL,
                      hidden = 16L, n_heads = 4L, n_layers = 2L,
                      epochs = 200L, lr = 0.01, seed = NULL,
                      weight_decay = 1e-4, residual = TRUE,
                      average_heads = TRUE, readout_skip = TRUE,
                      val_frac = 0.2,
                      backend = c("r", "torch"),
                      device = c("cpu", "mps", "cuda")) {
  backend <- match.arg(backend)
  device  <- match.arg(device)
  # Transductive setting: the graph spans train and test nodes so message
  # passing can use the full structure, but the LOSS must be restricted to
  # nodes whose target is observed.  Without this the caller has to invent a
  # target for the held-out nodes -- the benchmark used the training mean --
  # and the head is then fitted to reproduce that invented value, dragging
  # every test prediction towards it.  Default TRUE everywhere reproduces the
  # previous behaviour for callers that genuinely observe every node.
  if (is.null(train_mask)) train_mask <- !is.na(targets)
  train_mask <- as.logical(train_mask)
  if (backend == "torch") {
    if (!requireNamespace("torch", quietly = TRUE))
      stop("Install `torch` to use backend = 'torch'.", call. = FALSE)
    return(.torch_gnn_fit(graph, targets, hidden, n_heads, n_layers,
                             epochs, lr, seed, device,
                             train_mask = train_mask,
                             readout_skip = readout_skip, val_frac = val_frac))
  }
  stopifnot(inherits(graph, "edaphos_gnn_graph"),
             length(targets) == graph$n,
             length(train_mask) == graph$n)
  if (sum(train_mask) < 2L)
    stop("`train_mask` must select at least 2 nodes with observed targets.",
          call. = FALSE)
  if (anyNA(targets[train_mask]))
    stop("`targets` must be non-missing wherever `train_mask` is TRUE.",
          call. = FALSE)
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
    # heads are concatenated on hidden layers; the output layer may average
    curr_dim <- if (l == n_layers && isTRUE(average_heads)) hidden
                else hidden * n_heads
  }
  # Final node embedding dim: averaged heads -> hidden, concatenated -> hidden*n_heads
  emb_dim <- if (isTRUE(average_heads)) hidden else hidden * n_heads
  # Readout skip: hand the raw node features to the head alongside the
  # aggregated embedding.
  #
  # Every GAT layer AVERAGES over a neighbourhood, which smooths each node's
  # covariates towards its local mean.  With no path from the input to the
  # readout, a profile's own covariate values reach the prediction only after
  # that smoothing, and the network cannot represent a function the raw
  # covariates express sharply.  Measured consequence: the aggregated-only
  # model scored below a plain OLS on the same covariates.  Concatenating the
  # input makes the linear model a special case of the GAT rather than a
  # competitor to it, which is the property a graph layer should have.
  if (isTRUE(readout_skip)) emb_dim <- emb_dim + d_in

  forward_all <- function(Wl, al) {
    f <- .gat_forward_all(X, graph, Wl, al, n_layers, n_heads, residual,
                           average_heads)
    # `emb_gat` is the learned node representation -- what gnn_embed() returns
    # and what the Pillar 6 x Pillar 10 bridge consumes.  The readout skip is a
    # property of the HEAD, so the raw features are appended only for the
    # regression design, never folded into the embedding itself.
    f$emb_gat <- f$emb
    if (isTRUE(readout_skip)) f$emb <- cbind(f$emb, X)
    f
  }
  backward_all <- function(caches, g_emb) {
    # the skip columns are the constant input X: no parameters behind them
    if (isTRUE(readout_skip))
      g_emb <- g_emb[, seq_len(ncol(g_emb) - d_in), drop = FALSE]
    .gat_backward_all(caches, g_emb, n_layers, n_heads, hidden)
  }

  # Standardise on the TRAINING nodes only -- using all nodes would leak the
  # held-out marginal distribution into the fit.
  y_mu    <- mean(targets[train_mask])
  y_sigma <- stats::sd(targets[train_mask])
  if (!is.finite(y_sigma) || y_sigma < 1e-6) y_sigma <- 1
  y_z <- (targets - y_mu) / y_sigma
  y_z_tr <- y_z[train_mask]
  n_tr_nodes <- sum(train_mask)

  # ---- Adam over attention parameters AND the linear head -----------------
  # The head alone used to be fitted while W / a_l / a_r stayed at their random
  # initialisation, so the "attention" never learned which neighbours matter.
  W_head <- rep(0, emb_dim); b_head <- 0
  lam    <- 1e-3
  b1 <- 0.9; b2 <- 0.999; eps_adam <- 1e-8
  zeros_like <- function(x) if (is.list(x)) lapply(x, zeros_like) else x * 0
  mW <- zeros_like(W_list); vW <- zeros_like(W_list)
  mA <- zeros_like(a_list); vA <- zeros_like(a_list)

  # Early stopping on an internal validation split.
  #
  # A two-layer, multi-head GAT carries a few hundred parameters; on the node
  # counts this package targets it reaches near-zero TRAINING loss while test
  # error rises.  Selecting the iterate by training loss -- which is what a
  # naive "keep the best" does -- therefore returns the most overfitted model
  # available.  Hold out a fifth of the training nodes, score every epoch on
  # them, and keep the parameters from the best validation epoch.  The held-out
  # nodes supplied by the caller are never touched by any of this.
  tr_idx  <- which(train_mask)
  n_val   <- max(1L, floor(val_frac * length(tr_idx)))
  # SORTED.  The validation loss is computed as
  #   emb[val_sel, ] %*% W_head  vs  y_z[val_idx],
  # and logical subsetting returns rows in ASCENDING node order while
  # `sample()` returns `val_idx` in a random one.  Unsorted, every epoch was
  # therefore scored against a permutation of the validation targets: the
  # criterion measured var(pred) + var(y) instead of the error, early stopping
  # selected whichever iterate predicted least, and `val_history` reported
  # roughly twice the true loss (measured on `br_cerrado`: 1.78 reported
  # against 0.78 aligned, and `best_epoch` stuck at 1 for every seed tried
  # there, i.e. the attention training was discarded wholesale).
  val_idx <- if (length(tr_idx) >= 10L) sort(sample(tr_idx, n_val))
             else integer(0)
  fit_idx <- setdiff(tr_idx, val_idx)
  fit_sel <- rep(FALSE, graph$n); fit_sel[fit_idx] <- TRUE
  val_sel <- rep(FALSE, graph$n); val_sel[val_idx] <- TRUE
  y_z_fit <- y_z[fit_idx]; y_z_val <- y_z[val_idx]
  n_fit   <- length(fit_idx)
  history <- numeric(epochs); val_history <- rep(NA_real_, epochs)
  best <- list(loss = Inf, epoch = NA_integer_)
  patience <- max(20L, ceiling(epochs / 5))
  since_improve <- 0L

  for (ep in seq_len(epochs)) {
    fw  <- forward_all(W_list, a_list)
    emb <- fw$emb
    # Solve the linear readout in CLOSED FORM instead of learning it by
    # gradient descent.  A ridge head has an exact solution given the current
    # embedding, so descending towards it wastes the optimiser's budget and --
    # far worse -- makes the validation loss meaningless in early epochs: the
    # head starts at zero, so epoch 1 IS the intercept model, and the attention
    # parameters move before the head catches up.  Early stopping then selects
    # epoch 1 and returns a constant.  Measured on the Cerrado folds, that is
    # exactly what happened: W_head came back identically zero while a ridge
    # fitted on the SAME embedding scored NSE +0.30.
    Xf <- cbind(1, emb[fit_sel, , drop = FALSE])
    P  <- diag(ncol(Xf)) * lam; P[1, 1] <- 0        # never penalise the intercept
    beta <- tryCatch(solve(crossprod(Xf) + P, crossprod(Xf, y_z_fit)),
                     error = function(e) NULL)
    if (is.null(beta)) break
    b_head <- beta[1L]; W_head <- as.numeric(beta[-1L])
    y_hat <- as.numeric(Xf %*% beta)
    err   <- y_hat - y_z_fit
    loss  <- mean(err^2) + lam * sum(W_head^2)
    history[ep] <- loss

    # model selection criterion: validation loss, never training loss
    sel_loss <- if (length(val_idx)) {
      v <- as.numeric(emb[val_sel, , drop = FALSE] %*% W_head + b_head)
      val_history[ep] <- mean((v - y_z_val)^2)
      val_history[ep]
    } else loss
    if (is.finite(sel_loss) && sel_loss < best$loss - 1e-10) {
      best <- list(loss = sel_loss, epoch = ep, W_list = W_list,
                    a_list = a_list, W_head = W_head, b_head = b_head)
      since_improve <- 0L
    } else since_improve <- since_improve + 1L
    if (since_improve >= patience) break

    # The head is optimal for this embedding, so it carries no gradient of its
    # own; it only routes the loss back into the attention parameters.
    g_yhat <- 2 * err / n_fit
    # only training rows enter the loss, so the embedding gradient is zero
    # elsewhere -- but message passing still carries it to every parameter
    g_emb <- matrix(0, nrow(emb), ncol(emb))
    g_emb[fit_sel, ] <- outer(g_yhat, W_head)
    bw <- backward_all(fw$caches, g_emb)

    step <- function(par, g, m, v) {
      m <- b1 * m + (1 - b1) * g
      v <- b2 * v + (1 - b2) * g^2
      mh <- m / (1 - b1^ep); vh <- v / (1 - b2^ep)
      list(par = par - lr * mh / (sqrt(vh) + eps_adam), m = m, v = v)
    }
    for (l in seq_len(n_layers)) for (hh in seq_len(n_heads)) {
      s <- step(W_list[[l]][[hh]],
                bw$g_W[[l]][[hh]] + weight_decay * W_list[[l]][[hh]],
                mW[[l]][[hh]], vW[[l]][[hh]])
      W_list[[l]][[hh]] <- s$par; mW[[l]][[hh]] <- s$m; vW[[l]][[hh]] <- s$v
      s <- step(a_list[[l]][[hh]]$a_l, bw$g_a[[l]][[hh]]$a_l,
                mA[[l]][[hh]]$a_l, vA[[l]][[hh]]$a_l)
      a_list[[l]][[hh]]$a_l <- s$par; mA[[l]][[hh]]$a_l <- s$m; vA[[l]][[hh]]$a_l <- s$v
      s <- step(a_list[[l]][[hh]]$a_r, bw$g_a[[l]][[hh]]$a_r,
                mA[[l]][[hh]]$a_r, vA[[l]][[hh]]$a_r)
      a_list[[l]][[hh]]$a_r <- s$par; mA[[l]][[hh]]$a_r <- s$m; vA[[l]][[hh]]$a_r <- s$v
    }
    if (!is.finite(loss)) break
  }

  # keep the best iterate rather than the last, so a late divergence in a long
  # run cannot silently degrade the fit
  if (is.finite(best$loss)) {
    W_list <- best$W_list; a_list <- best$a_list
    W_head <- best$W_head; b_head <- best$b_head
  }
  fw_final <- forward_all(W_list, a_list)
  emb      <- fw_final$emb_gat        # learned representation, no skip columns
  design   <- fw_final$emb            # what the head was fitted on
  n_ran   <- if (is.na(best$epoch)) length(history) else
             max(best$epoch, sum(history != 0))
  history <- history[seq_len(n_ran)]
  val_history <- val_history[seq_len(n_ran)]

  structure(list(
    backend  = "r",
    graph    = graph,
    targets  = targets,
    train_mask = train_mask,
    n_train  = sum(train_mask),
    emb          = emb,
    head_design  = design,
    readout_skip = readout_skip,
    y_mu     = y_mu, y_sigma = y_sigma,
    W_list   = W_list, a_list = a_list,
    W_head   = W_head, b_head = b_head,
    hidden   = hidden, n_heads = n_heads, n_layers = n_layers,
    emb_dim  = emb_dim,
    history      = history,
    val_history  = val_history,
    best_epoch   = best$epoch,
    n_val        = length(val_idx)
  ), class = "edaphos_gnn_gat")
}

#' Seed ensemble of GAT fits
#'
#' Fits `n_ensemble` independent GATs that differ only in their random seed --
#' which drives the attention initialisation and the internal validation split
#' -- and averages their predictions.
#'
#' A single GAT is one model; a quantile regression forest is an ensemble of
#' hundreds of trees. Comparing the two directly measures the ensembling as
#' much as the method, so a fair head-to-head gives the network an ensemble
#' too. Averaging also damps the run-to-run variance that a single
#' gradient-trained fit carries on datasets of this size.
#'
#' @inheritParams gnn_fit
#' @param n_ensemble Integer; number of members. Default `10L`.
#' @param ... Further arguments passed to [gnn_fit()] for every member --
#'   `hidden`, `n_heads`, `n_layers`, `epochs`, `lr`, `weight_decay`,
#'   `residual`, `average_heads`, `readout_skip`, `val_frac`, `backend`,
#'   `device`. Members differ only in their seed.
#' @return An `edaphos_gnn_ensemble` carrying the member fits, the averaged
#'   node predictions, and the between-member standard deviation (a cheap
#'   epistemic spread).
#' @examples
#' data(br_cerrado)
#' set.seed(10)
#'
#' sub <- br_cerrado[sample(nrow(br_cerrado), 150L), ]
#' names(sub)[names(sub) == "x"] <- "lon"
#' names(sub)[names(sub) == "y"] <- "lat"
#' g <- gnn_build_graph(sub, k = 6L,
#'                      feature_cols = c("elev", "slope", "twi", "map_mm"))
#'
#' test  <- rep(c(FALSE, FALSE, TRUE), length.out = nrow(sub))
#' y     <- sub$soc
#' y_obs <- y; y_obs[test] <- NA
#'
#' ens <- gnn_fit_ensemble(g, y_obs, n_ensemble = 4L, seed = 1L,
#'                         hidden = 8L, n_heads = 2L, n_layers = 2L,
#'                         epochs = 60L)
#' ens
#'
#' # Members differ only in their seed.  That alone moves the held-out
#' # score by more than most modelling choices do, which is the whole
#' # argument for reporting an ensemble instead of one lucky fit.
#' null_mean <- mean(y[!test])
#' nse <- function(pred)
#'   1 - sum((pred - y[test])^2) / sum((y[test] - null_mean)^2)
#' member <- vapply(ens$members, function(m) nse(predict(m)[test]),
#'                  numeric(1))
#' round(c(worst = min(member), mean = mean(member), best = max(member),
#'         ensemble = nse(predict(ens)[test])), 4)
#'
#' # Note what averaging does and does not buy: it beats the AVERAGE
#' # member, not the best one -- and which seed was best is knowable
#' # only from the held-out labels you are not supposed to have.
#'
#' # `member_sd` is the spread BETWEEN seeds, not a predictive
#' # interval.  It is under a fifth of the actual error here, so a
#' # +-1.96 sd band covers a quarter of the profiles, not 95 percent.
#' round(c(rmse       = sqrt(mean((predict(ens)[test] - y[test])^2)),
#'         mean_sd    = mean(ens$member_sd[test]),
#'         coverage95 = mean(abs(y[test] - predict(ens)[test]) <=
#'                           1.96 * ens$member_sd[test])), 3)
#' @export
gnn_fit_ensemble <- function(graph, targets, train_mask = NULL,
                               n_ensemble = 10L, seed = NULL, ...) {
  n_ensemble <- as.integer(n_ensemble)
  if (!is.finite(n_ensemble) || n_ensemble < 1L)
    stop("`n_ensemble` must be a positive integer.", call. = FALSE)
  base_seed <- if (is.null(seed)) 0L else as.integer(seed)
  members <- lapply(seq_len(n_ensemble), function(b)
    gnn_fit(graph, targets, train_mask = train_mask,
             seed = base_seed + b, ...))
  P <- vapply(members, stats::predict, numeric(graph$n))
  if (is.null(dim(P))) P <- matrix(P, nrow = graph$n)
  structure(list(
    members    = members,
    n_ensemble = n_ensemble,
    prediction = rowMeans(P),
    member_sd  = if (n_ensemble > 1L) apply(P, 1L, stats::sd)
                 else rep(0, graph$n),
    graph      = graph,
    train_mask = members[[1L]]$train_mask
  ), class = "edaphos_gnn_ensemble")
}

#' @export
predict.edaphos_gnn_ensemble <- function(object, ...) object$prediction

#' @export
print.edaphos_gnn_ensemble <- function(x, ...) {
  cat("<edaphos_gnn_ensemble>\n")
  cat(sprintf("  members = %d   nodes = %d   trained on = %d\n",
              x$n_ensemble, length(x$prediction), sum(x$train_mask)))
  cat(sprintf("  mean between-member sd = %.4g\n", mean(x$member_sd)))
  invisible(x)
}

#' Node-level embeddings from a fitted GAT
#'
#' @param object An `edaphos_gnn_gat` fit.  A `gnn_fit_ensemble()`
#'   result is not accepted; pass one of its `members` instead.
#' @return A matrix with one row per node in the graph -- every node,
#'   not only the training ones, since message passing runs over the
#'   whole graph.  The column count follows the `average_heads`
#'   argument of [gnn_fit()]: `hidden` columns when it is `TRUE` (the
#'   default, heads averaged) and `hidden * n_heads` when it is
#'   `FALSE` (heads concatenated).
#' @examples
#' data(br_cerrado)
#' set.seed(10)
#'
#' sub <- br_cerrado[sample(nrow(br_cerrado), 150L), ]
#' names(sub)[names(sub) == "x"] <- "lon"
#' names(sub)[names(sub) == "y"] <- "lat"
#' g <- gnn_build_graph(sub, k = 6L,
#'                      feature_cols = c("elev", "slope", "twi", "map_mm"))
#'
#' test  <- rep(c(FALSE, FALSE, TRUE), length.out = nrow(sub))
#' y_obs <- sub$soc; y_obs[test] <- NA
#' fit <- gnn_fit(g, y_obs, hidden = 8L, n_heads = 2L, n_layers = 2L,
#'                epochs = 60L, seed = 1L)
#' emb <- gnn_embed(fit)
#'
#' # One row per NODE, not per training node: message passing ran over
#' # the whole graph, so the 50 held-out profiles carry embeddings too.
#' c(rows = nrow(emb), cols = ncol(emb),
#'   nodes = g$n, trained_on = fit$n_train)
#'
#' # The embedding is NOT the design the head was fitted on.  With
#' # `readout_skip` (the default) the head also saw the raw features
#' # un-smoothed, so a downstream model fed `emb` alone is missing
#' # four columns -- and the readout_skip comparison in [gnn_fit()]
#' # shows how much of the score lives in them.
#' c(emb = ncol(emb), design = ncol(fit$head_design),
#'   raw_features = ncol(g$features))
#' isTRUE(all.equal(fit$head_design, cbind(emb, g$features),
#'                  check.attributes = FALSE))
#'
#' # The column count follows `average_heads`: averaged (the default)
#' # gives `hidden`, concatenated gives hidden * n_heads.
#' fit_cat <- gnn_fit(g, y_obs, hidden = 8L, n_heads = 2L, n_layers = 2L,
#'                    epochs = 60L, seed = 1L, average_heads = FALSE)
#' c(averaged = ncol(emb), concatenated = ncol(gnn_embed(fit_cat)))
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
  design <- if (!is.null(object$head_design)) object$head_design else object$emb
  y_z <- as.numeric(design %*% object$W_head + object$b_head)
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
