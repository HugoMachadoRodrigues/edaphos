#!/usr/bin/env Rscript
# =============================================================================
# Figures for the edaphos PLOS manuscript.
#
# One shared visual system, one file per figure, written at 300 dpi as TIFF
# (PLOS's required format) and PNG (for the Word build). Every figure is drawn
# from data distributed with the package or from public boundaries; nothing is
# mocked up.
#
#   Rscript paper/assets/figures.R
# =============================================================================
suppressPackageStartupMessages({
  library(ggplot2); library(sf); library(patchwork); library(scales)
})
ROOT <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
OUT <- file.path(ROOT, "paper", "figures"); dir.create(OUT, showWarnings = FALSE)
suppressMessages(pkgload::load_all(ROOT, quiet = TRUE))
ex <- function(f) readRDS(system.file("extdata", f, package = "edaphos"))

# ---- shared visual system ---------------------------------------------------
PAL <- c(
  soc      = "#4B2E15",   # soil brown, for carbon
  accent   = "#C1440E",   # burnt orange, for the thing being argued
  cool     = "#1B6CA8",   # blue, for the reference/baseline
  muted    = "#8A8F98",
  good     = "#2E7D5B",
  bad      = "#A8322D"
)
# a colour-blind-safe qualitative ramp for the six benchmark methods
METHOD_PAL <- c("#1B6CA8", "#2E7D5B", "#C1440E", "#7B5AA6", "#B8860B", "#8A8F98")

theme_edaphos <- function(base = 9) {
  theme_minimal(base_size = base, base_family = "") +
    theme(
      panel.grid.minor  = element_blank(),
      panel.grid.major  = element_line(colour = "grey92", linewidth = 0.3),
      axis.title        = element_text(colour = "grey20"),
      axis.text         = element_text(colour = "grey35"),
      plot.title        = element_text(face = "bold", size = base + 1.5,
                                       colour = "grey10"),
      plot.subtitle     = element_text(colour = "grey35", size = base - 0.5),
      plot.title.position = "plot",
      legend.title      = element_text(size = base - 0.5),
      legend.key.height = unit(0.9, "lines"),
      strip.text        = element_text(face = "bold", colour = "grey20")
    )
}
theme_map <- function(base = 9) {
  theme_void(base_size = base) +
    theme(plot.title = element_text(face = "bold", size = base + 1.5, colour = "grey10"),
          plot.subtitle = element_text(colour = "grey35", size = base - 0.5),
          plot.title.position = "plot",
          legend.title = element_text(size = base - 0.5))
}

# Regenerate only what is missing unless EDAPHOS_FIGS_FORCE=1. Some blocks
# train models (diffusion, MoCo, MCMC), so a full rebuild is minutes.
FORCE <- identical(Sys.getenv("EDAPHOS_FIGS_FORCE", "0"), "1")
need <- function(name) FORCE || !file.exists(file.path(OUT, paste0(name, ".png")))

save_fig <- function(p, name, w, h) {
  ggsave(file.path(OUT, paste0(name, ".png")), p, width = w, height = h,
         dpi = 300, bg = "white")
  ggsave(file.path(OUT, paste0(name, ".tiff")), p, width = w, height = h,
         dpi = 300, bg = "white", compression = "lzw")
  message(sprintf("  %-8s %4.1f x %4.1f in", name, w, h))
}

# =============================================================================
# Fig 1 — study area and data
# =============================================================================
message("Fig 1: study area")
CAU <- ex("causal_cerrado_real_v2.rds")
prof <- CAU$profiles
pts <- sf::st_as_sf(prof, coords = c("lon", "lat"), crs = 4326)

biomes  <- suppressMessages(geobr::read_biomes(year = 2019, showProgress = FALSE))
cerrado <- biomes[biomes$name_biome == "Cerrado", ]
brazil  <- suppressMessages(geobr::read_country(year = 2020, showProgress = FALSE))

map <- ggplot() +
  geom_sf(data = brazil, fill = "grey96", colour = "grey75", linewidth = 0.25) +
  geom_sf(data = cerrado, fill = "#F3E9DC", colour = "#B08968", linewidth = 0.45) +
  geom_sf(data = pts, aes(colour = soc), size = 0.55, alpha = 0.85) +
  scale_colour_viridis_c(
    option = "inferno", direction = -1, trans = "sqrt",
    breaks = c(5, 20, 50, 100, 200),
    name = expression(atop("Topsoil organic", paste("carbon (g kg"^-1, ")")))) +
  coord_sf(xlim = c(-62, -39), ylim = c(-25, -1), expand = FALSE) +
  labs(title = "A  Study area",
       subtitle = sprintf("%s WoSIS topsoil profiles across the Cerrado biome",
                          format(nrow(prof), big.mark = ","))) +
  theme_map() +
  theme(legend.position = c(0.16, 0.28),
        legend.background = element_rect(fill = alpha("white", 0.8), colour = NA))

dens <- ggplot(prof, aes(x = soc)) +
  geom_histogram(bins = 46, fill = PAL[["soc"]], colour = "white", linewidth = 0.15) +
  scale_x_continuous(trans = "sqrt", breaks = c(0, 10, 25, 50, 100, 200, 390)) +
  labs(title = "B  Distribution of the response",
       subtitle = sprintf("median %.1f g kg-1; long right tail to %.0f",
                          median(prof$soc), max(prof$soc)),
       x = expression(paste("Topsoil organic carbon (g kg"^-1, ", square-root scale)")),
       y = "Profiles") +
  theme_edaphos()

covlong <- data.frame(
  value = c(prof$map, prof$mat, prof$clay, prof$trees * 100),
  var = factor(rep(c("Precipitation (mm)", "Temperature (deg C)",
                     "Clay (%)", "Tree cover (%)"), each = nrow(prof)),
               levels = c("Precipitation (mm)", "Temperature (deg C)",
                          "Clay (%)", "Tree cover (%)")))
cov_p <- ggplot(covlong, aes(x = value, fill = var)) +
  geom_density(alpha = 0.75, colour = NA) +
  facet_wrap(~var, scales = "free", nrow = 1) +
  scale_fill_manual(values = c("#1B6CA8", "#C1440E", "#B08968", "#2E7D5B")) +
  labs(title = "C  Covariates at the profile locations",
       subtitle = "WorldClim 2.1, SoilGrids and Copernicus tree cover, extracted per profile",
       x = NULL, y = "Density") +
  theme_edaphos() + theme(legend.position = "none",
                          axis.text.y = element_blank())

fig_area <- (map | dens) / cov_p + plot_layout(heights = c(1.45, 1))
save_fig(fig_area, "Fig1", 9.2, 8.0)

# =============================================================================
# Fig 2 — benchmark (accuracy, skill, calibration, cost)
# =============================================================================
message("Fig 2: benchmark")
B6 <- ex("benchmark_wosis_6pilar.rds")
tb <- B6$cv_aggregate
tb$short <- sub(" .*", "", tb$method)
tb$label <- c("OLS on DAG set", "Quantile forest", "Bayesian spatial",
              "Foundation + forest", "Graph attention", "Quantum kernel")[
                match(tb$short, c("P1", "P5", "P7", "P4", "P10", "P6"))]
tb$label[is.na(tb$label)] <- tb$short[is.na(tb$label)]
tb <- tb[order(tb$rmse_mean), ]
tb$label <- factor(tb$label, levels = rev(tb$label))

pa <- ggplot(tb, aes(x = rmse_mean, y = label, fill = nse_mean > 0)) +
  geom_col(width = 0.62) +
  geom_text(aes(label = sprintf("%.3f", rmse_mean)), hjust = -0.18, size = 2.9,
            colour = "grey25") +
  scale_fill_manual(values = c(`TRUE` = PAL[["cool"]], `FALSE` = PAL[["bad"]]),
                    guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.13))) +
  labs(title = "A  Predictive accuracy", x = "RMSE, log1p(g/kg) (lower is better)",
       y = NULL, subtitle = "red: explains less than the training-fold mean\n68 km buffered spatial folds") +
  theme_edaphos()

