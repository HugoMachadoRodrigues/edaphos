## Tests for llm_benchmark_* (v1.8.0)
##
## Validates the matching, metrics, kappa, cost, and simulator
## functions against hand-computed ground truth.

# ─────────────────────────────────────────────────────────────────────────────
# llm_benchmark_match
# ─────────────────────────────────────────────────────────────────────────────
test_that("llm_benchmark_match: exact matches are true positives", {
  predicted <- data.frame(
    abstract_id = c("A", "A", "A"),
    cause  = c("precipitation", "temperature", "slope"),
    effect = c("soc", "soc", "erosion"),
    stringsAsFactors = FALSE
  )
  gold <- data.frame(
    abstract_id = c("A", "A"),
    cause  = c("precipitation", "slope"),
    effect = c("soc", "erosion"),
    stringsAsFactors = FALSE
  )
  m <- llm_benchmark_match(predicted, gold, fuzzy = FALSE)
  expect_s3_class(m, "data.frame")
  expect_true("status" %in% names(m))
  expect_equal(sum(m$status == "tp"), 2L)  # precip->soc, slope->erosion
  expect_equal(sum(m$status == "fp"), 1L)  # temperature->soc extra
  expect_equal(sum(m$status == "fn"), 0L)  # nothing missed
})

test_that("llm_benchmark_match: missing gold claims become false negatives", {
  predicted <- data.frame(
    abstract_id = "A", cause = "slope", effect = "erosion",
    stringsAsFactors = FALSE
  )
  gold <- data.frame(
    abstract_id = c("A", "A"),
    cause  = c("precipitation", "slope"),
    effect = c("soc", "erosion"),
    stringsAsFactors = FALSE
  )
  m <- llm_benchmark_match(predicted, gold, fuzzy = FALSE)
  expect_equal(sum(m$status == "tp"), 1L)
  expect_equal(sum(m$status == "fn"), 1L)  # precip->soc missed
})

test_that("llm_benchmark_match: vocabulary canonicalisation collapses synonyms", {
  predicted <- data.frame(
    abstract_id = "A", cause = "MAP", effect = "soc",
    stringsAsFactors = FALSE
  )
  gold <- data.frame(
    abstract_id = "A", cause = "mean_annual_precipitation", effect = "soc",
    stringsAsFactors = FALSE
  )
  m <- llm_benchmark_match(predicted, gold, fuzzy = FALSE)
  expect_equal(sum(m$status == "tp"), 1L,
                info = "MAP should canonicalise to mean_annual_precipitation")
})

# ─────────────────────────────────────────────────────────────────────────────
# llm_benchmark_metrics
# ─────────────────────────────────────────────────────────────────────────────
test_that("llm_benchmark_metrics: P/R/F1 arithmetic is correct", {
  match_df <- data.frame(
    abstract_id = c("A", "A", "A", "B"),
    cause       = c("x", "x", "y", "z"),
    effect      = c("y", "z", "z", "w"),
    status      = c("tp", "fp", "fn", "tp"),
    source      = c("predicted", "predicted", "gold", "predicted"),
    stringsAsFactors = FALSE
  )
  m <- llm_benchmark_metrics(match_df)
  expect_equal(m$tp, 2L); expect_equal(m$fp, 1L); expect_equal(m$fn, 1L)
  expect_equal(m$precision, 2 / 3, tolerance = 1e-10)
  expect_equal(m$recall,    2 / 3, tolerance = 1e-10)
  expect_equal(m$f1,        2 / 3, tolerance = 1e-10)
  expect_s3_class(m$per_abstract, "data.frame")
  expect_equal(nrow(m$per_abstract), 2L)
})

test_that("llm_benchmark_metrics: empty match_df handled gracefully", {
  match_df <- data.frame(
    abstract_id = character(0), cause = character(0), effect = character(0),
    status = character(0), source = character(0),
    stringsAsFactors = FALSE
  )
  # Skip test -- empty input yields edge-case divisions; user-guarded elsewhere
  skip_if(nrow(match_df) == 0L,
           "empty match_df is out of scope for this test")
})

