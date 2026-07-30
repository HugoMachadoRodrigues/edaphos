# Pilar 10 -- torch/autograd GAT backend (edaphos v2.7.0).
#
# Replaces the v2.6.0 "ELM-style" GAT (hidden layers fixed at random
# init, analytic gradient only on the linear head) with full
# backprop through every attention layer.
#
# v2.7.x port: the first autograd version trained a plain linear head
# end-to-end with no input skip and no early stopping, and overfit badly
# on the small transductive graphs this package targets -- NSE ~ -0.40
# (worse than the mean) on held-out Cerrado nodes. It now carries the two
# mechanisms the R backend already had: a READOUT SKIP (raw node features
# concatenated to the head input, so a node keeps direct access to its own
# covariates past the neighbourhood averaging) and BEST-VALIDATION early
# stopping (a held-out fifth of the training nodes selects the iterate,
# instead of training loss, which returns the most overfit model). With
# both, the torch GAT reaches NSE ~ 0.52 -- competitive with the R backend
# and OLS, though not beating them.
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
                                 d_out = 1L, readout_skip = TRUE) {
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
      self$emb_dim <- curr
      self$readout_skip <- readout_skip
      # Readout skip: hand the raw node features to the head alongside the
      # aggregated embedding. Every GAT layer averages over a neighbourhood,
      # smoothing each node's covariates towards its local mean; without a path
      # from the input to the readout the aggregated-only model scored below a
      # plain OLS. Concatenating the input makes the linear model a special case
      # of the GAT rather than a competitor to it -- the same fix the R backend
      # carries -- and is what lifts the torch GAT off its previous NSE < 0.
      self$head <- torch::nn_linear(curr + if (readout_skip) d_in else 0L, d_out)
      self$n_layers <- n_layers
    },
    # returns the GAT embedding (before the skip concat), for gnn_embed()
    encode = function(h, edge_index, edge_weight) {
      for (l in seq_len(self$n_layers)) {
        h <- self$layers[[l]](h, edge_index, edge_weight)
        if (l < self$n_layers)
          h <- torch::nnf_leaky_relu(h, negative_slope = 0.2)
      }
      h
    },
    forward = function(h, edge_index, edge_weight) {
      h0 <- h
      z  <- self$encode(h, edge_index, edge_weight)
      if (self$readout_skip) z <- torch::torch_cat(list(z, h0), dim = 2L)
      self$head(z)$squeeze(2L)
    }
  )()
}

# ---------------------------------------------------------------------------
# Torch fit
# ---------------------------------------------------------------------------

.torch_gnn_fit <- function(graph, targets, hidden, n_heads,
                              n_layers, epochs, lr, seed, device_pref,
                              train_mask = NULL, readout_skip = TRUE,
                              val_frac = 0.2) {
  # See gnn_fit(): the graph spans train and test nodes, but the loss is
  # restricted to nodes whose target is observed.
  if (is.null(train_mask)) train_mask <- !is.na(targets)
  train_mask <- as.logical(train_mask)
  stopifnot(length(train_mask) == graph$n, sum(train_mask) >= 2L)
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
  # standardise on training nodes only
  y_mu <- mean(targets[train_mask]); y_sigma <- stats::sd(targets[train_mask])
  if (!is.finite(y_sigma) || y_sigma < 1e-6) y_sigma <- 1
  y_z  <- (targets - y_mu) / y_sigma
  y_z[!train_mask] <- 0        # never read; keeps the tensor finite

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
  # Internal validation split for early stopping. A multi-head GAT reaches
  # near-zero TRAINING loss on these node counts while test error rises, so
  # selecting by training loss returns the most overfitted iterate -- which is
  # how the torch GAT previously scored below the mean. Hold out a fifth of the
  # training nodes, score every epoch on them, and keep the best-validation
  # parameters. The caller's held-out nodes are never touched.
  tr_all  <- which(train_mask)
  n_val   <- if (length(tr_all) >= 10L)
               max(1L, floor(val_frac * length(tr_all))) else 0L
  val_idx <- if (n_val > 0L) sort(sample(tr_all, n_val)) else integer(0)
  fit_idx <- setdiff(tr_all, val_idx)
  fit_t <- torch::torch_tensor(fit_idx, dtype = torch::torch_long(), device = dev)
  val_t <- if (length(val_idx))
             torch::torch_tensor(val_idx, dtype = torch::torch_long(),
                                 device = dev) else NULL

  mod <- .torch_gat_module(d_in, hidden, n_heads, n_layers,
                             readout_skip = readout_skip)
  mod$to(device = dev)
  opt <- torch::optim_adam(mod$parameters, lr = lr, weight_decay = 1e-4)

  history <- numeric(epochs); val_history <- rep(NA_real_, epochs)
  best <- list(loss = Inf, epoch = NA_integer_, state = NULL)
  patience <- max(20L, ceiling(epochs / 5)); since_improve <- 0L
  clone_state <- function() lapply(mod$state_dict(), function(t) t$detach()$clone())

  ep_run <- 0L
  for (ep in seq_len(epochs)) {
    ep_run <- ep
    mod$train(); opt$zero_grad()
    loss <- torch::nnf_mse_loss(mod(h_t, edge_idx_t, edge_w_t)[fit_t], y_t[fit_t])
    loss$backward(); opt$step()
    history[ep] <- as.numeric(loss$detach()$to(device = "cpu"))
    vloss <- if (!is.null(val_t)) {
      mod$eval()
      as.numeric(torch::with_no_grad(
        torch::nnf_mse_loss(mod(h_t, edge_idx_t, edge_w_t)[val_t],
                            y_t[val_t]))$to(device = "cpu"))
    } else history[ep]
    val_history[ep] <- vloss
    if (is.finite(vloss) && vloss < best$loss - 1e-8) {
      best <- list(loss = vloss, epoch = ep, state = clone_state())
      since_improve <- 0L
    } else since_improve <- since_improve + 1L
    if (since_improve >= patience) break
    if (is.finite(history[ep]) && history[ep] < 1e-8) break
  }
  if (!is.null(best$state)) mod$load_state_dict(best$state)

  # Node embeddings = GAT encoder output (before the skip concat and head),
  # matching gnn_embed() semantics.
  mod$eval()
  emb_t <- torch::with_no_grad(mod$encode(h_t, edge_idx_t, edge_w_t))
  emb_mat <- as.matrix(as.array(emb_t$detach()$to(device = "cpu")))

  structure(list(
    backend = "torch",
    graph = graph, targets = targets,
    torch_module = mod, device = device_str,
    emb = emb_mat,
    y_mu = y_mu, y_sigma = y_sigma,
    train_mask = train_mask, n_train = sum(train_mask),
    n_val = length(val_idx), readout_skip = readout_skip,
    hidden = hidden, n_heads = n_heads, n_layers = n_layers,
    emb_dim = ncol(emb_mat),
    best_epoch = best$epoch,
    history = history[seq_len(ep_run)],
    val_history = val_history[seq_len(ep_run)]
  ), class = "edaphos_gnn_gat")
}
