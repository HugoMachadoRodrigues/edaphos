## data-raw/llm_benchmark_run.R  (v1.8.0)
##
## Runs the LLM-extraction benchmark over the 30 gold-standard
## Cerrado abstracts, across three backends (Gemma 4, GPT-4o-mini,
## Claude Sonnet-4.5), and computes precision / recall / F1,
## pairwise Cohen's kappa, cost per 1 000 claims and latency.
##
## ============================================================
## TWO MODES
## ============================================================
##
##   Sys.setenv(EDAPHOS_USE_REAL_LLM = "1")   # (optional)
##
## If EDAPHOS_USE_REAL_LLM=1, the script calls the live APIs; the
## user must have Ollama + gemma4:latest running AND environment
## vars OPENAI_API_KEY / ANTHROPIC_API_KEY set.  Expect ~20-40
## minutes of runtime and a few cents of API cost.
##
## If EDAPHOS_USE_REAL_LLM is unset (default), the script uses the
## deterministic simulator llm_benchmark_simulate() calibrated to
## published per-backend profiles.  This mode is used for CI builds,
## vignette construction, and users without API access.
##
## Output: inst/extdata/llm_benchmark_results.rds

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))
suppressMessages(library(jsonlite))
set.seed(20260425L)

OUT_PATH <- file.path("inst", "extdata", "llm_benchmark_results.rds")
USE_REAL <- identical(Sys.getenv("EDAPHOS_USE_REAL_LLM", ""), "1")

message("=== [0/6] Loading gold-standard ===")
gold_path <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
                          package = "edaphos")
if (!nzchar(gold_path) || !file.exists(gold_path)) {
  gold_path <- "inst/extdata/cerrado_gold_standard_v1.jsonl"
}
stopifnot(file.exists(gold_path))

# Parse JSONL: one record per line
gold_records <- lapply(readLines(gold_path), fromJSON, simplifyVector = TRUE)

# Flatten the gold claims to a single data frame
gold_df <- do.call(rbind, lapply(gold_records, function(r) {
  cl <- r$claims
  if (is.null(cl) || length(cl) == 0L) return(NULL)
  if (is.data.frame(cl)) {
    data.frame(
      abstract_id = r$abstract_id,
      cause       = cl$cause,
      effect      = cl$effect,
      polarity    = cl$polarity,
      confidence  = as.numeric(cl$confidence),
      stringsAsFactors = FALSE
    )
  } else NULL
}))

message(sprintf("  Abstracts: %d  |  Gold claims: %d",
                length(gold_records), nrow(gold_df)))
message(sprintf("  Mode: %s",
                if (USE_REAL) "REAL API calls" else "SIMULATED"))

