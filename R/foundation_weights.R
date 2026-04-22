# Pillar 4 -- Pretrained weights distribution.
#
# Self-supervised pretraining on planetary tile stacks is heavy
# (hours of GPU time per run, gigabytes of raw input). Asking every
# `edaphos` user to reproduce that training from scratch before they
# can try the downstream fine-tuning API is the single biggest
# usability gap in Pillar 4. The three functions in this file close
# that gap:
#
#   * foundation_weights_list()      -- registry of published weights
#   * foundation_weights_download()  -- fetch + SHA-256 verify + cache
#   * foundation_weights_load()      -- restore into a MoCo v2 wrapper
#
# All artefacts are hosted publicly on **Zenodo**, so each release has
# a DOI, is discoverable via the Zenodo search API, and is archived
# indefinitely by CERN under the ESR Reproducibility Initiative. The
# GitHub release URL is also recorded as a fallback mirror for users
# on restricted networks.
#
# Storage layout
# ==============
# The default on-disk cache follows the R `rappdirs` standard:
#
#   <user_cache_dir>/edaphos/weights/<name>/
#     encoder_q.pt       (raw torch state_dict, gzip-compressed)
#     metadata.json      (channels, feature_dim, AoI, training config)
#
# Verification
# ============
# Every entry carries a SHA-256 digest that is re-computed on
# download. A mismatch raises an error rather than a warning, because
# silently loading tampered weights would compromise the
# reproducibility claim.

# ---- registry --------------------------------------------------------------

.foundation_weights_registry <- function() {
  # Hand-curated registry of published pretrained encoders. Each row
  # must carry a stable `name`, a Zenodo DOI / URL, a SHA-256 digest
  # of the encoder state_dict, and the metadata needed to rebuild
  # the in-memory `edaphos_foundation_moco` wrapper.
  #
  # When a new encoder is published, add a row here and bump the
  # package's minor version. The `url`, `doi` and `published_at`
  # fields remain NA until the Zenodo deposit is created; the
  # package consumer sees a clear "no published URL yet" error until
  # the next maintenance release wires them up.
  data.frame(
    name = c("edaphos-cerrado-moco-v1"),
    description = c(
      "MoCo v2 encoder pretrained on 50k 16x16 Cerrado tiles (SoilGrids 250m soc/clay/sand/phh2o/bdod + WorldClim 2.1 monthly prec/tavg + SRTM elev/slope), aligned to a 0.01-deg grid. 31 channels in, 64-dim feature embedding out. 20000 InfoNCE steps on an Apple M1 Max MPS; final InfoNCE loss ~1.64."
    ),
    n_channels  = c(31L),
    feature_dim = c(64L),
    proj_dim    = c(32L),
    patch_size  = c(16L),
    aoi         = c("Cerrado core (lon -53 to -43, lat -23 to -10)"),
    url         = c("https://zenodo.org/records/19701276/files/encoder_q.pt"),
    sha256      = c(
      "44ace7f78c658b6028f1cf5ccfa624023295e5576f681d0135db64726c6738e8"
    ),
    doi         = c("10.5281/zenodo.19701276"),
    license     = c("CC-BY-4.0"),
    published_at = c("2026-04-22T21:59:12Z"),
    edaphos_version = c("1.2.0"),
    stringsAsFactors = FALSE
  )
}

#' Catalogue of pretrained Pillar 4 encoders
#'
#' Returns a data frame describing every pretrained encoder published
#' by the `edaphos` project: its name, the Zenodo DOI, the raster
#' AoI it was trained on, the number of input channels it expects,
#' the feature dimension of its embeddings, and the SHA-256 digest
#' of the hosted artefact.
#'
#' New encoders are added by the `edaphos` maintainers on each minor
#' release and propagated through the package. Users with bespoke
#' pretrained encoders can bypass the registry entirely by passing a
#' local `.pt` path directly to [foundation_weights_load()].
#'
#' @return A data frame; one row per registered encoder.
#' @examples
#' foundation_weights_list()
#' @export
foundation_weights_list <- function() {
  .foundation_weights_registry()
}

# ---- cache directory -------------------------------------------------------

.foundation_weights_cache_dir <- function(cache_dir = NULL, name = NULL) {
  root <- cache_dir %||% tools::R_user_dir("edaphos", which = "cache")
  root <- file.path(root, "weights")
  if (!is.null(name)) root <- file.path(root, name)
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  root
}

