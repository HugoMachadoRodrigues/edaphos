# edaphos Dockerfile
#
# WHAT THIS IS, AND WHAT IT IS NOT. This file called itself a
# "reproducibility Dockerfile (v2.1.0)" and then built from the moving tip of
# `main`, so two builds a week apart produced different packages. It has not
# been touched since the commit that added it: the package is now 0.9.0, the
# version it labelled itself with never existed as a release, and its R 4.4.1
# base matches no leg of CI (which runs release, devel and oldrel-1).
#
# The CRAN snapshot below IS pinned, and that half was always right. What was
# missing is a pinned edaphos: pass EDAPHOS_REF a commit SHA or a tag, and the
# build is reproducible; leave it at `main` and it is a convenience image, not
# a reproducibility artefact. The default is `main` because there is no tag
# for the current version -- see STATUS.md's release-ledger findings -- and a
# default that lies about being pinned would be worse than one that says so.
#
# Base: rocker/geospatial (includes R, RStudio Server, terra, sf,
# gdal, proj, geos, netcdf, udunits2, pandoc). We layer on top the
# heavier torch runtime + all Suggests needed to run every vignette
# without network access.
#
# Build (reproducible -- pin the ref):
#   docker build --build-arg EDAPHOS_REF=<commit-sha> -t edaphos:<sha> .
#
# Build (convenience -- tracks main, NOT reproducible):
#   docker build -t edaphos:dev .
#
# Run (interactive RStudio):
#   docker run --rm -p 8787:8787 \
#     -e PASSWORD=edaphos \
#     -v $(pwd):/home/rstudio/project \
#     edaphos:dev
#   # Visit http://localhost:8787  (user: rstudio, pw: edaphos)
#
# Run (batch R session):
#   docker run --rm -v $(pwd):/work -w /work edaphos:dev \
#     Rscript -e 'library(edaphos); sessionInfo()'

# R 4.6.1, matching what CI's `release` legs and the committed check.log ran
# on. The previous 4.4.1 appeared in no CI leg, so the image tested a
# configuration nothing else did.
FROM rocker/geospatial:4.6.1

# Declared before the LABEL that interpolates it: an ARG used above its own
# declaration expands to empty, which would have stamped every image with a
# blank revision.
ARG EDAPHOS_REF=main

LABEL maintainer="Hugo Rodrigues <rodrigues.machado.hugo@gmail.com>" \
      org.opencontainers.image.title="edaphos" \
      org.opencontainers.image.description="Disruptive algorithms for Digital Soil Mapping" \
      org.opencontainers.image.source="https://github.com/HugoMachadoRodrigues/edaphos" \
      org.opencontainers.image.revision="${EDAPHOS_REF}" \
      org.opencontainers.image.licenses="MIT"

# System deps for torch (libtorch fetch) + pdf rendering for vignette
# builds that emit LaTeX. poppler-utils lets Claude/PDF tools read
# published papers inside the container.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libxml2-dev \
    poppler-utils \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ── CRAN deps (pin to the date of the edaphos v2.1.0 release so every
#    rebuild is byte-reproducible) ─────────────────────────────────────
# THE DISTRO CODENAME IS DERIVED, NOT TYPED. This URL hard-coded `jammy`,
# which was right for the old 4.4.1 base and is a silent trap on any other:
# a mismatched codename does not error, it just serves no binaries and the
# build falls back to compiling everything from source. Reading it from
# /etc/os-release keeps the URL correct across base-image bumps.
#
# The DATE stays pinned -- that is the half of this file that was always
# right. It is a CRAN snapshot, so the dependency set is fixed no matter when
# the image is built. (The comment used to call it "the date of the edaphos
# v2.1.0 release"; there was no such release. It is simply the snapshot this
# image is pinned to.)
ARG CRAN_SNAPSHOT=2026-04-23
RUN . /etc/os-release && \
    echo "R_CRAN_WEB=https://packagemanager.posit.co/cran/__linux__/${VERSION_CODENAME}/${CRAN_SNAPSHOT}" \
      >> /usr/local/lib/R/etc/Renviron.site && \
    echo "options(repos = c(CRAN = Sys.getenv('R_CRAN_WEB')))" \
      >> /usr/local/lib/R/etc/Rprofile.site

RUN R -e "install.packages(c( \
  'remotes', 'devtools', 'pkgdown', 'covr', \
  'dplyr', 'tidyr', 'ggplot2', 'scales', 'patchwork', \
  'RColorBrewer', 'ggridges', 'ggnewscale', 'DiagrammeR', \
  'knitr', 'rmarkdown', 'jsonlite', 'httr2', 'digest', \
  'dagitty', 'ggdag', 'bnlearn', 'dbarts', 'igraph', \
  'ranger', 'clhs', 'deSolve', 'stringdist', 'abind', \
  'fmsb', 'shiny', 'shinyjs', 'bslib', 'DT', \
  'ontologyIndex', 'gstat', 'aqp', 'geodata', 'sp' \
  ), repos = Sys.getenv('R_CRAN_WEB'))"

# ── torch runtime ────────────────────────────────────────────────────
RUN R -e "install.packages('torch', repos = Sys.getenv('R_CRAN_WEB')); \
          torch::install_torch(timeout = 600)"

# Optional reticulate + Python stack for the Qiskit bridge (Pilar 6).
# Skip by default to keep the image small; uncomment if you need VQE.
# RUN R -e "install.packages('reticulate', repos = Sys.getenv('R_CRAN_WEB'))"
# RUN pip install qiskit qiskit-aer qiskit-nature pyscf

# ── Install the edaphos package itself ───────────────────────────────
# EDAPHOS_REF is declared near the top so the LABEL can record it. A moving
# default: pass a commit SHA or tag for a reproducible image; the label carries
# whichever was used, so an image can always say what it contains even when
# that is "the tip of main on some day".
RUN R -e "remotes::install_github('HugoMachadoRodrigues/edaphos', \
            ref = '${EDAPHOS_REF}', \
            dependencies = TRUE, \
            upgrade = 'never')"

# ── Pre-download the v1 Cerrado encoder so offline demos work ────────
# NOT wrapped in try(). It was, which meant a failed download produced an
# image that builds cleanly, claims offline demos work, and does not have the
# weights. A build that cannot fetch the encoder should fail while someone is
# watching.
RUN R -e "edaphos::foundation_weights_download('edaphos-cerrado-moco-v1', \
                                                 verbose = TRUE)"

WORKDIR /home/rstudio/project
EXPOSE 8787

CMD ["/init"]