# ─────────────────────────────────────────────────────────────────────────────
# Helper: run one backend (real or simulated)
# ─────────────────────────────────────────────────────────────────────────────
run_backend <- function(name, abstracts, gold_df,
                         real_fn = NULL, sim_args = list()) {
  if (USE_REAL && is.function(real_fn)) {
    t0 <- Sys.time()
    rows <- list()
    for (r in abstracts) {
      t_call <- Sys.time()
      extracted <- tryCatch(
        real_fn(r$abstract_text),
        error = function(e) {
          message(sprintf("  [warn] %s failed on %s: %s",
                           name, r$abstract_id, conditionMessage(e)))
          data.frame(cause = character(), effect = character(),
                      stringsAsFactors = FALSE)
        }
      )
      if (nrow(extracted) > 0L) {
        extracted$abstract_id <- r$abstract_id
        extracted$latency_sec <- as.numeric(Sys.time() - t_call, units = "secs")
        rows[[r$abstract_id]] <- extracted
      }
    }
    claims <- do.call(rbind, rows)
    list(claims = claims,
         latency_total_sec = as.numeric(Sys.time() - t0, units = "secs"))
  } else {
    # Deterministic simulator.  Split latency args out of sim_args
    # before dispatching to llm_benchmark_simulate().
    t0 <- Sys.time()
    lat_mean <- sim_args$latency_mean %||% 5
    lat_sd   <- sim_args$latency_sd   %||% 1.5
    sim_core_args <- sim_args[setdiff(names(sim_args),
                                         c("latency_mean", "latency_sd"))]
    sim <- do.call(llm_benchmark_simulate,
                   c(list(gold = gold_df), sim_core_args))
    sim$latency_sec <- round(pmax(
      stats::rnorm(nrow(sim), mean = lat_mean, sd = lat_sd), 0.2), 2)
    list(claims = sim,
         latency_total_sec = as.numeric(Sys.time() - t0, units = "secs"))
  }
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ─────────────────────────────────────────────────────────────────────────────
# Run the three backends
# ─────────────────────────────────────────────────────────────────────────────
message("=== [1/6] Running backends ===")

# 1. Gemma 4 (local Ollama) — highest recall, decent precision, slow
message("  [1/3] Gemma 4 ...")
gemma_res <- run_backend(
  name      = "gemma4:latest",
  abstracts = gold_records,
  gold_df   = gold_df,
  real_fn   = if (USE_REAL) function(txt)
    causal_llm_extract(txt, backend = "ollama",
                        model = "gemma4:latest") else NULL,
  sim_args  = list(recall = 0.80, precision_target = 0.85,
                    mutate_rate = 0.06, seed = 101L,
                    latency_mean = 15.2, latency_sd = 4.1)
)

# 2. GPT-4o-mini (OpenAI) — high recall, medium precision, fast
message("  [2/3] GPT-4o-mini ...")
gpt_res <- run_backend(
  name      = "gpt-4o-mini",
  abstracts = gold_records,
  gold_df   = gold_df,
  real_fn   = if (USE_REAL) function(txt)
    causal_llm_extract(txt, backend = "openai",
                        model = "gpt-4o-mini") else NULL,
  sim_args  = list(recall = 0.88, precision_target = 0.80,
                    mutate_rate = 0.08, seed = 102L,
                    latency_mean = 3.1, latency_sd = 0.8)
)

# 3. Claude Sonnet-4.5 (Anthropic) — high precision, medium recall, slow
message("  [3/3] Claude Sonnet-4.5 ...")
claude_res <- run_backend(
  name      = "claude-sonnet-4.5",
  abstracts = gold_records,
  gold_df   = gold_df,
  real_fn   = if (USE_REAL) function(txt)
    causal_llm_extract(txt, backend = "anthropic",
                        model = "claude-sonnet-4-5") else NULL,
  sim_args  = list(recall = 0.84, precision_target = 0.90,
                    mutate_rate = 0.04, seed = 103L,
                    latency_mean = 5.7, latency_sd = 1.4)
)

backend_claims <- list(
  "Gemma 4"      = gemma_res$claims,
  "GPT-4o-mini"  = gpt_res$claims,
  "Claude Sonnet-4.5" = claude_res$claims
)
backend_latency_total <- list(
  "Gemma 4"      = gemma_res$latency_total_sec,
  "GPT-4o-mini"  = gpt_res$latency_total_sec,
  "Claude Sonnet-4.5" = claude_res$latency_total_sec
)

# ─────────────────────────────────────────────────────────────────────────────
# [2/6] Per-backend P/R/F1
# ─────────────────────────────────────────────────────────────────────────────
message("=== [2/6] Computing P/R/F1 per backend ===")

metrics_table <- data.frame()
per_backend_matches <- list()

for (b in names(backend_claims)) {
  match_df <- llm_benchmark_match(
    predicted = backend_claims[[b]],
    gold      = gold_df,
    fuzzy     = TRUE, fuzzy_threshold = 2L
  )
  per_backend_matches[[b]] <- match_df
  m <- llm_benchmark_metrics(match_df)
  metrics_table <- rbind(
    metrics_table,
    data.frame(backend  = b,
                n_claims = nrow(backend_claims[[b]]),
                tp = m$tp, fp = m$fp, fn = m$fn,
                precision = m$precision,
                recall    = m$recall,
                f1        = m$f1,
                stringsAsFactors = FALSE)
  )
}

message("Metrics table:")
print(metrics_table)

# ─────────────────────────────────────────────────────────────────────────────
# [3/6] Cohen's kappa pairwise + with gold
# ─────────────────────────────────────────────────────────────────────────────
message("=== [3/6] Cohen's kappa ===")

kappa_mat <- llm_benchmark_kappa(backend_claims, gold = gold_df)
message("Kappa matrix:")
print(round(kappa_mat, 3))

# ─────────────────────────────────────────────────────────────────────────────
# [4/6] Cost estimates
# ─────────────────────────────────────────────────────────────────────────────
message("=== [4/6] Cost estimates ===")

N_ABS <- length(gold_records)
cpa <- function(b) nrow(backend_claims[[b]]) / N_ABS
cost_table <- bind_rows(
  as.data.frame(llm_benchmark_cost("ollama",    model = "gemma4:latest",
                                    n_abstracts = N_ABS,
                                    claims_per_abstract = cpa("Gemma 4"))),
  as.data.frame(llm_benchmark_cost("openai",    model = "gpt-4o-mini",
                                    n_abstracts = N_ABS,
                                    claims_per_abstract = cpa("GPT-4o-mini"))),
  as.data.frame(llm_benchmark_cost("anthropic", model = "claude-sonnet-4-5",
                                    n_abstracts = N_ABS,
                                    claims_per_abstract = cpa("Claude Sonnet-4.5")))
)

# Fix backend column + add total cost for a 10k-abstract corpus scaling
cost_table$cost_10k_abstracts_usd <- with(cost_table,
  (cost_total_usd / n_abstracts) * 10000L
)
print(cost_table)

# ─────────────────────────────────────────────────────────────────────────────
# [5/6] Latency distribution
# ─────────────────────────────────────────────────────────────────────────────
message("=== [5/6] Latency summary ===")

latency_df <- bind_rows(lapply(names(backend_claims), function(b) {
  d <- backend_claims[[b]]
  data.frame(
    backend     = b,
    latency_sec = if ("latency_sec" %in% names(d)) d$latency_sec
                   else rnorm(nrow(d), 5, 2),
    stringsAsFactors = FALSE
  )
}))

latency_summary <- latency_df |>
  group_by(backend) |>
  summarise(
    n         = dplyr::n(),
    mean_sec  = mean(latency_sec, na.rm = TRUE),
    median_sec = median(latency_sec, na.rm = TRUE),
    p90_sec   = quantile(latency_sec, 0.9, na.rm = TRUE),
    .groups   = "drop"
  )
print(latency_summary)

# ─────────────────────────────────────────────────────────────────────────────
# [6/6] Bundle + save
# ─────────────────────────────────────────────────────────────────────────────
message("=== [6/6] Saving bundle ===")

R_out <- list(
  version             = packageVersion("edaphos"),
  date_computed       = Sys.time(),
  mode                = if (USE_REAL) "real_api" else "simulated",
  n_abstracts         = length(gold_records),
  n_gold_claims       = nrow(gold_df),

  # Raw data
  gold_records        = gold_records,
  gold_df             = gold_df,
  backend_claims      = backend_claims,
  per_backend_matches = per_backend_matches,
  latency_df          = latency_df,

  # Summary tables
  metrics_table       = metrics_table,
  kappa_matrix        = kappa_mat,
  cost_table          = cost_table,
  latency_summary     = latency_summary
)

saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
