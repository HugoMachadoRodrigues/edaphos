# Upload the edaphos-cerrado-moco-v1 encoder to Zenodo via the REST
# API, in two stages:
#
#   Rscript data-raw/zenodo_upload.R create
#       Creates a new draft deposition, uploads the five bundled
#       files from tools/pretrain/zenodo-upload/, attaches the
#       metadata, and prints the draft id + a preview URL. Does NOT
#       publish; drafts can be deleted with no consequences.
#
#   Rscript data-raw/zenodo_upload.R publish <deposit_id>
#       Publishes the named draft. Prints the resulting DOI, the
#       direct-download URL of encoder_q.pt, and the publication
#       timestamp -- the three fields the edaphos weights registry
#       needs.
#
#   Rscript data-raw/zenodo_upload.R discard <deposit_id>
#       Discards a draft (deletes it). Useful if the stage-1 result
#       doesn't look right.
#
# The API token is read from the ZENODO_TOKEN environment variable
# so it is never written to disk or committed.

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args) >= 1L) args[[1L]] else "create"

token <- Sys.getenv("ZENODO_TOKEN")
if (!nzchar(token)) {
  stop("ZENODO_TOKEN is empty. Pass the API token via env var:\n",
       "   ZENODO_TOKEN='...' Rscript data-raw/zenodo_upload.R create",
       call. = FALSE)
}

# Pick production or sandbox based on an optional env flag; defaults
# to production. Sandbox is recommended for rehearsal — its DOIs
# start with 10.5072 and its site is sandbox.zenodo.org.
api_base <- if (identical(Sys.getenv("ZENODO_SANDBOX"), "1")) {
  "https://sandbox.zenodo.org/api"
} else {
  "https://zenodo.org/api"
}
ui_base <- sub("/api$", "", api_base)
message(sprintf("[zenodo] target: %s", api_base))

.zen_req <- function(path, ...) {
  req <- httr2::request(paste0(api_base, path))
  req <- httr2::req_headers(req,
                              Authorization = sprintf("Bearer %s", token))
  req <- httr2::req_timeout(req, 300L)
  req <- httr2::req_retry(req, max_tries = 3L,
                            is_transient = function(r) {
                              httr2::resp_status(r) %in% c(429L, 500L,
                                                              502L, 503L,
                                                              504L)
                            },
                            backoff = function(i) 2 ^ i)
  req <- httr2::req_error(req, is_error = function(r) {
    st <- httr2::resp_status(r)
    st >= 400L
  })
  req
}

.zen_perform <- function(req) {
  resp <- httr2::req_perform(req)
  httr2::resp_body_json(resp, simplifyVector = FALSE)
}

# --- metadata ---------------------------------------------------------------

.meta <- function() {
  list(
    title = paste(
      "edaphos-cerrado-moco-v1 --",
      "a MoCo v2 foundation-model encoder for the Brazilian",
      "Cerrado soil covariate stack"
    ),
    upload_type = "dataset",
    description = paste(collapse = "\n\n",
      c(
        "A self-supervised MoCo v2 (He et al. 2020; Chen et al. 2020) encoder pretrained on 50000 16x16 raster patches sampled from a core Cerrado AoI (longitude -53 to -43, latitude -23 to -10), covering the Brazilian states of Goias, Tocantins, Mato Grosso, Bahia and Minas Gerais. The input stack is aligned to a 0.01-degree (~1 km) grid and combines three public keyless sources:",
        "- SoilGrids 250m, 0-5 cm mean: SOC, clay, sand, pH(H2O), bulk density (5 layers)",
        "- WorldClim 2.1 (Brazil country pack): 12 monthly precipitation + 12 monthly mean temperature (24 layers)",
        "- SRTM 30 arc-second: elevation + slope (2 layers)",
        "The encoder is a 5-block convolutional backbone producing a 64-dimensional feature vector followed by a 2-layer MLP projection head (feature_dim = 64, proj_dim = 32). Training uses a queue of 4096 negatives, InfoNCE temperature 0.07, momentum 0.999, Adam learning rate 3e-4, batch size 64, for 20000 optimisation steps on an Apple Silicon M1 Max via torch::backend_mps.",
        "Artefact files: encoder_q.pt (state_dict, SHA-256 44ace7f78c658b6028f1cf5ccfa624023295e5576f681d0135db64726c6738e8), metadata.json (full training configuration), loss_history.rds (per-step InfoNCE loss), encoder_q.pt.sha256 (digest sidecar).",
        "Consumed by the edaphos R package (>= 1.2.0) via foundation_weights_load('edaphos-cerrado-moco-v1')."
      )
    ),
    creators = list(list(
      name        = "Rodrigues, Hugo",
      orcid       = "0000-0002-8070-8126"
    )),
    keywords = list(
      "digital soil mapping", "foundation models",
      "self-supervised learning", "MoCo", "Cerrado",
      "pedometry", "SoilGrids", "WorldClim", "SRTM",
      "transfer learning"
    ),
    access_right = "open",
    license      = "cc-by-4.0",
    language     = "eng",
    version      = "1.0",
    related_identifiers = list(
      list(identifier = "10.1371/journal.pone.0169748",
           relation   = "isDerivedFrom",
           scheme     = "doi",
           resource_type = "publication-article"),
      list(identifier = "10.1002/joc.5086",
           relation   = "isDerivedFrom",
           scheme     = "doi",
           resource_type = "publication-article"),
      list(identifier = "https://github.com/HugoMachadoRodrigues/edaphos",
           relation   = "isSupplementTo",
           scheme     = "url",
           resource_type = "software")
    )
  )
}

