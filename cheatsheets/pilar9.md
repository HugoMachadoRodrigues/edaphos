# Pilar 9 — Diffusion Models (DDPM)

Conditional Denoising Diffusion Probabilistic Models for soil-map
patch generation.  Cosine schedule (Nichol & Dhariwal 2021), pure-R
ELM-style or torch-autograd backend.

## Core API

```r
# Build a (n_patches, H, W) stack
patches <- array(my_data, dim = c(n_patches, H, W))

# Train (R backend, ELM-style head; v3.2.0 batched training)
fit <- dm_fit(
  stack        = patches,
  conditioning = my_cond_matrix,    # optional (n_patches, cond_dim)
  T = 50L, epochs = 100L,
  hidden = 32L, lr = 0.01,
  backend = "r",                     # or "torch"
  seed = 1L
)

# Posterior sampling (n_samples maps)
samps <- dm_sample(fit, n_samples = 16L,
                     conditioning = matrix(my_query_cond, 16L, cond_dim),
                     seed = 1L)
# samps: (n_samples, H, W) array

# Cosine schedule helper
sched <- dm_cosine_schedule(T = 50L)
sched$alphabar; sched$sqrt_alphabar
```

## v3.0.0 bridge: `al_query_diffusion()` (Pilar 9 × Pilar 5)

Posterior-spread AL: ranks candidate cells by `posterior_sd`
(or `posterior_sd * |posterior_mean|`) over `n_samples` DDPM draws.

## Key references

* Ho, Jain & Abbeel (2020) DDPM.
* Nichol & Dhariwal (2021) — improved cosine schedule.

## See also

* `cheatsheets/pilar5.md` — AL-flavoured P9 query.