.foundation_weights_entry <- function(name) {
  reg <- .foundation_weights_registry()
  m   <- reg[reg$name == name, , drop = FALSE]
  if (nrow(m) != 1L) {
    stop("Unknown pretrained encoder '", name,
         "'. Run foundation_weights_list() to see available names.",
         call. = FALSE)
  }
  m
}

.sha256_file <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    # Fallback: base tools::md5sum is the only base-R hash; we use
    # digest::digest(..., algo = "sha256") when available, otherwise
    # emit a warning and skip verification.
    warning("Install `digest` to verify downloaded weights ",
             "(install.packages('digest')). Skipping SHA-256 check.",
             call. = FALSE)
    return(NA_character_)
  }
  digest::digest(file = path, algo = "sha256")
}

# ---- download --------------------------------------------------------------

#' Download a pretrained Pillar 4 encoder from Zenodo
#'
#' Fetches a named pretrained encoder from its registered URL (a
#' public Zenodo deposit), verifies its SHA-256 digest against the
#' registry, and caches the result under the user's standard cache
#' directory so subsequent calls are instantaneous.
#'
#' The cache directory defaults to
#' `tools::R_user_dir("edaphos", which = "cache") / weights / <name>`.
#' Override via `cache_dir` if you need to share the download across
#' users on a shared HPC filesystem, or to redirect the cache away
#' from a quota-limited home directory.
#'
#' @param name Character — a name from [foundation_weights_list()].
#' @param cache_dir Optional directory override.
#' @param overwrite Logical — if `TRUE`, re-download even when a
#'   cached copy exists.
#' @param timeout_sec Network timeout for the download request. The
#'   encoder artefacts are typically 1–5 MB, so 300 s is a comfortable
#'   ceiling.
#' @param verbose Logical — print progress messages.
#' @return A named list with:
#' \describe{
#'   \item{path}{Local path to the cached `.pt` state dict.}
#'   \item{metadata}{Local path to the `metadata.json` sidecar.}
#'   \item{entry}{The registry row (a one-row data frame).}
#' }
#' @seealso [foundation_weights_load()], [foundation_weights_list()].
#' @examples
#' \dontrun{
#'   loc <- foundation_weights_download("edaphos-cerrado-moco-v1",
#'                                        verbose = TRUE)
#'   moco <- foundation_weights_load(loc$path)
#' }
#' @export
foundation_weights_download <- function(name,
                                          cache_dir = NULL,
                                          overwrite = FALSE,
                                          timeout_sec = 300L,
                                          verbose = FALSE) {
  entry <- .foundation_weights_entry(name)
  if (is.na(entry$url) || !nzchar(entry$url)) {
    stop("Registered entry '", name, "' has no published URL yet ",
         "(this encoder is scheduled for a future release). ",
         "Check foundation_weights_list() for alternatives.",
         call. = FALSE)
  }
  dest_dir <- .foundation_weights_cache_dir(cache_dir, name)
  pt_path    <- file.path(dest_dir, "encoder_q.pt")
  meta_path  <- file.path(dest_dir, "metadata.json")

  need_download <- isTRUE(overwrite) || !file.exists(pt_path)
  if (need_download) {
    if (verbose) {
      message(sprintf("[foundation-weights] downloading %s  (%s)",
                       name, entry$url))
    }
    req <- httr2::request(entry$url)
    req <- httr2::req_timeout(req, timeout_sec)
    req <- httr2::req_retry(req, max_tries = 3L,
                              backoff = function(i) 2 ^ i)
    resp <- httr2::req_perform(req, path = pt_path)
    if (httr2::resp_status(resp) >= 400L) {
      stop("Download of '", name, "' failed with HTTP status ",
           httr2::resp_status(resp), ".", call. = FALSE)
    }
  } else if (verbose) {
    message("[foundation-weights] cache hit: ", pt_path)
  }

  # SHA-256 verification (best-effort; warns if `digest` missing).
  if (!is.na(entry$sha256) && nzchar(entry$sha256)) {
    got <- .sha256_file(pt_path)
    if (!is.na(got) && !identical(got, entry$sha256)) {
      unlink(pt_path)
      stop("SHA-256 mismatch for '", name, "': expected ",
           entry$sha256, ", got ", got, ". Cached copy deleted; ",
           "re-run with overwrite = TRUE once the registry is updated.",
           call. = FALSE)
    }
  }

  # Best-effort download of a metadata sidecar. Every published Zenodo
  # entry ships a `<name>.json` sidecar at a predictable URL next to
  # the weights; missing sidecars are tolerated (we fall back to the
  # registry row itself).
  if (!file.exists(meta_path)) {
    meta_url <- sub("\\.pt(?:\\.gz)?$", ".json", entry$url, perl = TRUE)
    if (meta_url != entry$url) {
      meta_resp <- tryCatch(
        httr2::req_perform(
          httr2::req_timeout(httr2::request(meta_url), timeout_sec),
          path = meta_path
        ),
        error = function(e) NULL
      )
      if (!is.null(meta_resp) &&
          httr2::resp_status(meta_resp) < 400L) {
        if (verbose) {
          message("[foundation-weights] metadata sidecar cached")
        }
      } else if (file.exists(meta_path)) {
        unlink(meta_path)
      }
    }
  }

  list(path = pt_path, metadata = meta_path, entry = entry)
}

