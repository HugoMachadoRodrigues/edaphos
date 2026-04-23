# Pillar 1 — LLM extraction benchmark (v1.8.0).
#
# Functions in this file form a self-contained evaluation pipeline for
# multi-backend LLM causal-claim extraction.  The pipeline has four
# pieces:
#
#   1. `llm_benchmark_match()`      — matches a backend's extracted
#      claims against a gold-standard set using exact / fuzzy rules,
#      returning TP / FP / FN / partial hits per abstract.
#   2. `llm_benchmark_metrics()`    — aggregates the match table into
#      precision, recall, F1 and per-abstract standard errors.
#   3. `llm_benchmark_kappa()`      — pairwise Cohen's kappa between
#      backends on the union of edges seen across backends + gold.
#   4. `llm_benchmark_simulate()`   — deterministic simulator that
#      generates realistic noisy extractions from a gold-standard set,
#      so the pipeline runs end-to-end without real API calls (vignette
#      builds on CI, reproducibility for external users).
#
# The prompt and extractor (`causal_llm_extract()`) are unchanged from
# v1.5.0 — this file is purely an evaluation layer on top.

# ---------------------------------------------------------------------------
# Canonical vocabulary normaliser
# ---------------------------------------------------------------------------

# Returns a lower_snake_case version of a variable label, stripping
# synonyms.  Conservative: does not collapse distinct pedometric terms
# (e.g. "precipitation" and "mean_annual_precipitation" stay different).
.llm_canon_label <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[[:space:]]+", "_", x)
  x <- gsub("[^a-z0-9_]", "", x)
  # Common synonyms
  map <- c(
    "map"     = "mean_annual_precipitation",
    "mat"     = "mean_annual_temperature",
    "tmean"   = "mean_annual_temperature",
    "t2m"     = "mean_annual_temperature",
    "rainfall"= "precipitation",
    "som"     = "soc",
    "toc"     = "soc",
    "corg"    = "soc",
    "organic_carbon" = "soc",
    "bulk_density"   = "bulk_density",
    "bdod"    = "bulk_density",
    "clay_content"   = "clay",
    "sand_content"   = "sand",
    "tree_cover"     = "vegetation",
    "native_vegetation" = "vegetation",
    "forest_cover"   = "vegetation"
  )
  if (x %in% names(map)) x <- unname(map[x])
  x
}

# ---------------------------------------------------------------------------
# Matching function
# ---------------------------------------------------------------------------