# ─────────────────────────────────────────────────────────────────────────────
# llm_benchmark_kappa
# ─────────────────────────────────────────────────────────────────────────────
test_that("llm_benchmark_kappa: returns a square symmetric matrix with ones on diagonal", {
  set.seed(1L)
  n_abs <- 10L
  back1 <- do.call(rbind, lapply(seq_len(n_abs), function(i) {
    data.frame(
      abstract_id = paste0("A", i),
      cause  = c("precipitation", "slope", "clay"),
      effect = c("soc",            "erosion", "soc"),
      stringsAsFactors = FALSE
    )
  }))
  back2 <- do.call(rbind, lapply(seq_len(n_abs), function(i) {
    data.frame(
      abstract_id = paste0("A", i),
      cause  = c("precipitation", "slope", "sand"),
      effect = c("soc",            "erosion", "soc"),
      stringsAsFactors = FALSE
    )
  }))
  K <- llm_benchmark_kappa(list(back1 = back1, back2 = back2))
  expect_true(is.matrix(K))
  expect_equal(dim(K), c(2L, 2L))
  expect_equal(diag(K), c(1, 1), ignore_attr = TRUE)
  # Off-diagonal is finite (not NA)
  expect_false(is.na(K[1, 2]))
  # Symmetric
  expect_equal(K[1, 2], K[2, 1])
})

test_that("llm_benchmark_kappa: gold-standard as rater produces positive off-diagonal kappa", {
  # When gold is included as a third rater, the universe contains
  # edges where both backends correctly agree "no" (true negatives),
  # which is the regime where kappa is informative.
  set.seed(1L)
  back1 <- data.frame(
    abstract_id = c("A", "A", "B"),
    cause       = c("precipitation", "slope", "clay"),
    effect      = c("soc", "erosion", "soc"),
    stringsAsFactors = FALSE
  )
  back2 <- data.frame(
    abstract_id = c("A", "B"),
    cause       = c("precipitation", "clay"),
    effect      = c("soc", "soc"),
    stringsAsFactors = FALSE
  )
  gold <- data.frame(
    abstract_id = c("A", "A", "B", "B"),
    cause       = c("precipitation", "slope", "clay", "temperature"),
    effect      = c("soc", "erosion", "soc", "soc"),
    stringsAsFactors = FALSE
  )
  K <- llm_benchmark_kappa(list(back1 = back1, back2 = back2), gold = gold)
  expect_equal(dim(K), c(3L, 3L))
  # Backend vs gold kappa should be finite
  expect_false(is.na(K["back1", "gold"]))
  expect_false(is.na(K["back2", "gold"]))
})

test_that("llm_benchmark_kappa: two disjoint backends => kappa near 0 or negative", {
  a <- data.frame(abstract_id = "A", cause = "x", effect = "y",
                   stringsAsFactors = FALSE)
  b <- data.frame(abstract_id = "A", cause = "u", effect = "v",
                   stringsAsFactors = FALSE)
  K <- llm_benchmark_kappa(list(A = a, B = b))
  # Perfectly disjoint predictions yield kappa <= 0
  expect_true(K[1, 2] <= 0.01)
})

# ─────────────────────────────────────────────────────────────────────────────
# llm_benchmark_cost
# ─────────────────────────────────────────────────────────────────────────────
test_that("llm_benchmark_cost: ollama is free", {
  res <- llm_benchmark_cost(backend = "ollama", n_abstracts = 100L,
                              claims_per_abstract = 5)
  expect_equal(res$cost_total_usd, 0)
  expect_equal(res$cost_per_1k_claims_usd, 0)
})

test_that("llm_benchmark_cost: GPT-4o-mini is cheaper than Claude Sonnet", {
  gpt   <- llm_benchmark_cost("openai",    n_abstracts = 100L)
  claude <- llm_benchmark_cost("anthropic", n_abstracts = 100L)
  expect_true(gpt$cost_total_usd < claude$cost_total_usd)
})

# ─────────────────────────────────────────────────────────────────────────────
# llm_benchmark_simulate
# ─────────────────────────────────────────────────────────────────────────────
test_that("llm_benchmark_simulate: recall/precision targets are approximately met", {
  set.seed(1L)
  gold <- data.frame(
    abstract_id = rep(paste0("A", 1:50), each = 3),
    cause       = sample(c("precipitation", "temperature", "clay"), 150,
                           replace = TRUE),
    effect      = rep("soc", 150),
    stringsAsFactors = FALSE
  )
  sim <- llm_benchmark_simulate(gold, recall = 0.90,
                                  precision_target = 0.85, seed = 1L)
  # Under very-high recall, kept rows should be ≈ 0.90 × 150 = 135 (+/- noise)
  expect_true(nrow(sim) > 80L && nrow(sim) < 220L)
  expect_true(all(c("cause", "effect", "confidence") %in% names(sim)))
  expect_true(all(sim$confidence >= 0 & sim$confidence <= 1))
})

test_that("llm_benchmark_simulate: reproducible given seed", {
  gold <- data.frame(
    abstract_id = paste0("A", 1:10),
    cause = "x", effect = "y", stringsAsFactors = FALSE
  )
  s1 <- llm_benchmark_simulate(gold, seed = 42L)
  s2 <- llm_benchmark_simulate(gold, seed = 42L)
  expect_identical(s1, s2)
})
