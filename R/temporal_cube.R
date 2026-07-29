#' Generate a synthetic 4D soil-dynamics cube (Pillar 3 helper)
#'
#' Builds a small spatio-temporal cube with realistic-looking dynamics
#' of Soil Organic Carbon (SOC) driven by monthly precipitation over a
#' static elevation field. The governing update is a minimalist
#' mass-balance
#'
#' \deqn{
#'   \mathrm{SOC}_{t+1} = \mathrm{SOC}_t +
#'     k_{\text{in}}\, P_t -
#'     k_{\text{out}}\,\mathrm{SOC}_t\, P_t / \bar{P} +
#'     \varepsilon
#' }
#'
#' with `k_in, k_out` small, \eqn{P_t} the monthly precipitation, and
#' \eqn{\bar P} the long-term mean. Precipitation itself is a sinusoidal
#' seasonal cycle modulated by a west-east gradient so the cube shows
#' both temporal memory and spatial heterogeneity.
#'
#' Use the resulting object to train [temporal_convlstm_fit()] and
#' forecast forward with [temporal_convlstm_rollout()] in the Pillar 3
#' vignette.
#'
#' @param H,W Integer, spatial grid size.
#' @param T_total Integer, total number of months.
#' @param seed Integer, RNG seed for reproducibility.
#' @param k_in,k_out Numeric rate coefficients of the input and output
#'   terms of the mass balance. The defaults do **not** reach a steady
#'   state: with `k_in` above `k_out` the series accumulates for as long
#'   as it is run. Measured at the shipped defaults, the grid mean
#'   starts near 20 g/kg and reaches 30.6 at `T_total = 6`, 52.4 at the
#'   default 18, and 103.7 at 60, with maxima of 38.3, 65.6 and 121.4 —
#'   so the cube leaves a plausible topsoil range somewhere between
#'   `T_total` 6 and 12, and is well outside it by the default. This
#'   documentation previously claimed the defaults kept SOC inside
#'   10-50 g/kg, which is true only up to `T_total = 6`.
#'
#'   That is a property of a deliberately simple generator, not a bug to
#'   route around: the cube exists to give ConvLSTM a reproducible
#'   space-time signal with known dynamics, and a monotone trend is a
#'   legitimate thing to learn. But do not read its values as SOC
#'   concentrations, and set `k_out` closer to `k_in` if you want a
#'   series that levels off.
#' @param noise Numeric, standard deviation of Gaussian process noise
#'   on the SOC evolution (per pixel, per month).
#'
#' @return A list with elements
#' \describe{
#'   \item{elev}{Numeric matrix `H x W`.}
#'   \item{precip}{Numeric array `T x H x W`.}
#'   \item{soc}{Numeric array `T x H x W`.}
#' }
#' @export
#' @examples
#' cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 12, seed = 1)
#' dim(cube$soc)  # 12 x 8 x 8
temporal_synth_soc_cube <- function(H = 16L, W = 16L, T_total = 18L,
                                    seed = 1L,
                                    k_in = 0.03, k_out = 0.015,
                                    noise = 0.2) {
  set.seed(seed)
  H <- as.integer(H); W <- as.integer(W); T_total <- as.integer(T_total)

  yy <- seq(-1, 1, length.out = H)
  xx <- seq(-1, 1, length.out = W)
  xg <- matrix(xx, H, W, byrow = TRUE)
  yg <- matrix(yy, H, W, byrow = FALSE)

  elev <- 100 + 40 * (xg + yg) + 15 * sin(xg * 4) +
          matrix(stats::rnorm(H * W, 0, 5), H, W)

  # West-east precipitation gradient (east wetter), seasonal cycle peaks
  # in month ~5 (austral autumn -> winter wet season).
  months   <- seq_len(T_total)
  seasonal <- 90 + 80 * sin((months - 3) * 2 * pi / 12)
  spatial_wet <- 0.6 + 0.6 * (xg + 1) / 2

  precip <- array(0, dim = c(T_total, H, W))
  for (t in seq_len(T_total)) {
    precip[t, , ] <- pmax(0,
      seasonal[t] * spatial_wet +
        matrix(stats::rnorm(H * W, 0, 8), H, W)
    )
  }
  p_bar <- mean(precip)

  soc <- array(0, dim = c(T_total, H, W))
  soc[1, , ] <- pmax(8,
    20 + 0.03 * (elev - 100) +
      matrix(stats::rnorm(H * W, 0, 1), H, W)
  )
  for (t in 2:T_total) {
    decomp <- k_out * soc[t - 1L, , ] * precip[t - 1L, , ] / p_bar
    input  <- k_in  * precip[t - 1L, , ]
    soc[t, , ] <- pmax(5,
      soc[t - 1L, , ] + input - decomp +
        matrix(stats::rnorm(H * W, 0, noise), H, W)
    )
  }

  list(elev = elev, precip = precip, soc = soc)
}

