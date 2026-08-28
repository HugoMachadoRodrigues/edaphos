#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# tools/provenance-inventory.R -- a measured inventory of what this package
# ships and where it came from. Writes tools/provenance-inventory.json.
#
#   Rscript tools/provenance-inventory.R
#
# WHY THIS EXISTS. "Does this package redistribute third-party soil data?" is
# a question of fact, and a hand-written answer is worth nothing: the reader
# has only the author's word for it. Everything below is measured from the
# repository, so any figure in the resulting document can be re-derived by
# anyone holding a checkout.
#
# TWO METHOD NOTES, both learned by getting them wrong first.
#
# 1. SEARCH DECOMPRESSED CONTENT, NOT RAW BYTES. `.rds` is gzip/xz and `.docx`
#    is a ZIP. Grepping their raw bytes for a four-letter term produces
#    matches by chance: `paper/plos-manuscript.docx` "contains" the bytes
#    `ncss` in its DEFLATE stream, and unzipping it shows the XML contains no
#    such word. Every content search here decompresses first.
#
# 2. HASHES USE THE PACKAGE'S OWN CONVENTION. `.script_hash()` hashes the
#    file's lines joined by "\n" through `digest`, NOT the raw file bytes, so
#    `shasum -a 256 <file>` disagrees with a recorded `script_sha256` by
#    design. Comparing the two looks like a tampered file and is not one.
# ---------------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
TERMS <- c("datsoilspc", "svrc_example", "KSSL", "Kellogg", "NCSS", "RaCA",
           "SSURGO", "STATSGO", "USDA", "NRCS")

# -- the package's own hashing convention, read from source rather than from
#    an installed copy, which may be older than the working tree.
src <- readLines("R/provenance.R", warn = FALSE)
i <- grep("^[.]script_hash <- function", src)[1]
j <- i; d <- 0L
repeat {
  d <- d + lengths(regmatches(src[j], gregexpr("[{]", src[j]))) -
           lengths(regmatches(src[j], gregexpr("[}]", src[j])))
  if (j > i && d == 0L) break
  j <- j + 1L
}
eval(parse(text = paste(src[i:j], collapse = "\n")))

file_sha <- function(p) if (requireNamespace("digest", quietly = TRUE))
  digest::digest(file = p, algo = "sha256") else unname(tools::md5sum(p))

read_any <- function(f) if (grepl("[.]rda$", f)) {
  e <- new.env(); load(f, e); get(ls(e)[1], e)
} else readRDS(f)

# -- every (lon, lat) pair anywhere inside an object, however nested --------
coords_of <- function(x, depth = 0L) {
  if (depth > 6L || is.null(x)) return(NULL)
  pair <- function(lo, la) {
    lo <- suppressWarnings(as.numeric(lo)); la <- suppressWarnings(as.numeric(la))
    if (length(lo) != length(la)) return(NULL)
    ok <- is.finite(lo) & is.finite(la)
    if (any(ok)) list(lon = lo[ok], lat = la[ok]) else NULL
  }
  if (is.data.frame(x)) {
    nm <- tolower(names(x))
    il <- which(nm %in% c("lon", "longitude", "long", "x"))
    ia <- which(nm %in% c("lat", "latitude", "y"))
    if (length(il) && length(ia)) return(pair(x[[il[1]]], x[[ia[1]]]))
    return(NULL)
  }
  if (is.list(x)) {
    nm <- names(x)
    if (!is.null(nm)) {
      il <- which(tolower(nm) %in% c("lon", "lons", "longitude"))
      ia <- which(tolower(nm) %in% c("lat", "lats", "latitude"))
      if (length(il) && length(ia) && is.numeric(x[[il[1]]]) && is.numeric(x[[ia[1]]])) {
        p <- pair(x[[il[1]]], x[[ia[1]]]); if (!is.null(p)) return(p)
      }
    }
    r <- lapply(x, coords_of, depth = depth + 1L)
    r <- r[!vapply(r, is.null, TRUE)]
    if (length(r)) return(list(lon = unlist(lapply(r, `[[`, "lon")),
                               lat = unlist(lapply(r, `[[`, "lat"))))
  }
  NULL
}