# Both nulls, because the choice of null moves the headline. The bar is the
# ACHIEVABLE null (training-fold mean); the open point is the oracle null
# (test-fold mean) that the conventional R-squared formula uses and that this
# paper reported under the achievable one's name until it was corrected.
pb <- ggplot(tb, aes(y = label)) +
  geom_vline(xintercept = 0, colour = "grey45", linetype = 2) +
  geom_segment(aes(x = 0, xend = nse_mean, yend = label,
                   colour = nse_mean > 0), linewidth = 1.1) +
  geom_point(aes(x = nse_mean, colour = nse_mean > 0), size = 3.1) +
  geom_point(aes(x = r2_mean), shape = 21, size = 2.6, stroke = 0.8,
             fill = "white", colour = "grey35") +
  scale_colour_manual(values = c(`TRUE` = PAL[["good"]], `FALSE` = PAL[["bad"]]),
                      guide = "none") +
  labs(title = "B  Skill against the achievable null",
       subtitle = paste("filled: vs each fold's TRAINING mean, the null a map could use.",
                        "\nopen: vs the test fold's own mean, an oracle -- the harder bar"),
       x = "Skill", y = NULL) +
  theme_edaphos() + theme(axis.text.y = element_blank())

# One colour per method, fixed by name so panels C and D agree with each other.
mcol <- setNames(METHOD_PAL[seq_len(nlevels(tb$label))], levels(tb$label))

pc <- ggplot(tb, aes(x = mpiw90_mean, y = picp90_mean)) +
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.86, ymax = 0.94,
           fill = PAL[["good"]], alpha = 0.10) +
  geom_hline(yintercept = 0.90, linetype = 2, colour = "grey40") +
  annotate("text", x = Inf, y = 0.905, label = "nominal 90%", hjust = 1.05,
           vjust = 0, size = 2.5, colour = "grey40") +
  geom_point(aes(colour = label), size = 4.2) +
  ggrepel::geom_text_repel(aes(label = label, colour = label), size = 2.8,
                           seed = 3, box.padding = 0.75, point.padding = 0.4,
                           min.segment.length = 0, segment.colour = "grey70",
                           max.overlaps = 20, show.legend = FALSE) +
  scale_colour_manual(values = mcol, guide = "none") +
  scale_y_continuous(limits = c(0.45, 0.96)) +
  labs(title = "C  Calibration against sharpness",
       subtitle = "shaded band: within 4 points of nominal coverage. Narrow intervals\nare a virtue only if coverage holds -- the quantum kernel has neither",
       x = "Mean 90% interval width (narrower = sharper)",
       y = "Empirical coverage") +
  theme_edaphos()

pd <- ggplot(tb, aes(x = elapsed_sum, y = label, fill = label)) +
  geom_col(width = 0.62) +
  geom_text(aes(label = ifelse(elapsed_sum >= 10,
                               sprintf("%.0f s", elapsed_sum),
                               sprintf("%.1f s", elapsed_sum))),
            hjust = -0.15, size = 2.8, colour = "grey25") +
  scale_fill_manual(values = mcol, guide = "none") +
  scale_x_continuous(trans = "log10", labels = label_number(accuracy = 1),
                     expand = expansion(mult = c(0, 0.30))) +
  labs(title = "D  Computational cost",
       subtitle = "the least accurate method is also the most expensive",
       x = "Seconds (log scale)", y = NULL) +
  theme_edaphos()

fig_bench <- (pa | pb) / (pc | pd) + plot_layout(heights = c(1, 1.15))
save_fig(fig_bench, "Fig13", 9.2, 7.4)

# =============================================================================
# Fig 3 — causal: forest plot + adjustment effect
# =============================================================================
message("Fig 3: causal")
e <- CAU$effects
lab <- c(wc_bio_12 = "Precipitation\n(per mm)", wc_bio_01 = "Temperature\n(per deg C)",
         wc_landcover_trees = "Tree cover\n(per unit)", soilgrids_clay = "Clay\n(per %)")
e$lab <- lab[e$exposure]
e$sig <- ifelse(e$signif, "interval excludes zero", "interval covers zero")
# put on a comparable scale: standardise by the covariate's own SD
sdv <- c(wc_bio_12 = sd(prof$map), wc_bio_01 = sd(prof$mat),
         wc_landcover_trees = sd(prof$trees), soilgrids_clay = sd(prof$clay))
e$s   <- sdv[e$exposure]
e$b_n <- e$beta_naive * e$s; e$b_a <- e$beta_adj * e$s
e$lo  <- e$ci_lo * e$s;      e$hi  <- e$ci_hi * e$s
e <- e[order(e$b_a), ]; e$lab <- factor(e$lab, levels = e$lab)

pf <- ggplot(e, aes(y = lab)) +
  geom_vline(xintercept = 0, linetype = 2, colour = "grey45") +
  geom_segment(aes(x = b_n, xend = b_a, yend = lab), colour = "grey65",
               linewidth = 0.7, arrow = arrow(length = unit(0.10, "in"), type = "closed")) +
  geom_errorbarh(aes(xmin = lo, xmax = hi, colour = sig), height = 0.14, linewidth = 0.9) +
  geom_point(aes(x = b_n), shape = 21, size = 3, fill = "white", colour = "grey45") +
  geom_point(aes(x = b_a, colour = sig), size = 3.6) +
  scale_colour_manual(values = c("interval excludes zero" = PAL[["good"]],
                                 "interval covers zero"   = PAL[["bad"]]),
                      name = NULL) +
  labs(title = "A  Adjustment moves the estimate, sometimes to nothing",
       subtitle = "open circle: unadjusted. filled: backdoor-adjusted, with 95% spatial block bootstrap.\nArrow shows the movement. Effects scaled by each covariate's standard deviation.",
       x = expression(paste("Change in topsoil carbon (g kg"^-1, ") per 1 SD of the exposure")),
       y = NULL) +
  theme_edaphos() + theme(legend.position = "top")

rv <- e[order(e$RV), ]; rv$lab <- factor(rv$lab, levels = rv$lab)
pr <- ggplot(rv, aes(x = RV, y = lab, fill = RV)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = sprintf("%.3f", RV)), hjust = -0.2, size = 2.9, colour = "grey25") +
  scale_fill_gradient(low = "#F2C4B4", high = PAL[["accent"]], guide = "none") +
  scale_x_continuous(labels = percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.18))) +
  labs(title = "B  How much confounding would erase it?",
       subtitle = "Cinelli-Hazlett robustness value: residual variance an unobserved\nconfounder must explain in BOTH exposure and outcome",
       x = "Robustness value", y = NULL) +
  theme_edaphos()

fig_causal <- pf / pr + plot_layout(heights = c(1.25, 1))
save_fig(fig_causal, "Fig14", 7.6, 7.2)

# =============================================================================
# Fig 3 — Pillar 2: the attained deep value vs the equation's coordinate
# =============================================================================
message("Fig 3: pedogenetic ODE")
CAP <- ex("capstone_campaign_results.rds")
ped <- CAP$piml_profile_obs
fitb <- piml_profile_fit_bayesian(ped$depth_mid, ped$soc_g_kg, method = "laplace", seed = 7L)
dz <- seq(0, max(ped$bottom) * 1.15, by = 2)   # past the deepest horizon
pp <- predict(fitb, newdepths = dz, interval = 0.95)
pdf_ <- data.frame(depth = dz, mean = pp$mean, lo = pp$lower, hi = pp$upper)
# Annotate with the POSTERIOR MEANS, which is what the drawn curve and Table 2
# both report. Using the MAP here instead would put numbers on the figure that
# disagree with the table beside it.
.ps  <- CAP$piml_params_table
y_as <- .ps$mean[.ps$param == "y_asym"]
y_in <- .ps$mean[.ps$param == "y_inf"]

