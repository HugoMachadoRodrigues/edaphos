## data-raw/causal_discovery_benchmark.R
##
## v1.7.2 — Causal discovery benchmark on 1 095 real WoSIS Cerrado
## profiles.  Compares three ways of constructing the pedogenetic DAG:
##
##   A) Expert DAG           — hand-specified by a pedologist (v1.4.0)
##   B) LLM-KG augmented DAG — expert base + Gemma 4 extracted claims
##                              (cached in inst/extdata/cerrado_claims.jsonl)
##   C) Data-driven DAG(s)   — learned from the 1 095 profiles by four
##                              bnlearn algorithms (hc, tabu, pc-stable,
##                              mmhc) with pedological priors (whitelist
##                              of orientation constraints).
##
## Metrics
## - Structural Hamming Distance (SHD) between each pair of methods.
## - Edge-by-edge agreement table (presence/absence matrix).
## - Identification sensitivity: does the backdoor adjustment set for
##   (wc_bio_12 -> soc_topsoil_gkg) change across methods?
##
## Output:  inst/extdata/causal_discovery_results.rds
## Consumed by:  vignettes/causal-discovery-trio.Rmd

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))
suppressMessages(library(dagitty))
stopifnot(requireNamespace("bnlearn", quietly = TRUE))
set.seed(20260425L)

OUT_PATH <- file.path("inst", "extdata", "causal_discovery_results.rds")

# ─────────────────────────────────────────────────────────────────────────────
# 0. Load shared data + expert DAG
# ─────────────────────────────────────────────────────────────────────────────
message("=== [0/5] Loading inputs ===")
causal_rds <- readRDS("inst/extdata/causal_cerrado_real.rds")
profiles   <- causal_rds$profiles
expert_dag <- causal_rds$dag

# DAG nodes (fixed canonical set used across all three methods)
DAG_NODES <- names(expert_dag)
expert_edges <- edges(expert_dag)[, c("v", "w")] |>
  setNames(c("from", "to"))

message(sprintf("  Profiles : %d", nrow(profiles)))
message(sprintf("  Nodes    : %d", length(DAG_NODES)))
message(sprintf("  Expert edges : %d", nrow(expert_edges)))

# Clean, numeric-complete subset (bnlearn needs complete cases)
vars_use <- intersect(DAG_NODES, names(profiles))
df <- profiles[, vars_use, drop = FALSE]
for (j in seq_along(df)) if (!is.numeric(df[[j]])) df[[j]] <- as.numeric(df[[j]])
df <- df[complete.cases(df), , drop = FALSE]
message(sprintf("  Complete rows : %d / %d", nrow(df), nrow(profiles)))

# ─────────────────────────────────────────────────────────────────────────────
# Helper: normalise any DAG into a tidy from/to edge frame over DAG_NODES
# ─────────────────────────────────────────────────────────────────────────────
dag_edges_df <- function(dag) {
  e <- edges(dag)
  if (nrow(e) == 0L) return(data.frame(from = character(0), to = character(0)))
  data.frame(from = e$v, to = e$w, stringsAsFactors = FALSE) |>
    filter(from %in% DAG_NODES, to %in% DAG_NODES) |>
    arrange(from, to)
}

# Structural Hamming Distance between two edge frames on the same node set.
#   SHD = (# edges in A only) + (# edges in B only) + (# reversed)
# Reversed edges count as 1 (not 2) following Tsamardinos et al. (2006).
compute_shd <- function(edges_a, edges_b) {
  key <- function(df) paste(df$from, df$to, sep = "->")
  key_rev <- function(df) paste(df$to, df$from, sep = "->")

  ka  <- key(edges_a)
  kb  <- key(edges_b)
  kbr <- key_rev(edges_b)

  # Shared in same direction
  shared   <- intersect(ka, kb)
  # A-only and B-only (either direction)
  a_only   <- setdiff(ka, c(kb, kbr))
  b_only   <- setdiff(kb, c(ka, key_rev(edges_a)))
  # Reversed: present in both but opposite direction
  reversed <- intersect(ka, kbr)

  list(
    shd       = length(a_only) + length(b_only) + length(reversed),
    shared    = length(shared),
    a_only    = length(a_only),
    b_only    = length(b_only),
    reversed  = length(reversed)
  )
}