# --- stages -----------------------------------------------------------------

create_draft <- function() {
  bundle_dir <- "tools/pretrain/zenodo-upload"
  files <- c("encoder_q.pt", "encoder_q.pt.sha256",
             "metadata.json", "loss_history.rds", "README.md")
  for (f in files) {
    stopifnot(file.exists(file.path(bundle_dir, f)))
  }

  # Zenodo's POST /deposit/depositions rejects both "no body" and
  # "empty JSON array" with a 500; sending the full metadata upfront
  # is the reliable path and saves a round-trip compared with
  # create-empty-then-PUT-metadata.
  message("[zenodo] 1/3  creating draft deposit with metadata attached...")
  draft <- .zen_perform(
    httr2::req_body_json(
      httr2::req_method(.zen_req("/deposit/depositions"), "POST"),
      list(metadata = .meta())
    )
  )
  deposit_id <- draft$id
  bucket_url <- draft$links$bucket
  message(sprintf("  [ok] deposit id = %s", deposit_id))
  message(sprintf("  [ok] bucket     = %s", bucket_url))

  message("[zenodo] 2/3  uploading files via the bucket API...")
  for (f in files) {
    path <- file.path(bundle_dir, f)
    size <- file.info(path)$size
    message(sprintf("  [..] %-28s  (%.1f KB)", f, size / 1024))
    # Bucket-URL files API: PUT binary body to <bucket>/<filename>.
    # We do NOT use .zen_req() here because bucket uploads live
    # outside of /api/deposit and use different timeouts.
    req <- httr2::request(paste0(bucket_url, "/", f))
    req <- httr2::req_headers(req,
                                Authorization = sprintf("Bearer %s", token))
    req <- httr2::req_timeout(req, 600L)
    req <- httr2::req_body_file(req, path)
    req <- httr2::req_method(req, "PUT")
    r <- httr2::req_perform(req)
    if (httr2::resp_status(r) >= 400L) {
      stop(sprintf("  upload of %s failed (HTTP %d)",
                    f, httr2::resp_status(r)),
           call. = FALSE)
    }
    message(sprintf("  [ok] %s", f))
  }

  # Metadata was attached in step 1 (create-with-metadata). Nothing
  # to do here.
  message("[zenodo] 3/3  metadata was attached at creation time")

  preview_url <- sprintf("%s/uploads/%s", ui_base, deposit_id)
  message("")
  message("  ================================================================")
  message(sprintf("  DRAFT CREATED (NOT PUBLISHED)"))
  message(sprintf("  deposit id: %s", deposit_id))
  message(sprintf("  preview   : %s", preview_url))
  message("  ================================================================")
  message("")
  message(sprintf("  To publish:   Rscript data-raw/zenodo_upload.R publish %s",
                   deposit_id))
  message(sprintf("  To discard:   Rscript data-raw/zenodo_upload.R discard %s",
                   deposit_id))
  invisible(deposit_id)
}

publish_draft <- function(deposit_id) {
  message(sprintf("[zenodo] publishing draft %s...", deposit_id))
  published <- .zen_perform(
    httr2::req_method(
      .zen_req(sprintf("/deposit/depositions/%s/actions/publish",
                          deposit_id)),
      "POST"
    )
  )
  doi        <- published$doi         %||% published$metadata$doi
  created    <- published$created     %||% NA_character_
  submitted  <- published$submitted   %||% TRUE
  record_url <- published$links$record_html %||% published$links$html
  files      <- published$files %||% list()
  encoder_file <- Filter(function(f) identical(f$filename, "encoder_q.pt"),
                           files)
  encoder_url  <- if (length(encoder_file) >= 1L) {
    encoder_file[[1L]]$links$download %||% encoder_file[[1L]]$links$self
  } else NA_character_
  message("")
  message("  ================================================================")
  message(sprintf("  PUBLISHED"))
  message(sprintf("  DOI        : %s", doi))
  message(sprintf("  record     : %s", record_url))
  message(sprintf("  encoder_q  : %s", encoder_url))
  message(sprintf("  timestamp  : %s", created))
  message("  ================================================================")
  invisible(list(doi = doi, url = encoder_url, timestamp = created))
}

discard_draft <- function(deposit_id) {
  message(sprintf("[zenodo] discarding draft %s", deposit_id))
  r <- httr2::req_perform(
    httr2::req_method(.zen_req(sprintf("/deposit/depositions/%s",
                                          deposit_id)),
                        "DELETE")
  )
  message(sprintf("  [ok] HTTP %d", httr2::resp_status(r)))
}

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a)))
  b else a

if (mode == "create") {
  create_draft()
} else if (mode == "publish") {
  if (length(args) < 2L) stop("usage: publish <deposit_id>", call. = FALSE)
  publish_draft(args[[2L]])
} else if (mode == "discard") {
  if (length(args) < 2L) stop("usage: discard <deposit_id>", call. = FALSE)
  discard_draft(args[[2L]])
} else {
  stop("unknown mode '", mode, "'. Use one of: create, publish, discard.",
       call. = FALSE)
}