# Panel A carries the whole point: the solution flattens onto y(Inf), well
# above zero, while y_inf sits far off to the left at a value no profile
# reaches. Extending to 400 cm makes the plateau visible.
pprof <- ggplot() +
  geom_vline(xintercept = 0, colour = "grey80", linewidth = 0.35) +
  geom_ribbon(data = pdf_, aes(y = -depth, xmin = lo, xmax = hi),
              fill = PAL[["soc"]], alpha = 0.18) +
  geom_path(data = pdf_, aes(x = mean, y = -depth), colour = PAL[["soc"]], linewidth = 1) +
  geom_vline(xintercept = y_as, colour = PAL[["cool"]], linetype = 2, linewidth = 0.7) +
  geom_vline(xintercept = y_in, colour = PAL[["bad"]], linetype = 3, linewidth = 0.7) +
  annotate("text", x = y_as, y = -0.62 * max(ped$bottom), hjust = -0.06, size = 2.7,
           colour = PAL[["cool"]], fontface = "bold",
           label = sprintf("y(inf) = %.2f\nattained", y_as)) +
  annotate("text", x = y_in, y = -0.26 * max(ped$bottom), hjust = -0.06, size = 2.7,
           colour = PAL[["bad"]], fontface = "bold",
           label = sprintf("y-inf = %.1f\nnever reached", y_in)) +
  geom_point(data = ped, aes(x = soc_g_kg, y = -depth_mid), colour = PAL[["accent"]],
             size = 2.6) +
  scale_y_continuous(breaks = -pretty(c(0, max(ped$bottom)), 5),
                     labels = pretty(c(0, max(ped$bottom)), 5)) +
  labs(title = "A  The profile settles above zero, not on y-infinity",
       subtitle = expression(paste("d", italic(y), "/d", italic(z), " = -", lambda[0],
                                   " exp(-", mu, italic(z), ")(", italic(y), " - ",
                                   italic(y)[infinity], "); ribbon is the 95% posterior")),
       x = expression(paste("Organic carbon (g kg"^-1, ")")), y = "Depth (cm)") +
  theme_edaphos()

ptab <- CAP$piml_params_table
ptab <- ptab[ptab$param %in% c("lambda0", "mu", "y0", "kappa", "sigma",
                               "y_asym", "y_inf"), ]
.lab <- c(lambda0 = "lambda[0]", mu = "mu", y0 = "y[0]", kappa = "kappa",
          sigma = "sigma~~(noise)",
          y_asym = "y(infinity)~~attained", y_inf = "y[infinity]~~coordinate")
ptab$param <- factor(ptab$param,
                     levels = c("lambda0", "mu", "kappa", "y0", "sigma",
                                "y_asym", "y_inf"))
ptab$lab <- factor(.lab[as.character(ptab$param)], levels = .lab)
ptab$ident <- ifelse(ptab$param == "y_inf", "not identified", "identified")
ppar <- ggplot(ptab, aes(y = 1, colour = ident)) +
  # A zero reference only where crossing zero is the point. On y0 it would
  # stretch the axis to 0-40 and hide an interval 1.2 g/kg wide.
  geom_vline(data = ptab[ptab$param %in% c("y_asym", "y_inf"), ],
             aes(xintercept = 0), linetype = 2, colour = "grey55") +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi), height = 0.14, linewidth = 0.9) +
  geom_point(aes(x = mean), size = 3.2) +
  facet_wrap(~lab, scales = "free_x", ncol = 1, strip.position = "left",
             labeller = label_parsed) +
  scale_colour_manual(values = c(identified = PAL[["cool"]],
                                 `not identified` = PAL[["bad"]]), name = NULL) +
  labs(title = sprintf("B  What the %d horizons identify", nrow(ped)),
       # Computed, not asserted. An earlier version hard-coded a ratio and the
       # claim "lies entirely below zero", both of which stopped being true
       # when the pedon became a real profile.
       subtitle = local({
         w <- function(k) {
           r <- CAP$piml_params_table[CAP$piml_params_table$param == k, ]
           r$ci_hi - r$ci_lo
         }
         lo <- CAP$piml_params_table$ci_lo[CAP$piml_params_table$param == "y_inf"]
         sprintf(paste0("The attainable deep value is pinned above zero; ",
                        "y-infinity, the\ncoordinate, is %.1fx wider and ",
                        "reaches %.1f g/kg -- impossible carbon"),
                 w("y_inf") / w("y_asym"), lo)
       }),
       x = "Posterior mean and 95% interval", y = NULL) +
  theme_edaphos() +
  theme(axis.text.y = element_blank(), axis.ticks.y = element_blank(),
        legend.position = "top", strip.placement = "outside",
        strip.text.y.left = element_text(angle = 0))

fig_ode <- pprof | ppar
save_fig(fig_ode, "Fig3", 9.4, 5.2)

# =============================================================================
# Fig 4 — Pillar 2: is the fitted depth function mappable?
# =============================================================================
if (need("Fig4")) {
message("Fig 4: parameter variograms")
V  <- ex("piml_parameter_variograms.rds")
tb <- V$table
LAB <- c(log_y0 = "log~y[0]", log_y_asym = "log~y(infinity)",
         log_kappa = "log~kappa", log_mu = "log~mu")

emp <- do.call(rbind, lapply(names(V$raw), function(k) {
  d <- V$raw[[k]]$vg
  data.frame(par = k, dist = d$dist, gamma = d$gamma, np = d$np)
}))
emp$lab <- factor(LAB[emp$par], levels = LAB)

# fitted exponential curves, but only where the fit is identified: a model
# whose range sits outside the cutoff is drawn as a dashed extrapolation and
# labelled as such, never as a measurement.
curv <- do.call(rbind, lapply(names(V$raw), function(k) {
  r <- V$raw[[k]]
  if (is.null(r$model)) return(NULL)
  nug <- r$nugget; psl <- r$psill; rng <- r$range
  h <- seq(0, V$cutoff, length.out = 200)
  data.frame(par = k, dist = h, gamma = nug + psl * (1 - exp(-h / rng)),
             identified = isTRUE(r$range_in_window))
}))
curv$lab <- factor(LAB[curv$par], levels = LAB)

ann <- do.call(rbind, lapply(seq_len(nrow(tb)), function(i) {
  k <- names(V$raw)[i]
  data.frame(par = k,
             txt = if (is.finite(tb$nugget_ratio[i]))
               sprintf("nugget/sill = %.2f\nrange = %.0f km",
                       tb$nugget_ratio[i], tb$range_km[i])
             else sprintf("range %.0f km is below the\n%.0f km nearest lag: not identified",
                          tb$range_km[i], tb$first_lag_km[i]),
             ok = is.finite(tb$nugget_ratio[i]))
}))
ann$lab <- factor(LAB[ann$par], levels = LAB)

p4 <- ggplot(emp, aes(dist, gamma)) +
  geom_line(data = curv, aes(dist, gamma, linetype = identified),
            colour = PAL[["cool"]], linewidth = 0.9) +
  geom_point(aes(size = np), colour = PAL[["soc"]], alpha = 0.85) +
  geom_text(data = ann, aes(x = 0, y = Inf, label = txt, colour = ok),
            hjust = -0.05, vjust = 1.4, size = 2.6, lineheight = 0.95,
            inherit.aes = FALSE) +
  facet_wrap(~lab, scales = "free_y", nrow = 2, labeller = label_parsed) +
  scale_size_continuous(range = c(0.6, 2.6), name = "point pairs",
                        labels = scales::label_number(scale_cut = scales::cut_short_scale())) +
  scale_linetype_manual(values = c(`TRUE` = 1, `FALSE` = 2), guide = "none") +
  scale_colour_manual(values = c(`TRUE` = PAL[["good"]], `FALSE` = PAL[["bad"]]),
                      guide = "none") +
  labs(title = "The depth function varies faster than the survey can see",
       subtitle = sprintf(paste("ODE parameters fitted at each of %s profiles, %s point pairs.",
                                "Green: a sill is\nreached inside the observed separations. Red: the fitted range falls below the",
                                "nearest\nlag the archive supports, so it is interpolated through empty space, not measured"),
                          format(V$n_profiles, big.mark = ","),
                          format(sum(V$raw[[1]]$vg$np), big.mark = ",")),
       x = "Separation distance (km)", y = "Semivariance") +
  theme_edaphos() + theme(legend.position = "top")

save_fig(p4, "Fig4", 8.6, 6.2)
}

