# Load a pretrained encoder into an `edaphos_foundation_moco` wrapper

Restores a pretrained MoCo v2 encoder from a `.pt` state-dict file (or
by name from the published registry) into an in-memory
`edaphos_foundation_moco` object that is **shape-compatible** with the
output of
[`foundation_moco_pretrain_tiles()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain_tiles.md).
The restored object is ready to feed into
[`foundation_moco_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed.md),
[`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md)
or
[`foundation_fit_regressor()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_regressor.md)
without any additional plumbing.

## Usage

``` r
foundation_weights_load(
  source,
  n_channels = NULL,
  feature_dim = NULL,
  proj_dim = NULL,
  cache_dir = NULL,
  overwrite = FALSE,
  verbose = FALSE
)
```

## Arguments

- source:

  Either a character name registered in
  [`foundation_weights_list()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_list.md)
  — in which case the encoder is downloaded (cached) via
  [`foundation_weights_download()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_download.md)
  — or a path to a local `.pt` file. The local-path branch is taken
  whenever `file.exists(source)`, and there is then no registry row to
  consult, so `n_channels`, `feature_dim` and `proj_dim` must all be
  supplied; omitting any of them is an error.

- n_channels, feature_dim, proj_dim:

  Integers. **Required** when `source` is a local path, where they must
  describe the shape the `.pt` file was saved from — a mismatch surfaces
  as a tensor-size error from `load_state_dict()`, not as a silent
  reshape. Optional when `source` is a registry name, in which case each
  unsupplied value defaults to the registry row.

- cache_dir, overwrite, verbose:

  Forwarded to
  [`foundation_weights_download()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_download.md)
  when `source` is a registry name.

## Value

An `edaphos_foundation_moco` object with a populated `$encoder_q` (the
query encoder; the momentum encoder is not restored because it is only
needed during training).

## Examples

``` r
# The registry route needs a network download from Zenodo, so it is
# not run here. It fills the three shapes from the registry row, so
# they are the one thing you do not have to pass.
if (FALSE) { # \dontrun{
  moco <- foundation_weights_load("edaphos-cerrado-moco-v1")
  # v1 expects 31 channels in the registry's band order; `patches`
  # must be a numeric (N, 31, 16, 16) array, standardised over your
  # own AoI (v1's training mean / sd are unrecoverable — see
  # foundation_weights_list()$norm_stats_status).
  emb <- foundation_moco_embed(moco, patches)
} # }

# The local-path route is offline, and is also how you reload your
# own encoders. It is shown here end to end on a throwaway model.
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {

# A 3-step fit on random noise. This is plumbing, not a model: it
# has learned nothing and its embeddings are meaningless. A usable
# encoder needs a real tile corpus and thousands of steps — see
# foundation_moco_pretrain_tiles().
set.seed(42)
patches <- array(stats::rnorm(24L * 5L * 8L * 8L), dim = c(24L, 5L, 8L, 8L))
set.seed(1)
fit <- foundation_moco_pretrain(patches, feature_dim = 16L, proj_dim = 8L,
                                batch_size = 8L, epochs = 3L, seed = 1L)
pt <- tempfile(fileext = ".pt")
torch::torch_save(fit$encoder_q$state_dict(), pt)

# A `.pt` is a bare state dict: it fixes the tensor sizes but records
# nothing about what they mean, so all three shapes are mandatory here
# and must match what was saved.
moco <- foundation_weights_load(pt, n_channels = 5L,
                                feature_dim = 16L, proj_dim = 8L)
print(c(n_channels = moco$n_channels, feature_dim = moco$feature_dim,
        proj_dim = moco$proj_dim))

# Only encoder_q is restored, and it comes back in eval() mode, so the
# reloaded copy reproduces the source object's embeddings exactly.
print(all.equal(foundation_moco_embed(moco, patches),
                foundation_moco_embed(fit, patches)))

# Omitting the shapes is a refusal, not a default. Note that this is
# what `foundation_weights_load(loc$path)` would hit after a
# foundation_weights_download() — pass loc$entry's shapes, or skip
# the download and load by name.
print(tryCatch(foundation_weights_load(pt), error = conditionMessage))
unlink(pt)
}
```
