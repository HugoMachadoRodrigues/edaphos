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
#'   edge as TP when the Levenshtein distances of its two endpoints
#'   *sum* to no more than `fuzzy_threshold`. If `FALSE`, require
#'   exact match on canonicalised labels. Fuzzy matching needs the
#'   suggested package \pkg{stringdist}; without it `fuzzy = TRUE`
#'   silently degrades to exact matching.
#' @param fuzzy_threshold Integer; maximum Levenshtein distance
#'   summed over the cause and the effect. Default `2`.
#'
#' @return A data frame with columns `abstract_id`, `cause`, `effect`,
#'   `status` (one of `"tp"`, `"fp"`, `"fn"`), and `source` (either
#'   `"predicted"` or `"gold"`).
#' @examples
#' # The package ships a 30-abstract Cerrado gold standard.  Flatten
#' # its nested `claims` arrays into the one-row-per-edge frame the
#' # matcher expects.
#' gold_path <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
#'                          package = "edaphos")
#' if (nzchar(gold_path)) {
#'   recs <- lapply(readLines(gold_path), jsonlite::fromJSON)
#'   gold <- do.call(rbind, lapply(recs, function(r) data.frame(
#'     abstract_id = r$abstract_id, cause = r$claims$cause,
#'     effect      = r$claims$effect, stringsAsFactors = FALSE)))
#'   print(c(abstracts = length(recs), claims = nrow(gold)))
#'
#'   # CER_01 is a rainfall / temperature / SOC abstract with five gold
#'   # claims.  Below is an extraction a pedologist would call four out
#'   # of four correct -- only the surface strings differ from the
#'   # annotator's.  Three score TP, one scores FP.
#'   cer1 <- gold[gold$abstract_id == "CER_01", ]
#'   pred <- data.frame(
#'     abstract_id = "CER_01",
#'     cause  = c("Rainfall", "MAP",        "mean annual temperature",
#'                "tree cover"),
#'     effect = c("TOC",      "tree cover", "Corg", "organic carbon"),
#'     stringsAsFactors = FALSE)
#'   print(llm_benchmark_match(pred, cer1))
#'
#'   # P = 0.75, R = 0.60, and BOTH losses are the matching rule rather
#'   # than the model:
#'   #  * "Rainfall" canonicalises to `precipitation`, the annotator
#'   #    wrote `mean_annual_precipitation`, and the normaliser keeps
#'   #    those deliberately apart -- so the same claim is scored as a
#'   #    false positive AND leaves the gold edge as a false negative.
#'   #  * gold lists `mean_annual_temperature -> soc` TWICE for CER_01,
#'   #    and matching is one-to-one, so one predicted edge clears only
#'   #    one of the pair.
#'   print(round(unlist(llm_benchmark_metrics(
#'     llm_benchmark_match(pred, cer1))[
#'       c("tp", "fp", "fn", "precision", "recall")]), 3))
#'
#'   # That duplicate caps the whole benchmark.  Feed gold back as its
#'   # own prediction, deduplicated the way any extractor would emit it,
#'   # and recall stops at 71/72 -- no model can score 1.
#'   ded <- gold[!duplicated(paste(gold$abstract_id, gold$cause,
#'                                 gold$effect)), ]
#'   print(round(unlist(llm_benchmark_metrics(
#'     llm_benchmark_match(ded, gold))[c("tp", "fn", "recall")]), 4))
#'
#'   # Trap: `fuzzy = TRUE` is the default, but it changes nothing here.
#'   # The threshold is the SUM over both endpoints, and no
#'   # predicted/gold pair in this vocabulary sits within 2 edits
#'   # without already matching exactly.  Report the threshold you used
#'   # next to F1 -- see llm_benchmark_simulate() for what raising it
#'   # does.
#'   print(identical(llm_benchmark_match(ded, gold, fuzzy = TRUE),
#'                   llm_benchmark_match(ded, gold, fuzzy = FALSE)))
#' }
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
#' @examples
#' res_path <- system.file("extdata", "llm_benchmark_results.rds",
#'                         package = "edaphos")
#' if (nzchar(res_path)) {
#'   B <- readRDS(res_path)
#'
#'   # Read this before quoting any number below: the shipped bundle is
#'   # simulator output, not measured API calls.
#'   print(B$mode)
#'
#'   m <- llm_benchmark_metrics(
#'     llm_benchmark_match(B$backend_claims[["Gemma 4"]], B$gold_df))
#'   print(round(unlist(
#'     m[c("tp", "fp", "fn", "precision", "recall", "f1")]), 4))
#'
#'   # Every row of the match table lands in exactly one cell, so the
#'   # three counts reconstruct its length -- a cheap audit that no
#'   # abstract was dropped by the join.
#'   mt <- llm_benchmark_match(B$backend_claims[["Gemma 4"]], B$gold_df)
#'   print(c(counts = m$tp + m$fp + m$fn, rows = nrow(mt)))
#'
#'   # Trap: `per_abstract` returns NA, not 0, whenever a denominator is
#'   # empty.  Precision is NA for the 2 abstracts where this backend
#'   # predicted nothing at all, and F1 is NA for all 5 where it got
#'   # nothing right (precision + recall == 0).
#'   pa <- m$per_abstract
#'   print(c(abstracts = nrow(pa), na_precision = sum(is.na(pa$precision)),
#'           na_f1 = sum(is.na(pa$f1))))
#'
#'   # So the obvious macro average deletes exactly the abstracts the
#'   # backend failed on and reports 0.794; scoring those failures as 0
#'   # gives 0.662; the pooled (micro) F1 is 0.706.  Quote the micro
#'   # figure -- `mean(f1, na.rm = TRUE)` is the flattering one.
#'   print(round(c(macro_narm = mean(pa$f1, na.rm = TRUE),
#'                 macro_zero = mean(ifelse(is.na(pa$f1), 0, pa$f1)),
#'                 micro      = m$f1), 4))
#'
#'   # And read the spread next to the headline: this backend is not
#'   # uniformly mediocre, it is bimodal -- 10 of 30 abstracts perfect,
#'   # 5 a complete miss.
#'   print(c(perfect = sum(pa$f1 == 1, na.rm = TRUE),
#'           total_miss = sum(is.na(pa$f1))))
#' }
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
#' @examples
#' res_path <- system.file("extdata", "llm_benchmark_results.rds",
#'                         package = "edaphos")
#' if (nzchar(res_path)) {
#'   B <- readRDS(res_path)
#'   print(round(llm_benchmark_kappa(B$backend_claims, gold = B$gold_df), 3))
#'
#'   # Read the `gold` column first: 0.342 / 0.256 / 0.567 against the
#'   # pedologist -- "fair" to "moderate", nowhere near the 0.80 you
#'   # would demand of a second human coder before trusting a KG.
#'   #
#'   # Then read the off-diagonals: two backends that each agree with
#'   # gold can still land at -0.081 with EACH OTHER.  Agreement with a
#'   # reference does not transfer between raters, because they miss
#'   # and invent different edges.
#'
#'   # Trap: the rating universe is the union of edges over whatever
#'   # raters you hand in, so kappa is a property of the CALL, not of
#'   # the pair.  Adding one sloppy fourth rater contributes 169 new
#'   # edges that Gemma and GPT both (correctly) decline, and their
#'   # kappa jumps from -0.081 to 0.385 without either changing a
#'   # single extraction.
#'   set.seed(1)
#'   junk <- data.frame(
#'     abstract_id = sample(unique(B$gold_df$abstract_id), 200,
#'                          replace = TRUE),
#'     cause  = sample(c("clay", "sand", "silt", "ph", "cec"), 200,
#'                     replace = TRUE),
#'     effect = sample(c("erosion", "ndvi", "slope", "land_use"), 200,
#'                     replace = TRUE), stringsAsFactors = FALSE)
#'   print(round(llm_benchmark_kappa(c(B$backend_claims, list(junk = junk)),
#'                                   gold = B$gold_df)[1:2, 1:2], 3))
#'
#'   # Honest caveat on the first matrix: these three "backends" were
#'   # drawn from the gold set by llm_benchmark_simulate() with an
#'   # independent keep-mask per backend, so near-zero pairwise kappa is
#'   # arithmetic from the generator, not evidence about Gemma, GPT or
#'   # Claude.
#'   print(B$mode)
#' }
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
#' @examples
#' # List prices, not invoices: published per-token rates times assumed
#' # token counts (700 in / 110 out).  Nothing is measured.
#' str(llm_benchmark_cost("anthropic", model = "claude-sonnet-4-5",
#'                        n_abstracts = 30L, claims_per_abstract = 2.4))
#'
#' # Scaling a Cerrado systematic review to 10 000 abstracts.  The
#' # local model reads $0 because list price is all this function
#' # knows -- it is blind to the GPU, and to the 15.9 s/abstract that
#' # the shipped latency summary records for Gemma 4 against 3.0 s for
#' # GPT-4o-mini.
#' round(c(
#'   ollama    = llm_benchmark_cost("ollama",
#'                                  n_abstracts = 10000L)$cost_total_usd,
#'   openai    = llm_benchmark_cost("openai",
#'                                  n_abstracts = 10000L)$cost_total_usd,
#'   anthropic = llm_benchmark_cost("anthropic",
#'                                  n_abstracts = 10000L)$cost_total_usd), 2)
#'
#' # Trap 1: `n_abstracts` cancels out of `cost_per_1k_claims_usd`.
#' # That headline is a function of the token assumptions and
#' # `claims_per_abstract` alone and says nothing about your corpus.
#' c(n30 = llm_benchmark_cost("openai", n_abstracts = 30L,
#'          claims_per_abstract = 2.4)$cost_per_1k_claims_usd,
#'   n10k = llm_benchmark_cost("openai", n_abstracts = 10000L,
#'           claims_per_abstract = 2.4)$cost_per_1k_claims_usd)
#'
#' # Trap 2: an unrecognised backend returns NA prices rather than
#' # erroring, so a typo quietly turns a paid model into a free one.
#' llm_benchmark_cost("gemini", n_abstracts = 30L)$cost_total_usd
#'
#' # Trap 3: the denominator is claims EXTRACTED, not claims CORRECT,
#' # so over-extraction buys a cheaper headline.  Re-normalise on the
#' # true positives from the shipped benchmark and both backends get
#' # dearer -- GPT by 1.43x, Claude by 1.22x -- and the advertised 22x
#' # price gap between them narrows to 19x.
#' res_path <- system.file("extdata", "llm_benchmark_results.rds",
#'                         package = "edaphos")
#' if (nzchar(res_path)) {
#'   mt <- readRDS(res_path)$metrics_table   # rows: Gemma, GPT, Claude
#'   per1k <- function(bk, claims) llm_benchmark_cost(
#'     bk, n_abstracts = 30L,
#'     claims_per_abstract = claims / 30)$cost_per_1k_claims_usd
#'   print(round(rbind(
#'     openai    = c(all = per1k("openai",    mt$n_claims[2]),
#'                   tp  = per1k("openai",    mt$tp[2])),
#'     anthropic = c(all = per1k("anthropic", mt$n_claims[3]),
#'                   tp  = per1k("anthropic", mt$tp[3]))), 4))
#' }
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
#' @param recall Probability of keeping a gold claim. This is the
#'   sampling probability, not the recall you will measure: mutation
#'   happens after sampling, so the realised recall is lower.
#' @param precision_target Used only to derive the false-positive
#'   rate, assuming no mutation. With `mutate_rate > 0` the realised
#'   precision falls below this target, because every mutated endpoint
#'   converts a true positive into a false positive.
#' @param mutate_rate Probability of mutating an endpoint label.
#' @param seed Optional RNG seed. Pass one: without it the output,
#'   including its row count, differs between calls.
#' @return Data frame with columns `abstract_id`, `cause`, `effect`
#'   and `confidence`. Any other column of `gold` (`polarity`, for
#'   instance) is dropped.
#' @examples
#' res_path <- system.file("extdata", "llm_benchmark_results.rds",
#'                         package = "edaphos")
#' if (nzchar(res_path)) {
#'   B <- readRDS(res_path)
#'
#'   # Always pass `seed`.  Without one even the row count moves.
#'   print(identical(llm_benchmark_simulate(B$gold_df, seed = 42L),
#'                   llm_benchmark_simulate(B$gold_df, seed = 42L)))
#'
#'   # The shipped benchmark bundle IS this function, not an API call:
#'   # replaying the Gemma 4 profile from data-raw/llm_benchmark_run.R
#'   # reproduces its row of `metrics_table` to the digit.
#'   sim <- llm_benchmark_simulate(B$gold_df, recall = 0.80,
#'                                 precision_target = 0.85,
#'                                 mutate_rate = 0.06, seed = 101L)
#'   m <- llm_benchmark_metrics(llm_benchmark_match(sim, B$gold_df))
#'   print(rbind(
#'     replayed = round(unlist(m[c("precision", "recall", "f1")]), 4),
#'     shipped  = round(unlist(
#'       B$metrics_table[1, c("precision", "recall", "f1")]), 4)))
#'
#'   # `recall` and `precision_target` are knobs on the sampler, not
#'   # properties of the output: 0.80 and 0.85 in give 0.667 and 0.750
#'   # out.  `mutate_rate` is why -- it corrupts endpoint labels AFTER
#'   # sampling, so each mutation costs one TP and adds one FP, pushing
#'   # both metrics down at once.
#'   for (mr in c(0, 0.05, 0.20)) {
#'     s <- llm_benchmark_simulate(B$gold_df, recall = 0.82,
#'                                 precision_target = 0.90,
#'                                 mutate_rate = mr, seed = 7L)
#'     mm <- llm_benchmark_metrics(llm_benchmark_match(s, B$gold_df))
#'     cat(sprintf("mutate_rate %.2f -> precision %.4f (target 0.90)\n",
#'                 mr, mm$precision))
#'   }
#'
#'   # The mutation writes "<label>_alt", four edits away, so the
#'   # default fuzzy_threshold of 2 recovers none of it and a threshold
#'   # of 4 recovers all of it: F1 0.706 -> 0.824.  That single line of
#'   # the scoring rule moves F1 further (+0.118) than the whole spread
#'   # between the three simulated backends (0.116).  Fix the rule
#'   # before you compare models.
#'   if (requireNamespace("stringdist", quietly = TRUE)) {
#'     print(round(vapply(c(2L, 4L), function(th)
#'       llm_benchmark_metrics(llm_benchmark_match(
#'         sim, B$gold_df, fuzzy_threshold = th))$f1, numeric(1)), 4))
#'   }
#'
#'   # `polarity` does not survive, although it is right there in the
#'   # gold frame -- so a downstream KG built from simulated claims
#'   # cannot be scored on the sign of the effect, only on its
#'   # existence.
#'   print(names(sim))
#' }
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