message("done -> ", OUT)

# ---------------------------------------------------------------------------
# factor() with hard-coded levels fails SILENTLY when a level does not match a
# value: every unmatched row becomes NA, the plot loses the distinction the
# figure exists to show, and the legend reads "NA". That shipped in Fig 11 --
# panel B's three clouds were levelled on panel A's shorter labels and the
# published figure carries one grey cloud under a caption describing three.
# Nothing in ggplot warns. This does.
# ---------------------------------------------------------------------------
.fct <- function(x, levels, what = deparse(substitute(x))) {
  missing_lv <- setdiff(unique(as.character(x)), levels)
  if (length(missing_lv))
    stop(sprintf("%s: %d value(s) match no level -- {%s}; levels are {%s}",
                 what, length(missing_lv),
                 paste(missing_lv, collapse = ", "),
                 paste(levels, collapse = ", ")), call. = FALSE)
  factor(x, levels = levels)
}

# =============================================================================
# Fig 5 — Pillar 3: space-time forecasting and sequential assimilation
# =============================================================================
message("Fig 5: 4D pedometry")
TT   <- ex("temporal_cerrado_results.rds")
meta <- TT$meta
grid_df <- function(m, lab) {
  data.frame(lon = rep(meta$lons, times = meta$W),
             lat = rep(meta$lats, each  = meta$H),
             z = as.vector(m), panel = lab)
}
# three lead times from the ensemble-mean forecast, against the truth
leads <- c(1L, 18L, 36L)
fc_mean <- apply(TT$ensemble_forecast, c(2, 3, 4), mean)
maps <- do.call(rbind, c(
  lapply(leads, function(k) { d <- grid_df(TT$truth_future[k, , ], "Observed");
                              d$month <- sprintf("Month %d", k); d }),
  lapply(leads, function(k) { d <- grid_df(fc_mean[k, , ], "ConvLSTM forecast");
                              d$month <- sprintf("Month %d", k); d })))
maps$panel <- .fct(maps$panel, c("Observed", "ConvLSTM forecast"))
maps$month <- .fct(maps$month, sprintf("Month %d", leads))

p3a <- ggplot(maps, aes(lon, lat, fill = z)) +
  geom_raster() +
  facet_grid(panel ~ month, switch = "y") +
  scale_fill_viridis_c(option = "viridis", name = "NDVI (z)") +
  coord_equal(expand = FALSE) +
  labs(title = "A  A soil-vegetation field forecast forward in time",
       subtitle = "stacked convolutional LSTM, 10 x 10 cells over the Cerrado, 36 months ahead",
       x = NULL, y = NULL) +
  theme_edaphos() +
  theme(axis.text = element_blank(), panel.grid = element_blank(),
        legend.position = "right", strip.placement = "outside",
        strip.text.y.left = element_text(angle = 90, face = "bold"),
        panel.spacing = unit(0.35, "lines"))

# ensemble trajectory at the cell the filter corrects most
gr <- which(abs(TT$analysis$mean - TT$prior$mean) ==
              max(abs(TT$analysis$mean - TT$prior$mean)), arr.ind = TRUE)[1, ]
traj <- data.frame(
  month = rep(seq_len(dim(TT$ensemble_forecast)[2]), dim(TT$ensemble_forecast)[1]),
  value = as.vector(t(TT$ensemble_forecast[, , gr[1], gr[2]])),
  member = rep(seq_len(dim(TT$ensemble_forecast)[1]),
               each = dim(TT$ensemble_forecast)[2]))
truth_line <- data.frame(month = seq_len(dim(TT$truth_future)[1]),
                         value = TT$truth_future[, gr[1], gr[2]])

p3b <- ggplot() +
  geom_line(data = traj, aes(month, value, group = member),
            colour = "#1B6CA8", alpha = 0.35, linewidth = 0.4) +
  geom_line(data = truth_line, aes(month, value), colour = PAL[["accent"]],
            linewidth = 1) +
  annotate("text", x = Inf, y = Inf, label = "observed", hjust = 1.1, vjust = 1.6,
           colour = PAL[["accent"]], size = 3, fontface = "bold") +
  annotate("text", x = Inf, y = -Inf, label = "10 ensemble members", hjust = 1.1,
           vjust = -0.8, colour = "#1B6CA8", size = 3) +
  labs(title = "B  Forecast ensemble at the cell the filter corrects most",
       x = "Months ahead", y = "NDVI (z)") +
  theme_edaphos()

enkf <- rbind(grid_df(TT$prior$mean, "Prior (forecast)"),
              grid_df(TT$analysis$mean, "Analysis (after assimilation)"),
              grid_df(TT$analysis$mean - TT$prior$mean, "Increment"))
enkf$panel <- .fct(enkf$panel, c("Prior (forecast)",
                                 "Analysis (after assimilation)", "Increment"))
obs_pts <- data.frame(lon = meta$lons[TT$obs$col], lat = meta$lats[TT$obs$row],
                      panel = factor("Analysis (after assimilation)",
                                     levels = levels(enkf$panel)))
p3c <- ggplot(enkf, aes(lon, lat, fill = z)) +
  geom_raster() +
  geom_point(data = obs_pts, aes(lon, lat), inherit.aes = FALSE,
             shape = 21, size = 2.2, stroke = 0.8, colour = "white", fill = "black") +
  facet_wrap(~panel, nrow = 1) +
  scale_fill_gradient2(low = "#2166AC", mid = "grey96", high = "#B2182B",
                       midpoint = 0, name = "NDVI (z)") +
  coord_equal(expand = FALSE) +
  labs(title = "C  Ensemble Kalman assimilation of eight in-situ observations",
       subtitle = sprintf("localised update; ensemble spread falls by %.0f%% at the observed cells",
                          100 * TT$sd_reduction),
       x = NULL, y = NULL) +
  theme_edaphos() +
  theme(axis.text = element_blank(), panel.grid = element_blank())

fig_temporal <- p3a / (p3b | p3c) + plot_layout(heights = c(1.15, 1))
save_fig(fig_temporal, "Fig5", 9.4, 7.6)

# =============================================================================
# Fig 6 — Pillar 6: the simulated quantum kernel
# =============================================================================
message("Fig 6: quantum kernel")
data(br_cerrado, envir = environment())
set.seed(4)
idx <- sample(nrow(br_cerrado), 60)
Xq  <- quantum_scale(as.matrix(br_cerrado[idx, c("elev", "twi", "map_mm")]))
ord <- order(br_cerrado$soc[idx])
Xq  <- Xq[ord, , drop = FALSE]
Kq  <- quantum_kernel(Xq, reps = 2L)
d2  <- as.matrix(dist(Xq))^2
Kr  <- exp(-d2 / (2 * median(d2[upper.tri(d2)])))

gram <- rbind(
  data.frame(i = rep(seq_len(nrow(Kq)), nrow(Kq)), j = rep(seq_len(nrow(Kq)), each = nrow(Kq)),
             k = as.vector(Kq), panel = "Quantum fidelity kernel"),
  data.frame(i = rep(seq_len(nrow(Kr)), nrow(Kr)), j = rep(seq_len(nrow(Kr)), each = nrow(Kr)),
             k = as.vector(Kr), panel = "Gaussian (RBF) kernel"))
gram$panel <- .fct(gram$panel, c("Quantum fidelity kernel", "Gaussian (RBF) kernel"))

p6a <- ggplot(gram, aes(i, j, fill = k)) +
  geom_raster() + facet_wrap(~panel) +
  scale_fill_viridis_c(option = "magma", name = "K(x, x')", limits = c(0, 1)) +
  coord_equal(expand = FALSE) +
  labs(title = "A  Two similarity matrices over the same 60 profiles",
       subtitle = "profiles ordered by organic carbon; the quantum kernel is the fidelity of two encoded states",
       x = "Profile", y = "Profile") +
  theme_edaphos() + theme(panel.grid = element_blank())

# the encoding circuit's effect: kernel value against covariate distance
dd <- data.frame(dist = sqrt(d2[upper.tri(d2)]),
                 quantum = Kq[upper.tri(Kq)], rbf = Kr[upper.tri(Kr)])