#' Assemble a 4D input tensor-ready array from a synthetic cube
#'
#' Packages [temporal_synth_soc_cube()]'s output into the
#' `(batch, T, C, H, W)` array shape expected by
#' [temporal_convlstm_fit()], with two channels:
#' \enumerate{
#'   \item static elevation (broadcast along time);
#'   \item dynamic precipitation.
#' }
#' Also returns the target SOC array in `(batch, T, H, W)` form.
#'
#' @param cube List returned by [temporal_synth_soc_cube()].
#' @param t_slice Optional integer vector with time indices to include
#'   (default = all months). Useful to split train / forecast windows.
#'
#' @return A list with `sequence` `(1, T', 2, H, W)`, `target`
#'   `(1, T', H, W)`, and `scaling` — the six constants (`soc_mu`,
#'   `soc_sd`, `prec_mu`, `prec_sd`, `elev_mu`, `elev_sd`) needed to
#'   map z-scored predictions back to g/kg. `scaling` is always
#'   computed from the whole `cube`, never from `t_slice`.
#' @export
#' @examples
#' cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)
#'
#' # The cube is a LIST of three fields of different rank: a static
#' # H x W elevation matrix and two T x H x W stacks. It is not an
#' # array, and it is not stacked in (T, C, H, W) order yet.
#' vapply(cube, function(z) paste(dim(z), collapse = " x "), "")
#' #        elev      precip         soc
#' #     "8 x 8" "6 x 8 x 8" "6 x 8 x 8"
#'
#' tt <- temporal_cube_to_tensor(cube)
#' dim(tt$sequence)   # 1 6 2 8 8 = (batch, T, channel, H, W)
#' dim(tt$target)     # 1 6 8 8   = (batch, T, H, W)
#'
#' # Channel 1 is elevation broadcast along time, channel 2 is the
#' # monthly precipitation. A static covariate therefore costs T
#' # identical copies of the same map.
#' identical(tt$sequence[1, 1, 1, , ], tt$sequence[1, 6, 1, , ])  # TRUE
#' identical(tt$sequence[1, 1, 2, , ], tt$sequence[1, 6, 2, , ])  # FALSE
#'
#' # Trap: `t_slice` subsets the sequence but NOT the standardisation.
#' # mu and sd always come from the whole cube, so a training window
#' # is not centred -- months 1:4 sit 0.55 sd below the six-month mean.
#' train <- temporal_cube_to_tensor(cube, t_slice = 1:4)
#' round(c(slice = mean(train$target), full = mean(tt$target)), 4)
#' #   slice    full
#' # -0.5519  0.0000
#' identical(train$scaling, tt$scaling)   # TRUE
#'
#' # That shared scaling is exactly what temporal_convlstm_rollout()
#' # needs to compare a train window with a forecast window. It also
#' # means the forecast months leak their mean and sd into the
#' # training normalisation; an operational forecast must standardise
#' # on history only.
#'
#' # `scaling` is the only route back to g/kg, and it is exact.
#' soc3 <- tt$target[1, 3, , ] * tt$scaling$soc_sd + tt$scaling$soc_mu
#' max(abs(soc3 - cube$soc[3, , ]))       # 0
#' round(unlist(tt$scaling[c("soc_mu", "soc_sd")]), 3)
#' # soc_mu soc_sd
#' # 23.782  4.313
temporal_cube_to_tensor <- function(cube, t_slice = NULL) {
  stopifnot(is.list(cube), all(c("elev", "precip", "soc") %in% names(cube)))
  T_total <- dim(cube$precip)[1L]
  if (is.null(t_slice)) t_slice <- seq_len(T_total)
  t_slice <- as.integer(t_slice)
  T_ <- length(t_slice)
  H <- nrow(cube$elev); W <- ncol(cube$elev)

  # Broadcast elev across time
  elev_t <- array(rep(cube$elev, each = 1L), dim = c(1L, H, W))
  # Standardise for training stability
  elev_z <- (cube$elev - mean(cube$elev)) / max(stats::sd(cube$elev), 1e-3)
  prec_mu <- mean(cube$precip); prec_sd <- max(stats::sd(cube$precip), 1e-3)
  soc_mu  <- mean(cube$soc);    soc_sd  <- max(stats::sd(cube$soc),    1e-3)

  seq_arr <- array(0, dim = c(1L, T_, 2L, H, W))
  tgt_arr <- array(0, dim = c(1L, T_, H, W))
  for (i in seq_along(t_slice)) {
    t <- t_slice[i]
    seq_arr[1L, i, 1L, , ] <- elev_z
    seq_arr[1L, i, 2L, , ] <- (cube$precip[t, , ] - prec_mu) / prec_sd
    tgt_arr[1L, i, , ]     <- (cube$soc[t, , ]    - soc_mu)  / soc_sd
  }
  list(
    sequence = seq_arr,
    target   = tgt_arr,
    scaling  = list(soc_mu = soc_mu, soc_sd = soc_sd,
                    prec_mu = prec_mu, prec_sd = prec_sd,
                    elev_mu = mean(cube$elev),
                    elev_sd = stats::sd(cube$elev))
  )
}
