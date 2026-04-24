# Pilar 10 -- torch/autograd GAT backend (edaphos v2.7.0).
#
# Replaces the v2.6.0 "ELM-style" GAT (hidden layers fixed at random
# init, analytic gradient only on the linear head) with full
# backprop through every attention layer.
#
# Vectorisation
# -------------
# For a graph with `n` nodes, `E` edges and a hidden width `d`, the
# attention score matrix in a single-head GAT layer is computed as:
#
#     alpha_e = softmax_{src} ( LeakyReLU( a^top [W h_{src(e)} || W h_{dst(e)}] ) )
#
# We build this as a dense (n x d_out) matrix multiplication and then
# scatter-add via an edge-index lookup.  For small pedometric graphs
# (n <= 5 000) this is dense-safe; a sparse (torch_sparse) version is
# future work.

# ---------------------------------------------------------------------------
# Multi-head GAT layer
# ---------------------------------------------------------------------------

.torch_gat_layer <- function(d_in, d_out, n_heads,
                               leaky_slope = 0.2,
                               concat = TRUE) {
  torch::nn_module(
    "edaphos_gat_layer",
    initialize = function() {
      self$W  <- torch::nn_linear(d_in, d_out * n_heads, bias = FALSE)
      self$a_l <- torch::nn_parameter(
        torch::torch_randn(c(n_heads, d_out)) * 0.1
      )
      self$a_r <- torch::nn_parameter(
        torch::torch_randn(c(n_heads, d_out)) * 0.1
      )
      self$d_out  <- d_out
      self$n_heads <- n_heads
      self$leaky_slope <- leaky_slope
      self$concat <- concat
    },
    forward = function(h, edge_index, edge_weight) {
      # h: (n, d_in); edge_index: (E, 2) (src, dst)
      n <- h$size(1L)
      Wh <- self$W(h)$reshape(c(n, self$n_heads, self$d_out))
      # Attention logits per head per edge
      src <- edge_index[, 1L]   # 1-based
      dst <- edge_index[, 2L]
      # s_l = sum_d (Wh[i] * a_l)  -> shape (n, n_heads)
      s_l <- (Wh * self$a_l$unsqueeze(1L))$sum(dim = 3L)
      s_r <- (Wh * self$a_r$unsqueeze(1L))$sum(dim = 3L)
      e <- s_l[src] + s_r[dst]           # (E, n_heads)
      e <- torch::nnf_leaky_relu(e, negative_slope = self$leaky_slope)
      # Softmax-normalise edges by source node  (per head)
      # Dense-safe: for each source, compute exp(e) / sum(exp(e))
      exp_e <- torch::torch_exp(e - e$max()) * edge_weight$unsqueeze(2L)
      # Sum per source: scatter add
      denom <- torch::torch_zeros(c(n, self$n_heads), device = e$device)
      denom <- denom$index_add(1L, src, exp_e)
      alpha_e <- exp_e / (denom[src] + 1e-8)    # (E, n_heads)
      # Aggregate neighbour features: sum alpha_e * Wh[dst]
      msg <- alpha_e$unsqueeze(3L) * Wh[dst]    # (E, n_heads, d_out)
      out <- torch::torch_zeros(c(n, self$n_heads, self$d_out),
                                  device = h$device)
      out <- out$index_add(1L, src, msg)
      if (self$concat) {
        out$reshape(c(n, self$n_heads * self$d_out))
      } else {
        out$mean(dim = 2L)
      }
    }
  )()
}

# ---------------------------------------------------------------------------
# Full GAT module
# ---------------------------------------------------------------------------

.torch_gat_module <- function(d_in, hidden, n_heads, n_layers,
                                 d_out = 1L) {
  torch::nn_module(
    "edaphos_gat",
    initialize = function() {
      layers <- list()
      curr <- d_in
      for (l in seq_len(n_layers)) {
        concat_l <- (l < n_layers)
        layers[[l]] <- .torch_gat_layer(curr, hidden, n_heads,
                                           concat = concat_l)
        curr <- if (concat_l) hidden * n_heads else hidden
      }
      self$layers <- torch::nn_module_list(layers)
      self$head   <- torch::nn_linear(curr, d_out)
      self$n_layers <- n_layers
    },
    forward = function(h, edge_index, edge_weight) {
      for (l in seq_len(self$n_layers)) {
        h <- self$layers[[l]](h, edge_index, edge_weight)
        if (l < self$n_layers) {
          h <- torch::nnf_leaky_relu(h, negative_slope = 0.2)
        }
      }
      self$head(h)$squeeze(2L)
    }
  )()
}

# ---------------------------------------------------------------------------
# Torch fit
# ---------------------------------------------------------------------------

.torch_gnn_fit <- function(graph, targets, hidden, n_heads,
                              n_layers, epochs, lr, seed, device_pref) {
  if (!is.null(seed)) {
    set.seed(seed); torch::torch_manual_seed(seed)
  }
  device_str <- if (identical(device_pref, "mps") &&
                      torch::backends_mps_is_available()) "mps"
                 else if (identical(device_pref, "cuda") &&
                             torch::cuda_is_available()) "cuda"
                 else "cpu"
  dev <- torch::torch_device(device_str)

  X <- graph$features
  d_in <- ncol(X)

  # Standardise targets
  y_mu <- mean(targets); y_sigma <- stats::sd(targets)
  if (y_sigma < 1e-6) y_sigma <- 1
  y_z  <- (targets - y_mu) / y_sigma

  h_t <- torch::torch_tensor(X, dtype = torch::torch_float(),
                                device = dev)
  edge_idx_t <- torch::torch_tensor(graph$edge_index,
                                        dtype = torch::torch_long(),
                                        device = dev)
  edge_w_t <- torch::torch_tensor(graph$edge_weight,
                                      dtype = torch::torch_float(),
                                      device = dev)
  y_t <- torch::torch_tensor(y_z, dtype = torch::torch_float(),
                                device = dev)

  mod <- .torch_gat_module(d_in, hidden, n_heads, n_layers)
  mod$to(device = dev)
  opt <- torch::optim_adam(mod$parameters, lr = lr,
                              weight_decay = 1e-4)
  history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    opt$zero_grad()
    pred <- mod(h_t, edge_idx_t, edge_w_t)
    loss <- torch::nnf_mse_loss(pred, y_t)
    loss$backward()
    opt$step()
    history[ep] <- as.numeric(loss$detach()$to(device = "cpu"))
    if (is.finite(history[ep]) && history[ep] < 1e-6) break
  }

  # Final node embeddings (last GAT layer output, before head)
  # We run through all but the head to get (n, emb_dim)
  mod$eval()
  emb_t <- torch::with_no_grad({
    e <- h_t
    for (l in seq_len(mod$n_layers)) {
      e <- mod$layers[[l]](e, edge_idx_t, edge_w_t)
      if (l < mod$n_layers)
        e <- torch::nnf_leaky_relu(e, negative_slope = 0.2)
    }
    e
  })
  emb_mat <- as.matrix(as.array(emb_t$detach()$to(device = "cpu")))

  structure(list(
    backend = "torch",
    graph = graph, targets = targets,
    torch_module = mod, device = device_str,
    emb = emb_mat,
    y_mu = y_mu, y_sigma = y_sigma,
    hidden = hidden, n_heads = n_heads, n_layers = n_layers,
    emb_dim = ncol(emb_mat),
    history = history[history > 0 | is.na(history)]
  ), class = "edaphos_gnn_gat")
}