ddl <- rbind(data.frame(dist = dd$dist, k = dd$quantum, kind = "Quantum fidelity"),
             data.frame(dist = dd$dist, k = dd$rbf,     kind = "Gaussian (RBF)"))
p6b <- ggplot(ddl, aes(dist, k, colour = kind)) +
  geom_point(alpha = 0.25, size = 0.7) +
  geom_smooth(se = FALSE, method = "loess", formula = y ~ x, linewidth = 1) +
  scale_colour_manual(values = c("Quantum fidelity" = "#7B2D8E",
                                 "Gaussian (RBF)" = "#1B6CA8"), name = NULL) +
  labs(title = "B  Similarity against distance in covariate space",
       subtitle = "the Gaussian kernel decays monotonically; the ZZ feature map does not,\nwhich is the property it is proposed for -- and, here, why it generalises worse",
       x = "Euclidean distance between standardised covariates",
       y = "Kernel value") +
  theme_edaphos() + theme(legend.position = "top")

fig_quantum <- p6a / p6b + plot_layout(heights = c(1, 0.95))
save_fig(fig_quantum, "Fig8", 8.4, 7.2)

# =============================================================================
# Fig 7 — Pillar 9: diffusion, reference vs trained sampler
# =============================================================================
if (need("Fig11")) {
message("diffusion (fits two models)")
g <- 45L
ux <- sort(unique(br_cerrado$x)); uy <- sort(unique(br_cerrado$y))
as_grid <- function(v) { m <- matrix(NA_real_, g, g)
  m[cbind(match(br_cerrado$x, ux), match(br_cerrado$y, uy))] <- v; m }
fieldz <- { f <- as_grid(br_cerrado$twi); (f - mean(f)) / stats::sd(f) }
P <- 8L; st <- seq(1L, g - P + 1L, by = 3L); gg <- expand.grid(r = st, c = st)
stack <- array(0, dim = c(nrow(gg), P, P))
for (i in seq_len(nrow(gg)))
  stack[i, , ] <- fieldz[gg$r[i]:(gg$r[i] + P - 1L), gg$c[i]:(gg$c[i] + P - 1L)]

lag1 <- function(p) {
  h <- stats::cor(as.vector(p[, -ncol(p)]), as.vector(p[, -1]))
  v <- stats::cor(as.vector(p[-nrow(p), ]), as.vector(p[-1, ])); (h + v) / 2
}
fit_r <- dm_fit(stack, backend = "r", T = 100L, epochs = 250L, hidden = 48L,
                lr = 0.02, seed = 1L)
gen_r <- dm_sample(fit_r, n_samples = 40L, seed = 7L)
has_t <- isTRUE(tryCatch(torch::torch_is_installed(), error = function(e) FALSE))
if (has_t) {
  fit_t <- dm_fit(stack, backend = "torch", device = "cpu", T = 100L, epochs = 700L,
                  hidden = 64L, lr = 1e-3, seed = 1L)
  gen_t <- dm_sample(fit_t, n_samples = 40L, seed = 7L)
}
patch_df <- function(a, idx, lab) do.call(rbind, lapply(seq_along(idx), function(k)
  data.frame(x = rep(1:P, P), y = rep(1:P, each = P),
             z = as.vector(a[idx[k], , ]), rep = k, panel = lab)))
sel <- 1:4
pl <- rbind(patch_df(stack, c(1, 20, 60, 110), "Real"),
            patch_df(gen_r, sel, "Pure-R\nreference"))
if (has_t) pl <- rbind(pl, patch_df(gen_t, sel, "Trained\n(torch)"))
pl$panel <- .fct(pl$panel, intersect(c("Real", "Pure-R\nreference", "Trained\n(torch)"), pl$panel))
p9a <- ggplot(pl, aes(x, y, fill = z)) +
  geom_raster() + facet_grid(panel ~ rep, switch = "y") +
  scale_fill_gradientn(colours = hcl.colors(64, "Terrain2"), name = "z",
                       limits = c(-2.5, 2.5), oob = scales::squish) +
  coord_equal(expand = FALSE) +
  labs(title = "A  Whole-patch realisations, not per-pixel intervals",
       subtitle = "8 x 8 topographic wetness patches. Colour is clipped at +/-2.5 sd, so the\nreference sampler's saturated cells are themselves the diagnostic",
       x = NULL, y = NULL) +
  theme_edaphos() +
  theme(axis.text = element_blank(), panel.grid = element_blank(),
        strip.text.x = element_blank(), strip.placement = "outside",
        strip.text.y.left = element_text(angle = 0, face = "bold", size = 7.5,
                                         hjust = 1))

stats_df <- rbind(
  data.frame(set = "Real patches", sd = apply(stack, 1, stats::sd), l1 = apply(stack, 1, lag1)),
  data.frame(set = "Pure-R reference sampler", sd = apply(gen_r, 1, stats::sd),
             l1 = apply(gen_r, 1, lag1)))
if (has_t) stats_df <- rbind(stats_df,
  data.frame(set = "Trained (torch) sampler", sd = apply(gen_t, 1, stats::sd),
             l1 = apply(gen_t, 1, lag1)))
# Panel B's labels are NOT panel A's. Forcing pl$panel's levels ("Real",
# "Pure-R\nreference", "Trained\n(torch)") onto values spelled "Real patches",
# "Pure-R reference sampler" and "Trained (torch) sampler" matched nothing and
# silently turned every row into NA -- which is what shipped: one grey cloud, a
# legend reading "NA", and a single ellipse, under a caption describing three
# distinguishable clouds. Level them on their own values.
SET_LEVELS <- c("Real patches", "Pure-R reference sampler",
                "Trained (torch) sampler")
stats_df$set <- .fct(stats_df$set, intersect(SET_LEVELS, stats_df$set))
SETCOL <- c("Real patches" = "#4B2E15", "Pure-R reference sampler" = "#A8322D",
            "Trained (torch) sampler" = "#2E7D5B")
p9b <- ggplot(stats_df, aes(l1, sd, colour = set, fill = set)) +
  geom_vline(xintercept = mean(apply(stack, 1, lag1)), linetype = 2, colour = "grey55") +
  geom_hline(yintercept = mean(apply(stack, 1, stats::sd)), linetype = 2, colour = "grey55") +
  geom_point(alpha = 0.55, size = 1.6) +
  stat_ellipse(level = 0.8, linewidth = 0.8, show.legend = FALSE) +
  scale_colour_manual(values = SETCOL, name = NULL) +
  scale_fill_manual(values = SETCOL, guide = "none") +
  labs(title = "B  The two-number check a generative soil model must pass",
       subtitle = "dashed lines are the real patches' means. The reference sampler misses on\nboth axes: too variable, and spatially incoherent (lag-1 near zero)",
       x = "Lag-1 spatial autocorrelation", y = "Within-patch standard deviation") +
  theme_edaphos() + theme(legend.position = "top")

fig_diff <- p9a / p9b + plot_layout(heights = c(1, 1.05))
save_fig(fig_diff, "Fig11", 8.6, 7.4)
}

# =============================================================================
# Fig 8 — Pillar 10: the co-location graph
# =============================================================================
message("Fig 8: graph attention")
set.seed(11)
sub_i <- sample(nrow(prof), 320)
gd <- prof[sub_i, ]
gd$lon <- gd$lon; gd$lat <- gd$lat
G <- gnn_build_graph(gd, k = 6L, feature_cols = c("mat", "map", "clay", "elev"))
ei <- G$edge_index
edges <- data.frame(
  x = gd$lon[ei[, 1]], y = gd$lat[ei[, 1]],
  xend = gd$lon[ei[, 2]], yend = gd$lat[ei[, 2]],
  w = G$edge_weight)