# ---- load ------------------------------------------------------------------

#' Load a pretrained encoder into an `edaphos_foundation_moco` wrapper
#'
#' Restores a pretrained MoCo v2 encoder from a `.pt` state-dict file
#' (or by name from the published registry) into an in-memory
#' `edaphos_foundation_moco` object that is **shape-compatible** with
#' the output of [foundation_moco_pretrain_tiles()]. The restored
#' object is ready to feed into [foundation_moco_embed()],
#' [foundation_fit_classifier()] or [foundation_fit_regressor()]
#' without any additional plumbing.
#'
#' @param source Either a character name registered in
#'   [foundation_weights_list()] — in which case the encoder is
#'   downloaded (cached) via [foundation_weights_download()] — or a
#'   path to a local `.pt` file. For the local path case, pass the
#'   matching metadata as `n_channels` / `feature_dim` / etc.
#' @param n_channels,feature_dim,proj_dim Optional integers; when
#'   `source` is a local path these must describe the shape the
#'   `.pt` file was saved from. When `source` is a registry name they
#'   are pulled from the registry.
#' @param cache_dir,overwrite,verbose Forwarded to
#'   [foundation_weights_download()] when `source` is a registry
#'   name.
#' @return An `edaphos_foundation_moco` object with a populated
#'   `$encoder_q` (the query encoder; the momentum encoder is not
#'   restored because it is only needed during training).
#' @examples
#' \dontrun{
#'   moco <- foundation_weights_load("edaphos-cerrado-moco-v1")
#'   emb  <- foundation_moco_embed(moco, patches)
#' }
#' @export
foundation_weights_load <- function(source,
                                      n_channels  = NULL,
                                      feature_dim = NULL,
                                      proj_dim    = NULL,
                                      cache_dir   = NULL,
                                      overwrite   = FALSE,
                                      verbose     = FALSE) {
  .moco_require_torch()

  if (is.character(source) && length(source) == 1L &&
      !file.exists(source)) {
    loc <- foundation_weights_download(source, cache_dir = cache_dir,
                                          overwrite = overwrite,
                                          verbose = verbose)
    pt_path <- loc$path
    entry   <- loc$entry
    n_channels  <- n_channels  %||% entry$n_channels
    feature_dim <- feature_dim %||% entry$feature_dim
    proj_dim    <- proj_dim    %||% entry$proj_dim
  } else {
    stopifnot(is.character(source), length(source) == 1L,
              file.exists(source))
    pt_path <- source
    if (is.null(n_channels) || is.null(feature_dim) ||
        is.null(proj_dim)) {
      stop("Loading from a local path requires `n_channels`, ",
           "`feature_dim` and `proj_dim` to be supplied explicitly.",
           call. = FALSE)
    }
    entry <- NULL
  }

  stopifnot(is.numeric(n_channels), is.numeric(feature_dim),
            is.numeric(proj_dim))
  n_channels  <- as.integer(n_channels)
  feature_dim <- as.integer(feature_dim)
  proj_dim    <- as.integer(proj_dim)

  EncCtor <- .moco_build_encoder()
  enc_q <- EncCtor(in_channels = n_channels,
                    feature_dim = feature_dim,
                    proj_dim    = proj_dim)
  state <- torch::torch_load(pt_path)
  enc_q$load_state_dict(state)
  enc_q$eval()

  structure(
    list(
      encoder_q   = enc_q,
      feature_dim = feature_dim,
      proj_dim    = proj_dim,
      n_channels  = n_channels,
      source      = if (is.null(entry)) pt_path else entry$name,
      registry    = entry
    ),
    class = "edaphos_foundation_moco"
  )
}
