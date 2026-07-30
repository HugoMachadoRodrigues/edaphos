#!/usr/bin/env Rscript
# =============================================================================
# Patch the CAUSAL slots of capstone_campaign_results.rds with real data.
#
# Replaces the 5 hand-typed llm_claims rows and the fabricated causal_effects
# (whose betas matched no artefact) with:
#   * llm_claims        -- a real Gemma-4 knowledge-graph extraction over the
#                          10 real Cerrado abstracts in cerrado_abstracts.jsonl
#                          (requires a local Ollama with the `gemma4` model)
#   * causal_effects    -- the real 3077-profile backdoor table from
#                          causal_cerrado_real_v2.rds (adjusted associations +
#                          Cinelli-Hazlett robustness values)
#   * causal_posteriors -- real block-bootstrap (B=500) samples per exposure
#   * dag / dag_info    -- the real DAG and which LLM edges map onto its nodes
#
# The other pillars' slots are left untouched. Idempotent: re-running recomputes
# the causal slots from the same sources.
# =============================================================================
suppressMessages(pkgload::load_all(".", quiet = TRUE))
CAP <- "inst/extdata/capstone_campaign_results.rds"
R   <- readRDS(CAP)
v2  <- readRDS("inst/extdata/causal_cerrado_real_v2.rds")
d   <- v2$profiles
dag <- v2$dag

## ---- real Gemma-4 KG over the 10 real abstracts ----------------------------
abs <- lapply(readLines("inst/extdata/cerrado_abstracts.jsonl", warn = FALSE),
              jsonlite::fromJSON)
raw <- list()
for (a in abs) {
  r <- tryCatch(causal_llm_extract(text = a$abstract, backend = "ollama",
                                   model = "gemma4:latest", temperature = 0,
                                   timeout_sec = 180),
                error = function(e) NULL)
  if (!is.null(r) && nrow(r)) { r$source <- a$source; raw[[length(raw) + 1]] <- r }
}
claims <- do.call(rbind, raw)
claims <- claims[order(-claims$confidence), ]
claims <- claims[!duplicated(paste(tolower(claims$cause), tolower(claims$effect))), ]

## ---- real backdoor effects (mapped to the capstone's display columns) ------
lbl <- c(wc_bio_12 = "MAP (mm/a)", wc_bio_01 = "MAT (°C)",
         wc_landcover_trees = "Cobertura arbórea (0–1)", soilgrids_clay = "Argila (%)")
eff <- v2$effects
causal_effects <- data.frame(
  exposure = unname(lbl[eff$exposure]), outcome = "COS (g/kg)",
  estimate = eff$beta_adj, ci_lo = eff$ci_lo, ci_hi = eff$ci_hi,
  RV = eff$RV, adjustment = eff$adjustment, stringsAsFactors = FALSE)

## ---- real block-bootstrap posteriors ---------------------------------------
d$soc_topsoil_gkg <- d$soc; d$wc_bio_01 <- d$mat; d$wc_bio_12 <- d$map
d$wc_landcover_trees <- d$trees; d$soilgrids_clay <- d$clay
set.seed(1); cl <- stats::kmeans(scale(d[, c("lon", "lat")]), 20L, iter.max = 50L)$cluster
adj <- c(wc_bio_12 = "slope + wc_bio_01", wc_bio_01 = "slope + wc_bio_12",
         wc_landcover_trees = "wc_bio_01 + wc_bio_12", soilgrids_clay = "slope")
causal_posteriors <- setNames(lapply(names(adj), function(ex) {
  f <- stats::as.formula(sprintf("soc_topsoil_gkg ~ %s + %s", ex, adj[[ex]]))
  s <- vapply(1:500, function(b) {
    idx <- unlist(lapply(sample(unique(cl), replace = TRUE), function(k) which(cl == k)))
    unname(tryCatch(coef(lm(f, d[idx, ]))[ex], error = function(e) NA_real_))
  }, numeric(1))
  list(samples = s[is.finite(s)])
}), unname(lbl[names(adj)]))

## ---- map LLM concepts onto DAG nodes ---------------------------------------
nodes <- names(dagitty::coordinates(dag)$x)
base_edges <- with(dagitty::edges(dag), paste(v, w, sep = "->"))
syn <- c(soc = "soc_topsoil_gkg", topsoil_soc = "soc_topsoil_gkg",
         soil_organic_carbon = "soc_topsoil_gkg", soc_accumulation = "soc_topsoil_gkg",
         topsoil_organic_carbon_stocks = "soc_topsoil_gkg", soc_loss = "soc_topsoil_gkg",
         mean_annual_precipitation = "wc_bio_12", precipitation = "wc_bio_12", map = "wc_bio_12",
         mean_annual_temperature = "wc_bio_01", temperature = "wc_bio_01", mat = "wc_bio_01",
         clay_content = "soilgrids_clay", clay = "soilgrids_clay",
         sand = "soilgrids_sand", bulk_density = "soilgrids_bdod", bdod = "soilgrids_bdod",
         tree_cover = "wc_landcover_trees", woody_cover = "wc_landcover_trees",
         elevation = "elev", elev = "elev", slope = "slope")
norm <- function(x) gsub("[^a-z0-9]", "", tolower(x))
nn <- norm(nodes); names(syn) <- norm(names(syn)); syn <- setNames(norm(syn), names(syn))
map_node <- function(term) {
  t <- norm(term)
  if (t %in% nn) return(nodes[match(t, nn)])
  if (t %in% names(syn)) return(nodes[match(syn[[t]], nn)])
  NA_character_
}
claims$cause_node  <- vapply(claims$cause,  map_node, "")
claims$effect_node <- vapply(claims$effect, map_node, "")
on_dag <- claims[!is.na(claims$cause_node) & !is.na(claims$effect_node), ]
llm_edges <- if (nrow(on_dag)) unique(paste(on_dag$cause_node, on_dag$effect_node, sep = "->")) else character()

R$llm_claims <- claims[, c("cause", "effect", "confidence", "evidence")]
R$causal_effects <- causal_effects
R$causal_posteriors <- causal_posteriors
R$dag <- dag
R$dag_info <- list(
  n_nodes = length(nodes),
  n_edges = length(base_edges) + length(setdiff(llm_edges, base_edges)),
  base_edges = base_edges, llm_edges = llm_edges,
  edges_df = data.frame(from = with(dagitty::edges(dag), v), to = with(dagitty::edges(dag), w)),
  n_llm_claims_total = nrow(claims), n_llm_claims_on_dag = nrow(on_dag))
R$causal_provenance <- list(n_profiles = v2$n_profiles, source = "causal_cerrado_real_v2.rds",
  llm = sprintf("Gemma-4 over %d real abstracts: %d edges, %d expressible in the DAG",
                length(abs), nrow(claims), nrow(on_dag)))
saveRDS(R, CAP, compress = "xz")
message(sprintf("patched capstone causal slots: %d LLM edges (%d on DAG), effects on %d profiles",
                nrow(claims), nrow(on_dag), v2$n_profiles))