p10a <- ggplot() +
  geom_sf(data = cerrado, fill = "#F7F2EA", colour = "#B08968", linewidth = 0.35) +
  geom_segment(data = edges, aes(x = x, y = y, xend = xend, yend = yend, alpha = w),
               colour = "#1B6CA8", linewidth = 0.22) +
  geom_point(data = gd, aes(lon, lat, fill = soc), shape = 21, size = 1.5,
             stroke = 0.15, colour = "white") +
  scale_alpha_continuous(range = c(0.05, 0.55), guide = "none") +
  scale_fill_viridis_c(option = "inferno", direction = -1, trans = "sqrt",
                       name = expression(paste("SOC (g kg"^-1, ")"))) +
  coord_sf(xlim = c(-60, -41), ylim = c(-24, -2), expand = FALSE) +
  labs(title = "A  Profiles as nodes of a co-location graph",
       subtitle = sprintf("%d profiles, k = 6 nearest neighbours, %d edges; edge opacity is the inverse-distance weight",
                          nrow(gd), nrow(ei))) +
  theme_map() + theme(legend.position = "right")

# degree and edge-length distributions: what the graph actually encodes
deg <- as.vector(table(factor(c(ei[, 1], ei[, 2]), levels = seq_len(nrow(gd)))))
# Great-circle km, not Euclidean degrees: a degree of longitude at 24 S is 9%
# shorter than a degree of latitude, so a degree axis is not a length axis.
elen <- vapply(seq_len(nrow(edges)), function(i)
  edaphos:::.gc_km(cbind(edges$x[i], edges$y[i]),
                   cbind(edges$xend[i], edges$yend[i]))[1, 1], numeric(1))
gstat <- rbind(data.frame(v = deg,  panel = "Node degree"),
               data.frame(v = elen, panel = "Edge length (km)"))
gstat$panel <- .fct(gstat$panel, c("Node degree", "Edge length (km)"))
p10b <- ggplot(gstat, aes(v, fill = panel)) +
  geom_histogram(bins = 34, colour = "white", linewidth = 0.15) +
  facet_wrap(~panel, scales = "free", nrow = 1) +
  scale_fill_manual(values = c("Node degree" = "#7B5AA6",
                               "Edge length (km)" = "#2E7D5B"), guide = "none") +
  labs(title = "B  What the graph encodes",
       subtitle = sprintf(paste("the k-nearest-neighbour relation is asymmetric, so after symmetrising,",
                                "degree\nranges %d-%d rather than sitting at k = 6; most edges are short but a tail",
                                "reaches\nacross sparsely surveyed ground"), min(deg), max(deg)),
       x = NULL, y = "Count") +
  theme_edaphos()

fig_graph <- p10a / p10b + plot_layout(heights = c(1.5, 1))
save_fig(fig_graph, "Fig12", 7.8, 8.0)

# =============================================================================
# Pillar 5 — active learning: where to sample next
# =============================================================================
if (need("Fig7")) {
message("Pillar 5: active learning")
COVS <- c("elev", "slope", "twi", "map_mm")
set.seed(7)
seed_idx <- al_initial_design(br_cerrado, COVS, n = 30L, seed = 7L)
al_lab   <- br_cerrado[seed_idx, ]
al_cand  <- br_cerrado[-seed_idx, ]
al_mod   <- al_fit(al_lab, target = "soc", covariates = COVS)
al_next  <- al_query(al_mod, candidates = al_cand, n = 8L)
nxt_rows <- if (is.data.frame(al_next)) al_next else al_cand[al_next, ]

# predictive-interval width over the whole grid = the uncertainty surface
pred_all <- predict(al_mod$model, data = br_cerrado[, COVS], type = "quantiles",
                    quantiles = c(0.1, 0.9))$predictions
unc <- pred_all[, 2] - pred_all[, 1]
surf <- data.frame(x = br_cerrado$x, y = br_cerrado$y, unc = unc, soc = br_cerrado$soc)

p5a <- ggplot(surf, aes(x, y)) +
  geom_raster(aes(fill = unc)) +
  geom_point(data = al_lab, aes(x, y), shape = 21, size = 1.5, stroke = 0.35,
             fill = "white", colour = "grey20") +
  geom_point(data = nxt_rows, aes(x, y), shape = 23, size = 3.4, stroke = 0.9,
             fill = "#C1440E", colour = "white") +
  scale_fill_viridis_c(option = "mako", direction = -1,
                       name = expression(paste("80% interval\nwidth (g kg"^-1, ")"))) +
  coord_equal(expand = FALSE) +
  labs(title = "A  The survey decides where to go next",
       subtitle = "bundled 45 x 45 Cerrado demonstration grid. Background: quantile-forest interval\nwidth. White circles: 30 labelled profiles. Orange diamonds: the batch of 8 selected",
       x = NULL, y = NULL) +
  theme_map() + theme(legend.position = "right")

pool_w <- data.frame(w = unc[-seed_idx], set = "All candidates")
sel_i  <- which(paste(al_cand$x, al_cand$y) %in% paste(nxt_rows$x, nxt_rows$y))
batch_w <- data.frame(w = unc[-seed_idx][sel_i], set = "Selected batch")
p5b <- ggplot(rbind(pool_w, batch_w), aes(w, fill = set)) +
  geom_density(alpha = 0.6, colour = NA) +
  scale_fill_manual(values = c("All candidates" = "#8A8F98",
                               "Selected batch" = "#C1440E"), name = NULL) +
  labs(title = "B  The batch is drawn from the uncertain tail",
       subtitle = sprintf("mean interval width: pool %.1f, batch %.1f g kg-1",
                          mean(pool_w$w), mean(batch_w$w)),
       x = expression(paste("80% predictive-interval width (g kg"^-1, ")")),
       y = "Density") +
  theme_edaphos() + theme(legend.position = "top")

# covariate-space coverage: the batch should also spread, not cluster
cs <- rbind(
  data.frame(x = br_cerrado$twi, y = br_cerrado$map_mm, set = "Candidate pool"),
  data.frame(x = al_lab$twi,   y = al_lab$map_mm,   set = "Labelled"),
  data.frame(x = nxt_rows$twi, y = nxt_rows$map_mm, set = "Selected batch"))
p5c <- ggplot(cs, aes(x, y, colour = set, size = set, alpha = set)) +
  geom_point() +
  scale_colour_manual(values = c("Candidate pool" = "grey78", "Labelled" = "#1B6CA8",
                                 "Selected batch" = "#C1440E"), name = NULL) +
  scale_size_manual(values = c(0.5, 1.6, 3), guide = "none") +
  scale_alpha_manual(values = c(0.5, 0.9, 1), guide = "none") +
  labs(title = "C  Where the batch sits in covariate space",
       subtitle = "the batch spreads along wetness but concentrates at high precipitation --\nthe policy chases variance, and variance here is not uniformly distributed",
       x = "Topographic wetness index", y = "Mean annual precipitation (mm)") +
  theme_edaphos() + theme(legend.position = "top")

fig_al <- p5a / (p5b | p5c) + plot_layout(heights = c(1.25, 1))
save_fig(fig_al, "Fig7", 9.0, 8.0)
}

