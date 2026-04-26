# Pilar 4 — Contrastive Raster Embeddings as Active-Learning Covariates

## Abstract

Self-Supervised Learning (SSL) has emerged as the dominant
representation-learning paradigm in computer vision ([Chen et al.
2020](#ref-Chen2020simclr); [He et al. 2020](#ref-He2020moco); [Oord,
Li, and Vinyals 2018](#ref-Oord2018cpc)) and is increasingly applied to
remote sensing ([Jean et al. 2019](#ref-Jean2019tile2vec); [Reichstein
et al. 2019](#ref-ReichsteinDL2019)). The **Pillar 4** of `edaphos`
ships a minimal SimCLR-style pipeline ([Chen et al.
2020](#ref-Chen2020simclr)) that pre-trains a small raster encoder on
unlabelled covariate patches; the resulting per-pixel embeddings are
then used as additional covariates inside the Pillar 5 Active Learning
loop on `br_cerrado`. We report a head-to-head comparison of the
identical AL policy with and without the learned features.

## 1. Contrastive representation learning

Given a mini-batch $\{\mathbf{x}_{i}\}_{i = 1}^{B}$ of raster patches,
SimCLR draws two independent stochastic augmentations
${\widetilde{\mathbf{x}}}_{i}^{(1)},{\widetilde{\mathbf{x}}}_{i}^{(2)}$
of each patch, encodes them with a shared CNN $f_{\theta}$ and a
projection head $g_{\phi}$, and minimises the normalised
temperature-scaled cross-entropy (NT-Xent) loss ([Chen et al.
2020](#ref-Chen2020simclr)):
$$\mathcal{L}_{\text{NT-Xent}}\; = \; - \frac{1}{2B}\sum\limits_{i = 1}^{B}\sum\limits_{v \in \{ 1,2\}}\log\frac{\exp\left( {sim}\left( \mathbf{z}_{i}^{(v)},\mathbf{z}_{i}^{(v^{\prime})} \right)/\tau \right)}{\sum\limits_{k \neq {(i,v)}}\exp\left( {sim}\left( \mathbf{z}_{i}^{(v)},\mathbf{z}_{k} \right)/\tau \right)},$$
where
$\mathbf{z} = g_{\phi}\left( f_{\theta}\left( \widetilde{\mathbf{x}} \right) \right)$,
${sim}( \cdot , \cdot )$ is cosine similarity and $\tau$ is the
temperature. After pre-training, the projection head is discarded and
the *backbone* feature vector $f_{\theta}(\mathbf{x})$ is used as the
reusable representation.

## 2. Data preparation

Each of the 2025 pixels of `br_cerrado` is made the centre of a
$7 \times 7 \times 5$ patch with five normalised channels (elevation,
slope, TWI, mean annual precipitation, NDVI). Reflection padding
preserves the original grid size.

``` r
library(edaphos)
.torch_ok <- requireNamespace("torch", quietly = TRUE) &&
             isTRUE(tryCatch(torch::torch_is_installed(),
                             error = function(e) FALSE))
if (!.torch_ok) {
  knitr::knit_exit(
    "torch runtime (libtorch) not available — skipping vignette."
  )
}
data(br_cerrado, package = "edaphos")

covs_base <- c("elev", "slope", "twi", "map_mm", "ndvi")
H <- length(unique(br_cerrado$y))
W <- length(unique(br_cerrado$x))
stopifnot(H * W == nrow(br_cerrado))
c(H = H, W = W)
#>  H  W 
#> 45 45
```

torch runtime (libtorch) not available — skipping vignette.

Chen, T., S. Kornblith, M. Norouzi, and G. Hinton. 2020. “A Simple
Framework for Contrastive Learning of Visual Representations.” In
*Proceedings of the 37th International Conference on Machine Learning*,
119:1597–607.

He, K., H. Fan, Y. Wu, S. Xie, and R. Girshick. 2020. “Momentum Contrast
for Unsupervised Visual Representation Learning.” In *IEEE/CVF
Conference on Computer Vision and Pattern Recognition*, 9729–38.

Jean, N., S. Wang, A. Samar, G. Azzari, D. Lobell, and S. Ermon. 2019.
“Tile2Vec: Unsupervised Representation Learning for Spatially
Distributed Data.” In *Proceedings of the AAAI Conference on Artificial
Intelligence*, 33:3967–74.
<https://doi.org/10.1609/aaai.v33i01.33013967>.

Oord, A. van den, Y. Li, and O. Vinyals. 2018. “Representation Learning
with Contrastive Predictive Coding.” *arXiv:1807.03748*.

Reichstein, M., G. Camps-Valls, B. Stevens, M. Jung, J. Denzler, N.
Carvalhais, and Prabhat. 2019. “Deep Learning and Process Understanding
for Data-Driven Earth System Science.” *Nature* 566: 195–204.
<https://doi.org/10.1038/s41586-019-0912-1>.
