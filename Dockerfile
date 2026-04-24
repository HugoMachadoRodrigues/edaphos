# edaphos reproducibility Dockerfile  (v2.1.0)
#
# Base: rocker/geospatial (includes R, RStudio Server, terra, sf,
# gdal, proj, geos, netcdf, udunits2, pandoc). We layer on top the
# heavier torch runtime + all Suggests needed to run every vignette
# without network access.
#
# Build:
#   docker build -t edaphos:2.1.0 .
#
# Run (interactive RStudio):
#   docker run --rm -p 8787:8787 \
#     -e PASSWORD=edaphos \
#     -v $(pwd):/home/rstudio/project \
#     edaphos:2.1.0
#   # Visit http://localhost:8787  (user: rstudio, pw: edaphos)
#
# Run (batch R session):
#   docker run --rm -v $(pwd):/work -w /work edaphos:2.1.0 \
#     Rscript -e 'library(edaphos); sessionInfo()'

FROM rocker/geospatial:4.4.1

LABEL maintainer="Hugo Rodrigues <rodrigues.machado.hugo@gmail.com>" \
      org.opencontainers.image.title="edaphos" \
      org.opencontainers.image.description="Disruptive algorithms for Digital Soil Mapping" \
      org.opencontainers.image.source="https://github.com/HugoMachadoRodrigues/edaphos" \
      org.opencontainers.image.version="2.1.0" \
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
ENV R_CRAN_WEB="https://packagemanager.posit.co/cran/__linux__/jammy/2026-04-23"

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
ARG EDAPHOS_REF=main
RUN R -e "remotes::install_github('HugoMachadoRodrigues/edaphos', \
            ref = '${EDAPHOS_REF}', \
            dependencies = TRUE, \
            upgrade = 'never')"

# ── Pre-download the v1 Cerrado encoder so offline demos work ────────
RUN R -e "try({ \
  edaphos::foundation_weights_download('edaphos-cerrado-moco-v1', \
                                         verbose = TRUE) \
  })"

WORKDIR /home/rstudio/project
EXPOSE 8787

CMD ["/init"]