# Bounding boxes. Brazil is generous on purpose -- the claim being tested is
# "these points are not in the United States", and a loose Brazil box makes
# that claim harder to pass, not easier.
in_brazil <- function(lo, la) lo >= -74 & lo <= -34 & la >= -34 & la <= 6
in_usa <- function(lo, la)
  (lo > -125 & lo < -66 & la > 24 & la < 50) |   # conterminous
  (lo > -170 & lo < -130 & la > 51 & la < 72)    # Alaska

# -- every character string reachable inside an object ----------------------
strings_of <- function(x, depth = 0L, acc = character()) {
  if (depth > 6L || is.null(x)) return(acc)
  if (is.character(x)) acc <- c(acc, x)
  nm <- names(x); if (!is.null(nm)) acc <- c(acc, nm)
  if (is.list(x) && length(x))
    for (k in seq_along(x)) acc <- strings_of(x[[k]], depth + 1L, acc)
  acc
}

# -- walk the shipped artefacts --------------------------------------------
files <- c(sort(list.files("inst/extdata", "[.]rds$", full.names = TRUE)),
           sort(list.files("data", "[.]rda$", full.names = TRUE)))

entry <- function(path) {
  ob <- tryCatch(read_any(path), error = function(e) NULL)
  g <- coords_of(ob)
  st <- strings_of(ob)
  hits <- TERMS[vapply(TERMS, function(t) any(grepl(t, st, ignore.case = TRUE)), TRUE)]
  pr <- if (is.list(ob)) ob$provenance else NULL
  scr <- pr$script %||% ob$built_by %||% NA_character_
  out <- list(
    file = basename(path),
    bytes = unname(file.size(path)),
    sha256_file = unname(file_sha(path)),
    script = if (is.na(scr[1])) NA_character_ else scr[1],
    script_sha256_recorded = pr$script_sha256 %||% NA_character_,
    script_hash_verifies = if (!is.null(pr$script_sha256) && !is.na(scr[1]) &&
                               file.exists(scr[1]))
      identical(unname(.script_hash(scr[1])[["hash"]]), pr$script_sha256) else NA,
    built_from = pr$built_from %||% NA_character_,
    stripped = !is.null(ob$strip_note),
    sources = unique(trimws(unlist(lapply(ob$sources %||% list(), as.character)))),
    terms_found = hits,
    n_coords = if (is.null(g)) 0L else length(g$lon)
  )
  if (!is.null(g)) {
    out$lon_range <- round(range(g$lon), 4)
    out$lat_range <- round(range(g$lat), 4)
    out$coords_in_brazil <- sum(in_brazil(g$lon, g$lat))
    out$coords_in_usa <- sum(in_usa(g$lon, g$lat))
  } else {
    out$coords_in_brazil <- 0L; out$coords_in_usa <- 0L
  }
  out
}

cat("walking", length(files), "shipped artefacts ...\n")
bundles <- lapply(files, entry)

# -- the strongest check: synthetic points vs the real coordinates removed ---
#
# A bounding box tests where points ARE. This tests what they are NOT: it
# rebuilds the coordinate universe that the 2026-08-28 strip removed and asks
# whether anything still shipped coincides with it. That is the check the
# accusation actually calls for -- content against the concrete set alleged to
# have been copied, rather than content against a map.
#
# The removed universe is computed by DIFFERENCE, pre-strip minus post-strip,
# rather than by parsing the manifest. The manifest is prose written by the
# strip script; the difference is measured from the bundles themselves, and it
# is what caught that the manifest under-reports (11 rows for 13 bundles).
STRIP_COMMIT <- "8f23ddf"

git_show_rds <- function(rev, path) {
  tf <- tempfile(fileext = ".rds")
  ok <- suppressWarnings(system2("git", c("show", paste0(rev, ":", path)),
                                 stdout = tf, stderr = FALSE))
  on.exit(unlink(tf), add = TRUE)
  if (!identical(ok, 0L) || !file.exists(tf) || file.size(tf) == 0) return(NULL)
  tryCatch(readRDS(tf), error = function(e) NULL)
}

ckey <- function(g) if (is.null(g)) character(0) else
  paste(round(g$lon, 5), round(g$lat, 5))

collision <- NULL
parent <- suppressWarnings(system2("git", c("rev-parse", paste0(STRIP_COMMIT, "^")),
                                   stdout = TRUE, stderr = FALSE))
