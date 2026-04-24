# Pilar 9 -- Diffusion models for generative soil maps (v2.5.0 scope).
#
# Status: SCAFFOLD.
#
# Why a pillar?
# -------------
# All the current pillars output POINT predictions (optionally with
# uncertainty bands).  None of them can sample ENTIRE plausible soil
# maps conditional on covariates + sparse observations.  Denoising
# diffusion probabilistic models (DDPMs, Ho et al. 2020; Song & Ermon
# 2019) do exactly that -- they sample from p(map | covariates,
# observed_points).  For Digital Soil Mapping this is novel: no
# published work uses diffusion models on soil maps.  Pilar 9 closes
# that gap.
#
# The natural architecture for our setting is a 2-D conditional DDPM
# with:
#   - covariate channels as conditioning input (concat to every
#     intermediate activation)
#   - observation mask + observed values as an extra hard-constraint
#     channel (classifier-free guidance)
#   - U-Net backbone with time-embedding injection at each level
#
# Sampling from the trained model gives:
#   (a) the CONDITIONAL MEAN map (equivalent to kriging mean but
#       non-Gaussian),
#   (b) the CONDITIONAL MARGINAL SD (per-pixel uncertainty),
#   (c) FULL JOINT SAMPLES (critical for downstream tasks like
#       catchment-scale uncertainty propagation).
#
# TODO (v2.5.0)
# -------------
#  - [ ] `dm_unet_module()`: conditional U-Net, 4 levels, time
#        embedding via sinusoidal + MLP.
#  - [ ] `dm_fit(stack, obs, epochs, T, beta_schedule, ...)` using
#        cosine beta schedule (Nichol & Dhariwal 2021).
#  - [ ] `dm_sample(fit, n_samples, conditioning, guidance_scale)`
#        implementing DDPM ancestral sampling + classifier-free
#        guidance for masked observations.
#  - [ ] `dm_posterior(fit, n_samples)` -> `edaphos_posterior` with
#        `query_type = "map"`.
#  - [ ] Benchmark: DDPM vs kriging vs ranger on Cerrado SOC maps.
#  - [ ] `vignettes/pilar9-diffusion-models.Rmd`

#' Train a conditional DDPM on a covariate raster stack (scaffold,
#' v2.5.0)
#'
#' @description **Not yet implemented.**  Scheduled for v2.5.0.
#' @param stack A `terra::SpatRaster` of covariates (C channels).
#' @param obs Data frame with columns `row`, `col`, `value` for the
#'   labelled points.
#' @param epochs Integer; training epochs.
#' @param T Integer; diffusion timesteps.
#' @param ... Additional torch / optimisation arguments.
#' @return (When implemented) An `edaphos_dm_fit` S3 object.
#' @export
dm_fit <- function(stack, obs, epochs = 100L, T = 1000L, ...) {
  stop(
    "`dm_fit()` is scheduled for edaphos v2.5.0 (Pilar 9 -- Diffusion\n",
    "models for generative soil maps).  The API is fixed; the body\n",
    "will wire the conditional U-Net + ancestral sampler in v2.5.0.",
    call. = FALSE
  )
}

#' Sample soil maps from a trained diffusion model (scaffold, v2.5.0)
#'
#' @description **Not yet implemented.**  Scheduled for v2.5.0.
#' @param fit An `edaphos_dm_fit` object.
#' @param n_samples Integer; number of independent map draws.
#' @param conditioning Optional covariate stack + observation mask.
#' @param guidance_scale Numeric; classifier-free guidance strength.
#' @export
dm_sample <- function(fit, n_samples = 4L,
                        conditioning = NULL, guidance_scale = 1) {
  stop("`dm_sample()` is scheduled for edaphos v2.5.0 (Pilar 9).",
        call. = FALSE)
}