# =============================================================================
# Pillar 7 — Bayesian hierarchical spatial: kriged surface and its uncertainty
# =============================================================================
if (need("Fig9")) {
message("Pillar 7: Bayesian kriging")
set.seed(3)
bh_i  <- sample(nrow(br_cerrado), 150)
bh_d  <- br_cerrado[bh_i, ]; bh_d$lon <- bh_d$x; bh_d$lat <- bh_d$y
bh_fit <- bhs_fit(bh_d, soc ~ twi + map_mm, coords = c("lon", "lat"),
                  nmcmc = 3000L, burn = 1000L, seed = 3L)
newd <- br_cerrado; newd$lon <- newd$x; newd$lat <- newd$y
bh_pr <- predict(bh_fit, newdata = newd, n_draws = 400L)
krig <- data.frame(x = newd$x, y = newd$y, mean = bh_pr$mean, sd = bh_pr$sd)

kA <- ggplot(krig, aes(x, y, fill = mean)) + geom_raster() +
  geom_point(data = bh_d, aes(x, y), inherit.aes = FALSE, shape = 21, size = 1.1,
             stroke = 0.3, fill = "white", colour = "grey25") +
  scale_fill_viridis_c(option = "inferno", direction = -1,
                       name = expression(paste("SOC (g kg"^-1, ")"))) +
  coord_equal(expand = FALSE) +
  labs(title = "A  Posterior mean surface", x = NULL, y = NULL,
       subtitle = "white circles are the 150 conditioning observations") +
  theme_map()

kB <- ggplot(krig, aes(x, y, fill = sd)) + geom_raster() +
  geom_point(data = bh_d, aes(x, y), inherit.aes = FALSE, shape = 21, size = 1.1,
             stroke = 0.3, fill = "white", colour = "grey25") +
  scale_fill_viridis_c(option = "cividis", name = "Posterior SD") +
  coord_equal(expand = FALSE) +
  labs(title = "B  Predictive standard deviation", x = NULL, y = NULL,
       subtitle = "nearly uniform here, because the fitted spatial term is negligible (panel C)") +
  theme_map()

# Why the uncertainty surface is nearly flat: the profile-MLE of phi rails at
# its bracket, so the fitted field is almost all nugget. The package warns about
# exactly this, and the honest figure is the diagnostic, not a prettier surface.
phi_grid <- exp(seq(log(0.05), log(30), length.out = 40))
ll <- vapply(phi_grid, function(ph) {
  f <- suppressWarnings(bhs_fit(bh_d, soc ~ twi + map_mm, coords = c("lon", "lat"),
        nmcmc = 300L, burn = 100L, phi_range = c(ph, ph * 1.0001), seed = 3L))
  mean(f$sigma2_draws) / (mean(f$sigma2_draws) + mean(f$tau2_draws))
}, numeric(1))
kC <- ggplot(data.frame(phi = phi_grid, frac = ll), aes(phi, frac)) +
  geom_line(colour = "#1B6CA8", linewidth = 1) +
  geom_point(colour = "#1B6CA8", size = 1.2) +
  geom_vline(xintercept = bh_fit$phi_hat, linetype = 2, colour = PAL[["accent"]]) +
  annotate("text", x = bh_fit$phi_hat, y = Inf, hjust = 1.08, vjust = 1.6, size = 2.7,
           colour = PAL[["accent"]],
           label = sprintf("profile-MLE rails at phi = %.1f", bh_fit$phi_hat)) +
  scale_x_continuous(trans = "log10") +
  labs(title = "C  Why panel B is nearly flat, and how the package says so",
       subtitle = sprintf(paste("the spatial share of variance collapses as the correlation rate grows;",
                                "the\nfitted field is %.0f%% nugget, and bhs_fit() emits a boundary warning"),
                          100 * (1 - mean(bh_fit$sigma2_draws) /
                                   (mean(bh_fit$sigma2_draws) + mean(bh_fit$tau2_draws)))),
       x = expression(paste("Correlation rate ", phi, " (log scale)")),
       y = "Spatial share of variance") +
  theme_edaphos()

fig_bhs <- (kA | kB) / kC + plot_layout(heights = c(1.3, 1))
save_fig(fig_bhs, "Fig9", 9.2, 7.2)
}

# =============================================================================
# Pillar 1 — the causal graph, its adjustment set, and its falsification
# =============================================================================
if (need("Fig2")) {
message("Pillar 1: causal graph")
dag_r <- causal_cerrado_real_dag()
nice <- c(elev = "Elevation", slope = "Slope", wc_bio_01 = "Temperature",
          wc_bio_12 = "Precipitation", wc_landcover_trees = "Tree cover",
          wc_landcover_cropland = "Cropland", wc_landcover_grassland = "Grassland",
          soilgrids_clay = "Clay", soilgrids_sand = "Sand",
          soilgrids_bdod = "Bulk density", soc_topsoil_gkg = "Topsoil carbon")
co <- dagitty::coordinates(dag_r)
nd <- data.frame(name = names(co$x), x = as.numeric(co$x), y = -as.numeric(co$y))
nd$lab <- nice[nd$name]
E <- dagitty::edges(dag_r)
ed <- data.frame(from = as.character(E$v), to = as.character(E$w))
ed$x    <- nd$x[match(ed$from, nd$name)]; ed$y    <- nd$y[match(ed$from, nd$name)]
ed$xend <- nd$x[match(ed$to,   nd$name)]; ed$yend <- nd$y[match(ed$to,   nd$name)]

aset <- causal_adjustment_set(dag_r, "wc_landcover_trees", "soc_topsoil_gkg",
                              effect = "total")
nd$role <- "other"
nd$role[nd$name %in% aset] <- "adjustment set"
nd$role[nd$name == "wc_landcover_trees"] <- "exposure"
nd$role[nd$name == "soc_topsoil_gkg"]    <- "outcome"
ed$hl <- ed$from %in% c("wc_landcover_trees", aset) & ed$to == "soc_topsoil_gkg" |
         ed$from %in% aset & ed$to == "wc_landcover_trees"

pd1 <- ggplot() +
  geom_segment(data = ed[!ed$hl, ], aes(x, y, xend = xend, yend = yend),
               colour = "grey80", linewidth = 0.4,
               arrow = arrow(length = unit(0.055, "in"), type = "closed")) +
  geom_segment(data = ed[ed$hl, ], aes(x, y, xend = xend, yend = yend),
               colour = "#C1440E", linewidth = 0.85,
               arrow = arrow(length = unit(0.075, "in"), type = "closed")) +
  geom_point(data = nd, aes(x, y, fill = role), shape = 21, size = 8.5,
             stroke = 0.5, colour = "white") +
  ggrepel::geom_text_repel(data = nd, aes(x, y, label = lab), size = 2.7,
                           colour = "grey15", seed = 2, box.padding = 0.55,
                           point.padding = 0.5, min.segment.length = 0.4,
                           segment.colour = "grey75") +
  scale_fill_manual(values = c(exposure = "#C1440E", outcome = "#4B2E15",
                               `adjustment set` = "#1B6CA8", other = "grey72"),
                    name = NULL,
                    breaks = c("exposure", "outcome", "adjustment set")) +
  labs(title = "A  A pedogenetic graph is an explicit, checkable claim",
       subtitle = sprintf("total effect of tree cover on carbon; the backdoor criterion returns {%s}",
                          paste(nice[aset], collapse = ", "))) +
  theme_map() + theme(legend.position = "top")

# the graph's own implied independencies, tested
have9 <- c("soc_topsoil_gkg","wc_bio_01","wc_bio_12","wc_landcover_trees",
           "soilgrids_clay","soilgrids_sand","soilgrids_bdod","elev","slope")
dd9 <- prof
dd9$soc_topsoil_gkg <- dd9$soc; dd9$wc_bio_01 <- dd9$mat; dd9$wc_bio_12 <- dd9$map
dd9$wc_landcover_trees <- dd9$trees; dd9$soilgrids_clay <- dd9$clay
dd9$soilgrids_sand <- dd9$sand; dd9$soilgrids_bdod <- dd9$bdod
keep9 <- vapply(seq_len(nrow(E)), function(i)
  as.character(E$v[i]) %in% have9 && as.character(E$w[i]) %in% have9, logical(1))
sub9 <- dagitty::dagitty(paste0("dag{", paste(sprintf("%s -> %s", E$v[keep9], E$w[keep9]),
                                              collapse = " "), "}"))
LT <- dagitty::localTests(sub9, dd9[stats::complete.cases(dd9[, have9]), have9],
                          type = "cis")
LT$reject <- LT$p.value < 0.05
pd2 <- ggplot(LT, aes(x = abs(estimate), fill = reject)) +
  geom_histogram(bins = 26, colour = "white", linewidth = 0.15) +
  scale_fill_manual(values = c(`FALSE` = "#2E7D5B", `TRUE` = "#A8322D"),
                    labels = c("compatible", "rejected at 5%"), name = NULL) +
  labs(title = "B  ... and this graph fails its own test",
       subtitle = sprintf("%d of %d implied conditional independencies are rejected; the largest\nviolated partial correlation is %.2f",
                          sum(LT$reject), nrow(LT), max(abs(LT$estimate))),
       x = "Absolute partial correlation that the graph implies should be zero",
       y = "Count") +
  theme_edaphos() + theme(legend.position = "top")

fig_dag <- pd1 / pd2 + plot_layout(heights = c(1.35, 1))
save_fig(fig_dag, "Fig2", 8.2, 8.2)
}