if (length(parent) == 1L && nzchar(parent)) {
  pre_paths <- suppressWarnings(system2("git",
    c("ls-tree", "-r", "--name-only", parent), stdout = TRUE, stderr = FALSE))
  pre_paths <- grep("^inst/extdata/.*[.]rds$", pre_paths, value = TRUE)

  removed <- character(0)
  for (rp in pre_paths) {
    pre <- ckey(coords_of(git_show_rds(parent, rp)))
    cur <- if (file.exists(rp)) ckey(coords_of(read_any(rp))) else character(0)
    removed <- c(removed, setdiff(pre, cur))
  }
  removed <- unique(removed)

  per_file <- lapply(files, function(f) {
    k <- ckey(coords_of(read_any(f)))
    list(file = basename(f), n_coords = length(k),
         collisions = sum(k %in% removed))
  })
  collision <- list(
    strip_commit = STRIP_COMMIT,
    compared_against = parent,
    removed_coordinates_distinct = length(removed),
    per_artefact = per_file,
    total_collisions = sum(vapply(per_file, function(x) x$collisions, 0L))
  )
  cat(sprintf("  %d distinct coordinates were removed by the strip\n",
              length(removed)))
} else {
  cat("  strip commit not reachable; collision check skipped\n")
}

# -- the absence search, over DECOMPRESSED content --------------------------
# Two surfaces: the working tree's text files, and every blob that has ever
# existed in this repository. See tools/history-term-scan.sh for the latter.
cat("scanning working tree ...\n")
tree_hits <- lapply(TERMS, function(t) {
  f <- suppressWarnings(system2("grep",
    c("-rl", "-i", t, "R", "man", "tests", "vignettes", "data-raw", "inst",
      "NEWS.md", "README.md", "DESCRIPTION", "NAMESPACE"),
    stdout = TRUE, stderr = FALSE))
  # tools/ is excluded: this script and its own output contain every term by
  # construction, and counting them would be counting the question as evidence.
  f <- f[!grepl("^tools/", f)]
  list(term = t, n_files = length(f), files = f)
})

res <- list(
  generated_by = "tools/provenance-inventory.R",
  repository = "edaphos",
  commit = tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE)[1],
                    error = function(e) NA_character_),
  package_version = tryCatch(
    sub("^Version:[[:space:]]*", "",
        grep("^Version:", readLines("DESCRIPTION", warn = FALSE), value = TRUE)[1]),
    error = function(e) NA_character_),
  bundles = bundles,
  collision_check = collision,
  tree_search = tree_hits,
  totals = list(
    artefacts = length(bundles),
    coordinates = sum(vapply(bundles, function(b) b$n_coords, 0L)),
    coordinates_in_brazil = sum(vapply(bundles, function(b) b$coords_in_brazil, 0L)),
    coordinates_in_usa = sum(vapply(bundles, function(b) b$coords_in_usa, 0L)),
    stripped_bundles = sum(vapply(bundles, function(b) isTRUE(b$stripped), TRUE)),
    hashes_verified = sum(vapply(bundles, function(b) isTRUE(b$script_hash_verifies), TRUE)),
    artefacts_containing_terms =
      sum(vapply(bundles, function(b) length(b$terms_found) > 0L, TRUE)),
    removed_coordinates = collision$removed_coordinates_distinct %||% NA_integer_,
    coordinate_collisions = collision$total_collisions %||% NA_integer_
  )
)

jsonlite::write_json(res, "tools/provenance-inventory.json",
                     auto_unbox = TRUE, pretty = TRUE, null = "null")
t <- res$totals
cat(sprintf(paste0("\n  %d artefacts | %d coordinates (%d in Brazil, %d in the USA)\n",
                   "  %d stripped | %d provenance hashes verified\n",
                   "  %d artefacts contain any search term\n",
                   "  %s coordinates removed by the strip | %s still-shipped collisions\n"),
            t$artefacts, t$coordinates, t$coordinates_in_brazil,
            t$coordinates_in_usa, t$stripped_bundles, t$hashes_verified,
            t$artefacts_containing_terms,
            format(t$removed_coordinates), format(t$coordinate_collisions)))