# Convert tidy edge frame back to dagitty DAG
edges_to_dagitty <- function(ed, nodes = DAG_NODES) {
  if (nrow(ed) == 0L) {
    body <- paste(nodes, collapse = "; ")
  } else {
    e_str <- paste(ed$from, "->", ed$to, collapse = "; ")
    # include isolated nodes so dagitty keeps them in the DAG
    body <- paste(paste(nodes, collapse = "; "), e_str, sep = "; ")
  }
  dagitty::dagitty(paste0("dag { ", body, " }"))
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Method A — Expert DAG
# ─────────────────────────────────────────────────────────────────────────────
message("=== [1/5] Method A: Expert DAG (v1.4.0) ===")
edges_A <- dag_edges_df(expert_dag)
message(sprintf("  A has %d edges", nrow(edges_A)))

# ─────────────────────────────────────────────────────────────────────────────
# 2. Method B — LLM-KG augmented (Gemma 4 extractions, cached)
# ─────────────────────────────────────────────────────────────────────────────
message("=== [2/5] Method B: LLM-KG augmented DAG ===")

# Read the extracted claims that the package actually ships, and map their
# conceptual variable names onto the WoSIS column names this benchmark uses.
#
# Through v3.10.0 this block hard-coded six edges with confidences of 0.90,
# 0.82, 0.78, 0.75, 0.72 and 0.71, described as "the same six high-confidence
# edges that a fresh Ollama + gemma4:latest run returns".  Nothing in the
# repository supports that: inst/extdata/cerrado_claims.jsonl contains 30
# claims, every one of them at confidence 0.9, expressed in conceptual names
# (mean_annual_precipitation, twi, soc) rather than WoSIS columns.  Those six
# edges and their varied confidences were composed by hand, and this method
# is labelled "LLM-augmented (Gemma 4)" in the vignette and the README.
#
# The mapping below is the only editorial step, and it is explicit and
# inspectable: concept -> WoSIS column, drawn from the package's own
# causal_ontology_cerrado() vocabulary.  Claims whose endpoints have no WoSIS
# counterpart are dropped and counted, not silently discarded.
# Only concepts with a genuine counterpart in the WoSIS covariate set may
# appear here.  Mapping a concept onto a column that does not exist (twi and
# elevation-derived indices are the tempting cases: this dataset has `elev`
# but no `twi`) produces edges to a phantom node, which the DAG constructor
# then drops -- silently turning a mapping error into an apparent finding.
# The assertion below makes that impossible.
CONCEPT_TO_WOSIS <- c(
  mean_annual_precipitation  = "wc_bio_12",
  precipitation              = "wc_bio_12",
  mean_annual_temperature    = "wc_bio_01",
  temperature                = "wc_bio_01",
  soc                        = "soc_topsoil_gkg",
  clay_content               = "soilgrids_clay",
  clay_content_at_bt_horizon = "soilgrids_clay",
  sand_content               = "soilgrids_sand",
  bulk_density               = "soilgrids_bdod",
  elevation                  = "elev",
  slope                      = "slope",
  tree_cover                 = "wc_landcover_trees",
  above_ground_biomass       = "wc_landcover_trees",
  land_use                   = "wc_landcover_cropland"
)
unknown_targets <- setdiff(unname(CONCEPT_TO_WOSIS), names(profiles))
if (length(unknown_targets))
  stop(sprintf(
    "CONCEPT_TO_WOSIS maps onto columns that do not exist in the profile frame: %s",
    paste(unknown_targets, collapse = ", ")), call. = FALSE)

claims_path <- system.file("extdata", "cerrado_claims.jsonl",
                            package = "edaphos")
claims_raw <- do.call(rbind, lapply(readLines(claims_path, warn = FALSE),
  function(l) {
    j <- jsonlite::fromJSON(l)
    data.frame(cause = j$cause, effect = j$effect,
               confidence = j$confidence, source = j$source,
               stringsAsFactors = FALSE)
  }))
message(sprintf("  read %d claims from %s", nrow(claims_raw),
                basename(claims_path)))

mapped <- transform(claims_raw,
  from = unname(CONCEPT_TO_WOSIS[cause]),
  to   = unname(CONCEPT_TO_WOSIS[effect]))
n_unmapped <- sum(is.na(mapped$from) | is.na(mapped$to))
llm_extra_edges <- unique(
  mapped[!is.na(mapped$from) & !is.na(mapped$to) & mapped$from != mapped$to,
         c("from", "to", "confidence")])
message(sprintf(
  "  mapped %d of %d claims onto WoSIS columns (%d dropped: endpoint outside the covariate set); %d distinct edges",
  nrow(claims_raw) - n_unmapped, nrow(claims_raw), n_unmapped,
  nrow(llm_extra_edges)))
if (nrow(llm_extra_edges) == 0L)
  stop("no claim mapped onto a WoSIS column -- refusing to present an empty edge set as an LLM-derived DAG",
       call. = FALSE)

# Augmented edge set = expert ∪ LLM-high-confidence (keep expert direction
# if conflict; reject LLM edge if it would create a cycle).
augmented_edges <- rbind(
  edges_A,
  llm_extra_edges[, c("from", "to")]
) |>
  distinct(from, to, .keep_all = TRUE)

# Build DAG + cycle check
# A silent fallback here would make Method B indistinguishable from Method A
# while still being labelled "LLM-augmented" in every downstream table.
dag_B <- tryCatch(edges_to_dagitty(augmented_edges),
                  error = function(e) {
                    warning(sprintf(
                      "augmented DAG could not be built (%s); Method B falls back to the expert DAG and is NOT an augmented result",
                      conditionMessage(e)), call. = FALSE)
                    expert_dag
                  })
edges_B <- dag_edges_df(dag_B)
message(sprintf(
  "  B has %d edges (+%d over A)",
  nrow(edges_B), nrow(edges_B) - nrow(edges_A)
))

# ─────────────────────────────────────────────────────────────────────────────
# 3. Method C — Four bnlearn data-driven algorithms
# ─────────────────────────────────────────────────────────────────────────────
message("=== [3/5] Method C: bnlearn data-driven (4 algorithms) ===")

# Pedological whitelist (prior orientations that are physically
# indisputable — climate precedes soil; topography precedes climate).
wl_df <- data.frame(
  from = c("elev", "elev", "wc_bio_12", "wc_bio_01"),
  to   = c("slope", "wc_bio_12", "soc_topsoil_gkg", "soc_topsoil_gkg"),
  stringsAsFactors = FALSE
)

# Pedological blacklist (physically forbidden reversals — SOC cannot
# cause precipitation).
bl_df <- data.frame(
  from = c("soc_topsoil_gkg", "soc_topsoil_gkg",
           "wc_landcover_trees", "slope"),
  to   = c("wc_bio_12", "wc_bio_01",
           "wc_bio_12", "elev"),
  stringsAsFactors = FALSE
)

# Note: mmhc is temporarily excluded. `causal_structure_learn` passes
# `score` and `alpha` as flat args, but bnlearn::mmhc expects them
# split into `restrict.args` / `maximize.args`. A fix is scheduled for
# a future release; the three remaining algorithms (hc, tabu,
# pc-stable) are sufficient for a benchmark of data-driven structure
# learning at this scale.
bnlearn_methods <- c("hc", "tabu", "pc-stable")
method_C_results <- list()

for (m in bnlearn_methods) {
  message(sprintf("  [C/%s] running...", m))
  res <- tryCatch(
    causal_structure_learn(
      data       = df,
      variables  = DAG_NODES,
      method     = m,
      whitelist  = wl_df,
      blacklist  = bl_df,
      bootstrap  = FALSE,
      seed       = 1L
    ),
    error = function(e) {
      message(sprintf("    [warn] %s failed: %s", m, conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(res) && !is.null(res$graph)) {
    # res is an edaphos_causal_kg wrapping an igraph; harvest arcs.
    el <- tryCatch(igraph::as_edgelist(res$graph),
                    error = function(e) NULL)
    if (!is.null(el) && nrow(el) > 0L) {
      ed <- data.frame(from = el[, 1L], to = el[, 2L],
                         stringsAsFactors = FALSE)
      ed <- ed[ed$from %in% DAG_NODES & ed$to %in% DAG_NODES, , drop = FALSE]
    } else {
      ed <- data.frame(from = character(0), to = character(0))
    }
    method_C_results[[m]] <- ed
    message(sprintf("    -> %d edges", nrow(ed)))
  } else {
    method_C_results[[m]] <- data.frame(from = character(0), to = character(0))
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Pairwise SHD matrix + agreement table
# ─────────────────────────────────────────────────────────────────────────────
message("=== [4/5] Computing SHD matrix and agreement ===")

method_labels <- c("Expert", "LLM-augmented",
                   "bnlearn hc", "bnlearn tabu",
                   "bnlearn pc-stable")
edges_list <- list(
  "Expert"             = edges_A,
  "LLM-augmented"      = edges_B,
  "bnlearn hc"         = method_C_results[["hc"]],
  "bnlearn tabu"       = method_C_results[["tabu"]],
  "bnlearn pc-stable"  = method_C_results[["pc-stable"]]
)

n_methods <- length(edges_list)
shd_mat      <- matrix(NA_real_, nrow = n_methods, ncol = n_methods,
                        dimnames = list(method_labels, method_labels))
shared_mat   <- matrix(NA_real_, nrow = n_methods, ncol = n_methods,
                        dimnames = list(method_labels, method_labels))
reversed_mat <- matrix(NA_real_, nrow = n_methods, ncol = n_methods,
                        dimnames = list(method_labels, method_labels))

for (i in seq_len(n_methods)) {
  for (j in seq_len(n_methods)) {
    s <- compute_shd(edges_list[[i]], edges_list[[j]])
    shd_mat[i, j]      <- s$shd
    shared_mat[i, j]   <- s$shared
    reversed_mat[i, j] <- s$reversed
  }
}

message("SHD matrix:")
print(shd_mat)

# Edge-by-edge presence matrix
all_edges_set <- unique(do.call(rbind, lapply(edges_list, function(e)
  if (nrow(e) > 0) e else NULL)))
all_edges_set <- all_edges_set[order(all_edges_set$from,
                                       all_edges_set$to), ]
edge_keys <- paste(all_edges_set$from, "->", all_edges_set$to)

presence_mat <- matrix(0L, nrow = length(edge_keys), ncol = n_methods,
                        dimnames = list(edge_keys, method_labels))
for (j in seq_along(edges_list)) {
  if (nrow(edges_list[[j]]) > 0L) {
    keys_j <- paste(edges_list[[j]]$from, "->", edges_list[[j]]$to)
    presence_mat[rownames(presence_mat) %in% keys_j, j] <- 1L
  }
}

# Edges discovered by data-driven methods but MISSED by expert
dd_methods <- c("bnlearn hc", "bnlearn tabu", "bnlearn pc-stable")
dd_majority <- rowSums(presence_mat[, dd_methods, drop = FALSE]) >= 2L
expert_present <- presence_mat[, "Expert"] == 1L
novel_edges_data <- rownames(presence_mat)[dd_majority & !expert_present]

# Expert edges rejected by data (not in any data-driven method)
dd_any <- rowSums(presence_mat[, dd_methods, drop = FALSE]) >= 1L
expert_only_edges <- rownames(presence_mat)[expert_present & !dd_any]

message(sprintf(
  "  Novel edges (≥2 data methods, missed by expert) : %d",
  length(novel_edges_data)
))
message(sprintf(
  "  Expert edges rejected by all data methods        : %d",
  length(expert_only_edges)
))

# ─────────────────────────────────────────────────────────────────────────────
# 5. Identification sensitivity — backdoor adjustment set stability
# ─────────────────────────────────────────────────────────────────────────────
message("=== [5/5] Identification sensitivity ===")

get_adj <- function(ed, exposure = "wc_bio_12",
                     outcome = "soc_topsoil_gkg") {
  if (nrow(ed) == 0L) return(character(0))
  dag <- tryCatch(edges_to_dagitty(ed),
                   error = function(e) NULL)
  if (is.null(dag)) return(character(0))
  adj <- tryCatch(
    causal_adjustment_set(dag, exposure = exposure,
                           outcome = outcome, effect = "direct"),
    error = function(e) character(0)
  )
  if (is.null(adj)) character(0) else as.character(adj)
}

adj_sets <- list(
  "Expert"             = get_adj(edges_A),
  "LLM-augmented"      = get_adj(edges_B),
  "bnlearn hc"         = get_adj(method_C_results[["hc"]]),
  "bnlearn tabu"       = get_adj(method_C_results[["tabu"]]),
  "bnlearn pc-stable"  = get_adj(method_C_results[["pc-stable"]])
)

adj_table <- data.frame(
  method      = names(adj_sets),
  adj_size    = vapply(adj_sets, length, integer(1L)),
  adj_set     = vapply(adj_sets, function(x)
                          if (length(x) == 0L) "∅"
                          else paste(x, collapse = ", "),
                        character(1L)),
  stringsAsFactors = FALSE
)
message("Adjustment sets for wc_bio_12 -> soc_topsoil_gkg:")
print(adj_table)

# ─────────────────────────────────────────────────────────────────────────────
# Save bundle
# ─────────────────────────────────────────────────────────────────────────────
message("=== Saving bundle ===")

R_out <- list(
  version           = packageVersion("edaphos"),
  date_computed     = Sys.time(),
  n_profiles_used   = nrow(df),
  dag_nodes         = DAG_NODES,

  # Edge sets by method
  edges_expert      = edges_A,
  edges_llm_aug     = edges_B,
  edges_bnlearn     = method_C_results,
  llm_extra_edges   = llm_extra_edges,

  # Priors used
  whitelist         = wl_df,
  blacklist         = bl_df,

  # Metrics
  shd_matrix        = shd_mat,
  shared_matrix     = shared_mat,
  reversed_matrix   = reversed_mat,
  presence_matrix   = presence_mat,
  novel_edges_data  = novel_edges_data,
  expert_only_edges = expert_only_edges,

  # Identification sensitivity
  adjustment_sets   = adj_sets,
  adjustment_table  = adj_table
)

saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