# =============================================================================
# Pillar 8 — neural operators over depth-function space
# =============================================================================
if (need("Fig10")) {
message("Pillar 8: neural operators")
set.seed(5)
n_site <- 140L
dep_tr <- c(5, 15, 30, 50, 75, 100)          # training depths
site   <- br_cerrado[sample(nrow(br_cerrado), n_site), c("twi", "map_mm", "elev", "slope")]
Xs     <- scale(as.matrix(site))
# depth profiles generated by the Pillar-2 pedogenetic equation, per site
lam <- 0.02 + 0.02 * plogis(Xs[, "twi"]); mu_ <- 0.008 + 0.008 * plogis(Xs[, "map_mm"])
y0_ <- 30 + 8 * Xs[, "map_mm"]; yinf <- 3 + 1.5 * Xs[, "elev"]
prof_fun <- function(z, i) yinf[i] + (y0_[i] - yinf[i]) *
  exp(-lam[i] / mu_[i] * (1 - exp(-mu_[i] * z)))
Ytr <- t(vapply(seq_len(n_site), function(i) prof_fun(dep_tr, i) +
                  stats::rnorm(length(dep_tr), 0, 0.4), numeric(length(dep_tr))))
tr <- 1:110; te <- 111:n_site
don <- no_deeponet_fit(dep_tr, Ytr[tr, ], Xs[tr, ], backend = "r",
                       branch_hidden = 24L, trunk_hidden = 24L, epochs = 500L,
                       lr = 0.02, seed = 5L)
dep_new <- seq(2, 110, by = 2)               # includes depths never trained on
pr <- predict(don, Xs[te, ], newdepths = dep_new)
truth <- t(vapply(te, function(i) prof_fun(dep_new, i), numeric(length(dep_new))))

show_i <- 1:6
pf <- do.call(rbind, lapply(show_i, function(k) rbind(
  data.frame(z = dep_new, y = truth[k, ], kind = "Truth", site = k),
  data.frame(z = dep_new, y = pr[k, ],    kind = "Operator prediction", site = k))))
obs <- do.call(rbind, lapply(show_i, function(k)
  data.frame(z = dep_tr, y = Ytr[te[k], ], site = k)))
p8a <- ggplot(pf, aes(y, -z)) +
  geom_path(aes(colour = kind, linetype = kind), linewidth = 0.8) +
  geom_point(data = obs, aes(y, -z), inherit.aes = FALSE, size = 1.2,
             colour = "grey25") +
  facet_wrap(~site, nrow = 2, labeller = labeller(site = function(v) paste("Site", v))) +
  scale_colour_manual(values = c(Truth = "grey45",
                                 `Operator prediction` = "#7B2D8E"), name = NULL) +
  scale_linetype_manual(values = c(Truth = 2, `Operator prediction` = 1), name = NULL) +
  scale_y_continuous(breaks = seq(0, -100, by = -25), labels = abs(seq(0, 100, by = 25))) +
  labs(title = "A  One trained operator emits the whole profile, at any depth",
       subtitle = "held-out sites; points are the six training depths, the curve is evaluated every 2 cm",
       x = expression(paste("Organic carbon (g kg"^-1, ")")), y = "Depth (cm)") +
  theme_edaphos() + theme(legend.position = "top")

err <- data.frame(z = dep_new,
                  rmse = sqrt(colMeans((truth - pr)^2)),
                  trained = dep_new %in% dep_tr)
p8b <- ggplot(err, aes(z, rmse)) +
  geom_col(aes(fill = trained), width = 1.6) +
  scale_fill_manual(values = c(`FALSE` = "#B8B3AC", `TRUE` = "#7B2D8E"),
                    labels = c("depth never seen in training", "training depth"),
                    name = NULL) +
  labs(title = "B  Error at depths the operator was never trained on",
       subtitle = "the operator interpolates the depth axis rather than treating each depth as a task",
       x = "Depth (cm)", y = expression(paste("RMSE across held-out sites (g kg"^-1, ")"))) +
  theme_edaphos() + theme(legend.position = "top")

fig_no <- p8a / p8b + plot_layout(heights = c(1.5, 1))
save_fig(fig_no, "Fig10", 8.6, 7.6)
}

# =============================================================================
# Pillar 4 — self-supervised foundation encoder
# =============================================================================
if (need("Fig6")) {
message("Pillar 4: foundation encoder (trains a small MoCo)")
gg2 <- 45L
uxx <- sort(unique(br_cerrado$x)); uyy <- sort(unique(br_cerrado$y))
lay <- lapply(c("elev", "slope", "twi", "map_mm", "ndvi"), function(v) {
  m <- matrix(NA_real_, gg2, gg2)
  m[cbind(match(br_cerrado$x, uxx), match(br_cerrado$y, uyy))] <- br_cerrado[[v]]
  (m - mean(m, na.rm = TRUE)) / stats::sd(m, na.rm = TRUE)
})
stk <- terra::rast(lapply(lay, function(m) terra::rast(m)))
names(stk) <- c("elev", "slope", "twi", "map_mm", "ndvi")
ds4 <- foundation_tile_dataset(stk, patch_size = 8L, n_patches = 700L, seed = 2L)
moc <- foundation_moco_pretrain_tiles(ds4, feature_dim = 48L, proj_dim = 24L,
                                      queue_size = 256L, batch_size = 32L,
                                      epochs = 700L, lr = 1e-3, device = "cpu",
                                      seed = 2L, verbose = FALSE)
lh <- moc$loss_history
p4a <- ggplot(data.frame(step = seq_along(lh), loss = lh), aes(step, loss)) +
  geom_hline(yintercept = log(1 + moc$queue_size), linetype = 2, colour = "grey45") +
  annotate("text", x = length(lh), y = log(1 + moc$queue_size),
           label = "uninformative reference, log(1 + K)", hjust = 1.02, vjust = -0.6,
           size = 2.6, colour = "grey40") +
  geom_line(colour = "#1B6CA8", alpha = 0.35, linewidth = 0.3) +
  geom_smooth(se = FALSE, method = "loess", formula = y ~ x, span = 0.3,
              colour = "#1B6CA8", linewidth = 1) +
  labs(title = "A  Contrastive pre-training, no labels used",
       subtitle = sprintf("InfoNCE over %d unlabelled patches; falls from %.2f to %.2f, well below chance",
                          ds4$n_patches, lh[1], min(lh)),
       x = "Optimiser step", y = "InfoNCE loss") +
  theme_edaphos()

set.seed(21)
patch4 <- ds4$sample(600L)                 # $sample is a sampler function
emb4 <- foundation_moco_embed(moc, patch4)
pc4  <- stats::prcomp(emb4, center = TRUE, scale. = TRUE)
vex  <- 100 * pc4$sdev^2 / sum(pc4$sdev^2)
cent <- ds4$patch_cells
pdf4 <- data.frame(PC1 = pc4$x[, 1], PC2 = pc4$x[, 2],
                   twi  = apply(patch4[, which(names(stk) == "twi"), , ], 1, mean),
                   elev = apply(patch4[, which(names(stk) == "elev"), , ], 1, mean))
p4b <- ggplot(pdf4, aes(PC1, PC2, colour = twi)) +
  geom_point(size = 1.1, alpha = 0.85) +
  scale_colour_viridis_c(option = "mako", direction = -1, name = "mean TWI\nin patch") +
  labs(title = "B  The embedding organises by landscape position",
       subtitle = sprintf("principal components of the %d-dimensional encoder output (%.0f%% and %.0f%% of variance);\ncolour is a covariate the encoder was never told about explicitly",
                          ncol(emb4), vex[1], vex[2]),
       x = sprintf("PC1 (%.0f%%)", vex[1]), y = sprintf("PC2 (%.0f%%)", vex[2])) +
  theme_edaphos()

fig_fnd <- p4a / p4b + plot_layout(heights = c(1, 1.2))
save_fig(fig_fnd, "Fig6", 8.2, 7.0)
}