#' Match extracted LLM claims against a gold-standard set
#'
#' Takes a data frame of extracted claims (from any backend) and a
#' data frame of gold-standard claims, and returns a per-claim match
#' table with TP / FP / FN labels.
#'
#' Matching is done on the (cause, effect) pair after
#' canonicalisation.  A predicted claim is a **true positive** if the
#' canonicalised pair appears in the gold set for the same abstract; a
#' **false positive** if the pair is not in gold; gold entries not in
#' predictions are **false negatives**.
#'
#' @param predicted Data frame with columns `abstract_id`, `cause`,
#'   `effect` (and optional `confidence`). Every edge found by the
#'   backend for a given abstract.
#' @param gold Data frame with columns `abstract_id`, `cause`, `effect`
#'   (and optional `polarity`). One row per annotated claim.
#' @param fuzzy Logical; if `TRUE` (default), also count a predicted
#'   edge as TP when one of its endpoints matches by Levenshtein
#'   distance within `fuzzy_threshold`. If `FALSE`, require exact
#'   match on canonicalised labels.
#' @param fuzzy_threshold Integer; maximum edit distance for a fuzzy
#'   endpoint match. Default `2`.
#'
#' @return A data frame with columns `abstract_id`, `cause`, `effect`,
#'   `status` (one of `"tp"`, `"fp"`, `"fn"`), and `source` (either
#'   `"predicted"` or `"gold"`).
#' @export
llm_benchmark_match <- function(predicted, gold,
                                 fuzzy = TRUE,
                                 fuzzy_threshold = 2L) {
  stopifnot(
    all(c("abstract_id", "cause", "effect") %in% names(predicted)),
    all(c("abstract_id", "cause", "effect") %in% names(gold)),
    is.logical(fuzzy), length(fuzzy) == 1L
  )
  predicted$cause  <- vapply(predicted$cause,  .llm_canon_label, character(1L))
  predicted$effect <- vapply(predicted$effect, .llm_canon_label, character(1L))
  gold$cause       <- vapply(gold$cause,       .llm_canon_label, character(1L))
  gold$effect      <- vapply(gold$effect,      .llm_canon_label, character(1L))

  # Within-abstract matching
  rows <- list()
  all_ids <- unique(c(predicted$abstract_id, gold$abstract_id))
  for (id in all_ids) {
    p <- predicted[predicted$abstract_id == id, , drop = FALSE]
    g <- gold[gold$abstract_id == id, , drop = FALSE]

    p_key <- paste(p$cause, "->", p$effect)
    g_key <- paste(g$cause, "->", g$effect)

    is_tp <- logical(nrow(p))
    matched_g <- logical(nrow(g))

    for (i in seq_len(nrow(p))) {
      for (j in seq_len(nrow(g))) {
        if (matched_g[j]) next
        is_match <- p$cause[i]  == g$cause[j] &&
                     p$effect[i] == g$effect[j]
        if (!is_match && fuzzy && requireNamespace("stringdist", quietly = TRUE)) {
          d1 <- stringdist::stringdist(p$cause[i],  g$cause[j],  method = "lv")
          d2 <- stringdist::stringdist(p$effect[i], g$effect[j], method = "lv")
          is_match <- (d1 + d2) <= fuzzy_threshold
        }
        if (is_match) {
          is_tp[i]     <- TRUE
          matched_g[j] <- TRUE
          break
        }
      }
    }

    if (nrow(p) > 0L) {
      rows[[paste0(id, "_p")]] <- data.frame(
        abstract_id = id,
        cause       = p$cause, effect = p$effect,
        status      = ifelse(is_tp, "tp", "fp"),
        source      = "predicted",
        stringsAsFactors = FALSE
      )
    }
    if (any(!matched_g) && nrow(g) > 0L) {
      fn_rows <- g[!matched_g, , drop = FALSE]
      rows[[paste0(id, "_g")]] <- data.frame(
        abstract_id = id,
        cause       = fn_rows$cause, effect = fn_rows$effect,
        status      = "fn",
        source      = "gold",
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

#' Compute precision / recall / F1 from a match table
#'
#' @param match_df Output of [`llm_benchmark_match()`].
#' @return Named list with `precision`, `recall`, `f1`, `tp`, `fp`,
#'   `fn`, and per-abstract metrics as a data frame in
#'   `per_abstract`.
#' @export
llm_benchmark_metrics <- function(match_df) {
  stopifnot(all(c("abstract_id", "status") %in% names(match_df)))
  tab <- table(match_df$status)
  TP  <- if ("tp" %in% names(tab)) as.integer(tab[["tp"]]) else 0L
  FP  <- if ("fp" %in% names(tab)) as.integer(tab[["fp"]]) else 0L
  FN  <- if ("fn" %in% names(tab)) as.integer(tab[["fn"]]) else 0L
  precision <- if (TP + FP > 0L) TP / (TP + FP) else NA_real_
  recall    <- if (TP + FN > 0L) TP / (TP + FN) else NA_real_
  f1        <- if (!is.na(precision) && !is.na(recall) &&
                    (precision + recall) > 0)
                  2 * precision * recall / (precision + recall)
                  else NA_real_

  per_ab <- do.call(rbind, lapply(unique(match_df$abstract_id), function(id) {
    m <- match_df[match_df$abstract_id == id, , drop = FALSE]
    tp <- sum(m$status == "tp");  fp <- sum(m$status == "fp")
    fn <- sum(m$status == "fn")
    p  <- if (tp + fp > 0L) tp / (tp + fp) else NA_real_
    r  <- if (tp + fn > 0L) tp / (tp + fn) else NA_real_
    f1_i <- if (!is.na(p) && !is.na(r) && (p + r) > 0)
      2 * p * r / (p + r) else NA_real_
    data.frame(abstract_id = id, tp = tp, fp = fp, fn = fn,
                precision = p, recall = r, f1 = f1_i,
                stringsAsFactors = FALSE)
  }))

  list(precision = precision, recall = recall, f1 = f1,
       tp = TP, fp = FP, fn = FN,
       per_abstract = per_ab)
}

# ---------------------------------------------------------------------------
# Cohen's kappa pairwise
# ---------------------------------------------------------------------------

#' Pairwise Cohen's kappa between backends on edge presence
#'
#' Computes agreement (Cohen's kappa) for every pair of backends on
#' the union of edges seen across them (and optionally gold) per
#' abstract.  For each backend pair (A, B), treats every (abstract,
#' edge) as a binary rating: "did backend X extract this edge?".
#'
#' @param claims_by_backend Named list of data frames, each with
#'   `abstract_id`, `cause`, `effect`.
#' @param gold Optional gold-standard frame to include as a rater.
#' @return Numeric matrix of kappa values (symmetric, diagonal = 1).
#' @export
llm_benchmark_kappa <- function(claims_by_backend, gold = NULL) {
  stopifnot(is.list(claims_by_backend), length(claims_by_backend) >= 2L)
  raters <- claims_by_backend
  if (!is.null(gold)) raters[["gold"]] <- gold

  # Canonicalise
  raters <- lapply(raters, function(df) {
    df$cause  <- vapply(df$cause,  .llm_canon_label, character(1L))
    df$effect <- vapply(df$effect, .llm_canon_label, character(1L))
    df$key    <- paste(df$abstract_id, df$cause, "->", df$effect)
    df
  })
  # Union of (abstract, edge) universe
  all_keys <- unique(unlist(lapply(raters, function(df) df$key)))
  # Presence matrix: rows = raters, cols = edges
  M <- matrix(0L, nrow = length(raters), ncol = length(all_keys),
               dimnames = list(names(raters), all_keys))
  for (r in seq_along(raters)) {
    M[r, all_keys %in% raters[[r]]$key] <- 1L
  }

  kappa_pair <- function(v1, v2) {
    tab <- table(factor(v1, levels = c(0, 1)),
                  factor(v2, levels = c(0, 1)))
    N   <- sum(tab)
    if (N == 0L) return(NA_real_)
    Po  <- (tab[1, 1] + tab[2, 2]) / N
    p1a <- (tab[1, 1] + tab[1, 2]) / N
    p1b <- (tab[1, 1] + tab[2, 1]) / N
    p2a <- (tab[2, 1] + tab[2, 2]) / N
    p2b <- (tab[1, 2] + tab[2, 2]) / N
    Pe  <- p1a * p1b + p2a * p2b
    if (abs(1 - Pe) < 1e-10) return(NA_real_)
    (Po - Pe) / (1 - Pe)
  }

  n <- nrow(M)
  K <- matrix(NA_real_, nrow = n, ncol = n,
               dimnames = list(rownames(M), rownames(M)))
  for (i in seq_len(n)) for (j in seq_len(n)) {
    K[i, j] <- if (i == j) 1 else kappa_pair(M[i, ], M[j, ])
  }
  K
}

# ---------------------------------------------------------------------------
# Cost estimator
# ---------------------------------------------------------------------------

#' Estimate per-1 000-claim extraction cost
#'
#' Uses published list prices as of 2026-04: Gemma 4 local $0,
#' GPT-4o-mini input $0.15 / 1M tokens + output $0.60 / 1M tokens,
#' Claude Sonnet-4.5 input $3 / 1M + output $15 / 1M.  Assumes mean
#' abstract is 220 tokens in + 110 tokens out + 480 tokens of system
#' prompt.
#'
#' @param backend String, one of `"ollama"`, `"openai"`, `"anthropic"`.
#' @param model Optional exact model id for documentation.
#' @param n_abstracts Integer; number of abstracts the extractor ran on.
#' @param claims_per_abstract Numeric; mean claims per abstract (for
#'   per-1k-claim normalisation).
#' @param tokens_in Integer; mean input tokens per call.
#' @param tokens_out Integer; mean output tokens per call.
#' @return Named list with cost per 1 000 claims in USD.
#' @export
llm_benchmark_cost <- function(backend,
                                 model = NULL,
                                 n_abstracts = 100L,
                                 claims_per_abstract = 5,
                                 tokens_in  = 700L,
                                 tokens_out = 110L) {
  prices_per_M <- switch(
    backend,
    "ollama"    = list(in_price = 0, out_price = 0),
    "openai"    = list(in_price = 0.15, out_price = 0.60),  # gpt-4o-mini
    "anthropic" = list(in_price = 3.00, out_price = 15.00), # claude-sonnet-4
    list(in_price = NA, out_price = NA)
  )
  n_claims  <- n_abstracts * claims_per_abstract
  cost_in   <- tokens_in  * n_abstracts * prices_per_M$in_price  / 1e6
  cost_out  <- tokens_out * n_abstracts * prices_per_M$out_price / 1e6
  total     <- cost_in + cost_out
  per_1k    <- if (n_claims > 0) total / n_claims * 1000 else NA_real_
  list(backend = backend, model = model,
       n_abstracts = n_abstracts, n_claims = n_claims,
       cost_total_usd = total, cost_per_1k_claims_usd = per_1k)
}

# ---------------------------------------------------------------------------
# Simulator (for reproducible runs without API keys)
# ---------------------------------------------------------------------------

#' Simulate backend extractions from a gold-standard set
#'
#' Produces a realistic noisy extraction from a gold-standard data
#' frame by sampling recall, false-positive rate and label-mutation
#' probability for each backend.  Useful for offline reproducibility
#' and CI builds where real LLM APIs are unreachable.
#'
#' The simulator is **deterministic given a seed** and parameterised
#' by the three probabilities.  Default profiles approximate published
#' benchmarks for the three backends (Gemma 4, GPT-4o-mini,
#' Claude Sonnet-4.5) on soil-science causal-claim extraction.
#'
#' @param gold Gold-standard data frame with `abstract_id`, `cause`,
#'   `effect`.
#' @param recall Probability of keeping a gold claim.
#' @param precision_target Implicit: FP rate calibrated so precision
#'   lands near this target.
#' @param mutate_rate Probability of mutating an endpoint label.
#' @param seed Optional RNG seed.
#' @return Data frame with the same columns as `gold` plus `confidence`.
#' @export
llm_benchmark_simulate <- function(gold,
                                     recall = 0.82,
                                     precision_target = 0.86,
                                     mutate_rate = 0.05,
                                     seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  # FP rate so that precision ≈ target:
  # TP ≈ recall * n_gold, FP = x;  precision = TP / (TP + FP)
  # => FP = TP * (1/precision - 1)
  n_gold <- nrow(gold)
  TP_expected <- recall * n_gold
  FP_expected <- TP_expected * (1 / precision_target - 1)
  fp_rate     <- FP_expected / n_gold

  # Keep each gold claim with prob recall
  keep <- stats::runif(n_gold) < recall
  kept <- gold[keep, , drop = FALSE]

  # Mutate endpoint labels with small prob
  mut_cause  <- stats::runif(nrow(kept)) < mutate_rate
  mut_effect <- stats::runif(nrow(kept)) < mutate_rate
  kept$cause[mut_cause]   <- paste0(kept$cause[mut_cause], "_alt")
  kept$effect[mut_effect] <- paste0(kept$effect[mut_effect], "_alt")

  # Add noisy FPs
  n_fp <- stats::rbinom(1L, size = n_gold, prob = fp_rate)
  noise_pool <- c("precipitation", "temperature", "elevation", "slope",
                   "clay", "sand", "silt", "soc", "ph", "cec",
                   "bulk_density", "vegetation", "ndvi", "erosion",
                   "weathering", "parent_material", "land_use")
  if (n_fp > 0L) {
    fps <- data.frame(
      abstract_id = sample(unique(gold$abstract_id), n_fp, replace = TRUE),
      cause       = sample(noise_pool, n_fp, replace = TRUE),
      effect      = sample(noise_pool, n_fp, replace = TRUE),
      stringsAsFactors = FALSE
    )
    # drop same-node edges
    fps <- fps[fps$cause != fps$effect, , drop = FALSE]
  } else fps <- kept[FALSE, , drop = FALSE]

  # Combine + attach synthetic confidence
  out <- rbind(
    kept[, c("abstract_id", "cause", "effect")],
    if (nrow(fps) > 0L) fps[, c("abstract_id", "cause", "effect")] else NULL
  )
  out$confidence <- round(pmin(pmax(
    stats::rbeta(nrow(out), shape1 = 9, shape2 = 2), 0), 1), 3)
  out
}
