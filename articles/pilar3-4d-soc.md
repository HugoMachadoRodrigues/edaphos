# Pilar 3 — 4D Pedometry: Stacked ConvLSTM Forecasts of SOC

## Abstract

Most digital soil maps report a time-invariant property field, which
ignores the evidence that topsoil Soil Organic Carbon (SOC) responds
measurably to climate forcing on monthly to annual scales ([Lehmann and
Kleber 2015](#ref-Lehmann2015); [Minasny et al.
2017](#ref-Minasny2017)). The **Pillar 3** of `edaphos` addresses that
gap with a stacked Convolutional LSTM ([Shi et al. 2015](#ref-Shi2015))
trained in sequence-to-sequence mode plus a multi-step rollout wrapper
for forward forecasting under known future drivers. A physics-informed
mass-balance regulariser optionally penalises violations of an
analytical SOC kinetic, fusing Pillar 2 into Pillar 3 ([Raissi,
Perdikaris, and Karniadakis 2019](#ref-Raissi2019); [Reichstein et al.
2019](#ref-ReichsteinDL2019)).

## 1. From 3D to 4D pedometry

Let $y(\mathbf{s},t)$ denote a topsoil property at location $\mathbf{s}$
and time $t \in \{ 1,\ldots,T\}$. Traditional DSM ([McBratney, Mendonça
Santos, and Minasny 2003](#ref-McBratney2003)) estimates
$y(\mathbf{s}) = \bar{y}(\mathbf{s}, \cdot )$ by collapsing over time. A
4D model retains the time dimension and predicts the full
spatio-temporal field
$y(\mathbf{s},t) \mid \mathbf{X}\left( \mathbf{s},t^{\prime} \leq t \right)$,
where $\mathbf{X}$ is the driver stack (climate, vegetation, static
topography).

The **Convolutional LSTM cell** ([Shi et al. 2015](#ref-Shi2015))
operationalises spatial memory: at each time step the hidden state
$\mathbf{H}_{t}$ and the cell state $\mathbf{C}_{t}$ are tensors of the
same spatial size as the input, so memory propagates *with* its
location: $$\begin{aligned}
\mathbf{i}_{t} & {= \sigma\left( W_{xi}*\mathbf{X}_{t} + W_{hi}*\mathbf{H}_{t - 1} + b_{i} \right),} \\
\mathbf{f}_{t} & {= \sigma\left( W_{xf}*\mathbf{X}_{t} + W_{hf}*\mathbf{H}_{t - 1} + b_{f} \right),} \\
\mathbf{g}_{t} & {= \tanh\left( W_{xg}*\mathbf{X}_{t} + W_{hg}*\mathbf{H}_{t - 1} + b_{g} \right),} \\
\mathbf{o}_{t} & {= \sigma\left( W_{xo}*\mathbf{X}_{t} + W_{ho}*\mathbf{H}_{t - 1} + b_{o} \right),} \\
\mathbf{C}_{t} & {= \mathbf{f}_{t} \odot \mathbf{C}_{t - 1} + \mathbf{i}_{t} \odot \mathbf{g}_{t},} \\
\mathbf{H}_{t} & {= \mathbf{o}_{t} \odot \tanh\left( \mathbf{C}_{t} \right),}
\end{aligned}$$ with `*` a 2-D convolution and $\odot$ the Hadamard
product. Stacking $L$ cells feeds $\mathbf{H}_{t}^{(\ell)}$ as the input
to layer $\ell + 1$, yielding a hierarchy of spatial receptive fields.

## 2. Synthetic SOC dynamics cube

To keep the vignette self-contained and reproducible,
\[[`temporal_synth_soc_cube()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_synth_soc_cube.md)\]\[temporal_synth_soc_cube\]
integrates the driver-response kinetic
$${SOC}_{t + 1} = {SOC}_{t} + k_{\text{in}}P_{t} - k_{\text{out}}\,{SOC}_{t}\, P_{t}/\bar{P} + \varepsilon,$$
with $P_{t}$ the monthly precipitation field and $\bar{P}$ its long-term
mean. The numerator $k_{\text{in}}P_{t}$ models organic input
proportional to wet-season biomass turnover; the denominator
$k_{\text{out}}{SOC}\, P/\bar{P}$ captures humidity-modulated
decomposition ([Lehmann and Kleber 2015](#ref-Lehmann2015); [Minasny et
al. 2017](#ref-Minasny2017)).

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
cube <- temporal_synth_soc_cube(H = 12L, W = 12L, T_total = 18L,
                                seed = 7L)
str(cube)
#> List of 3
#>  $ elev  : num [1:12, 1:12] 42.8 32.6 42.4 51.1 55.6 ...
#>  $ precip: num [1:18, 1:12, 1:12] 16.3 28.7 53.2 71.1 87.7 ...
#>  $ soc   : num [1:18, 1:12, 1:12] 18.9 19.4 20.1 21.3 23.3 ...
```

torch runtime (libtorch) not available — skipping vignette.

Lehmann, J., and M. Kleber. 2015. “The Contentious Nature of Soil
Organic Matter.” *Nature* 528: 60–68.
<https://doi.org/10.1038/nature16069>.

McBratney, A. B., M. L. Mendonça Santos, and B. Minasny. 2003. “On
Digital Soil Mapping.” *Geoderma* 117 (1-2): 3–52.
<https://doi.org/10.1016/S0016-7061(03)00223-4>.

Minasny, B., B. P. Malone, A. B. McBratney, D. A. Angers, D. Arrouays,
A. Chambers, V. Chaplot, et al. 2017. “Soil Carbon 4 Per Mille.”
*Geoderma* 292: 59–86. <https://doi.org/10.1016/j.geoderma.2017.01.002>.

Raissi, M., P. Perdikaris, and G. E. Karniadakis. 2019.
“Physics-Informed Neural Networks: A Deep Learning Framework for Solving
Forward and Inverse Problems Involving Nonlinear Partial Differential
Equations.” *Journal of Computational Physics* 378: 686–707.
<https://doi.org/10.1016/j.jcp.2018.10.045>.

Reichstein, M., G. Camps-Valls, B. Stevens, M. Jung, J. Denzler, N.
Carvalhais, and Prabhat. 2019. “Deep Learning and Process Understanding
for Data-Driven Earth System Science.” *Nature* 566: 195–204.
<https://doi.org/10.1038/s41586-019-0912-1>.

Shi, X., Z. Chen, H. Wang, D.-Y. Yeung, W.-K. Wong, and W.-C. Woo. 2015.
“Convolutional LSTM Network: A Machine Learning Approach for
Precipitation Nowcasting.” In *Advances in Neural Information Processing
Systems*, 28:802–10.
