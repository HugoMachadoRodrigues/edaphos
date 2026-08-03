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

pa <- ggplot(tb, aes(x = rmse_mean, y = label, fill = r2_mean > 0)) +
  geom_col(width = 0.62) +
  geom_text(aes(label = sprintf("%.3f", rmse_mean)), hjust = -0.18, size = 2.9,
            colour = "grey25") +
  scale_fill_manual(values = c(`TRUE` = PAL[["cool"]], `FALSE` = PAL[["bad"]]),
                    guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.13))) +
  labs(title = "A  Predictive accuracy", x = "RMSE, log1p(g/kg) (lower is better)",
       y = NULL, subtitle = "red: explains less than the training-fold mean") +
  theme_edaphos()

pb <- ggplot(tb, aes(x = r2_mean, y = label, colour = r2_mean > 0)) +
  geom_vline(xintercept = 0, colour = "grey45", linetype = 2) +
  geom_segment(aes(x = 0, xend = r2_mean, yend = label), linewidth = 1.1) +
  geom_point(size = 3.1) +
  scale_colour_manual(values = c(`TRUE` = PAL[["good"]], `FALSE` = PAL[["bad"]]),
                      guide = "none") +
  labs(title = "B  Skill against the achievable null",
       subtitle = "R-squared vs each fold's training mean",
       x = "R-squared", y = NULL) +
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
save_fig(fig_bench, "Fig7", 9.2, 7.4)

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
save_fig(fig_causal, "Fig8", 7.6, 7.2)

# =============================================================================
# Fig 4 — Pillar 2: the depth profile and its unidentified asymptote
# =============================================================================
message("Fig 4: pedogenetic ODE")
CAP <- ex("capstone_campaign_results.rds")
ped <- CAP$piml_profile_obs
fitb <- piml_profile_fit_bayesian(ped$depth_mid, ped$soc_g_kg, method = "laplace", seed = 7L)
dz <- seq(0, 150, by = 2)
pp <- predict(fitb, newdepths = dz, interval = 0.95)
pdf_ <- data.frame(depth = dz, mean = pp$mean, lo = pp$lower, hi = pp$upper)

pprof <- ggplot() +
  geom_ribbon(data = pdf_, aes(y = -depth, xmin = lo, xmax = hi),
              fill = PAL[["soc"]], alpha = 0.18) +
  geom_path(data = pdf_, aes(x = mean, y = -depth), colour = PAL[["soc"]], linewidth = 1) +
  geom_point(data = ped, aes(x = soc_g_kg, y = -depth_mid), colour = PAL[["accent"]],
             size = 2.6) +
  scale_y_continuous(breaks = seq(0, -150, by = -25), labels = abs(seq(0, 150, by = 25))) +
  labs(title = "A  Depth profile as the solution of an equation",
       subtitle = expression(paste("d", italic(y), "/d", italic(z), " = -", lambda[0],
                                   " exp(-", mu, italic(z), ")(", italic(y), " - ",
                                   italic(y)[infinity], "); ribbon is the 95% posterior")),
       x = expression(paste("Organic carbon (g kg"^-1, ")")), y = "Depth (cm)") +
  theme_edaphos()

ptab <- CAP$piml_params_table
ptab$param <- factor(ptab$param, levels = rev(c("lambda0", "mu", "y0", "y_inf")))
ptab$ident <- ifelse(ptab$param == "y_inf", "not identified", "identified")
ppar <- ggplot(ptab, aes(y = param, colour = ident)) +
  geom_vline(xintercept = 0, linetype = 2, colour = "grey55") +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi), height = 0.16, linewidth = 0.9) +
  geom_point(aes(x = mean), size = 3.2) +
  facet_wrap(~param, scales = "free", ncol = 1, strip.position = "left") +
  scale_colour_manual(values = c(identified = PAL[["cool"]],
                                 `not identified` = PAL[["bad"]]), name = NULL) +
  labs(title = "B  Posterior of the four parameters",
       subtitle = "y-infinity, the deep asymptote, spans physically impossible\nnegative carbon: seven upper-metre horizons do not constrain it",
       x = "Posterior mean and 95% interval", y = NULL) +
  theme_edaphos() +
  theme(axis.text.y = element_blank(), legend.position = "top",
        strip.placement = "outside", strip.text.y.left = element_text(angle = 0))

fig_ode <- pprof | ppar
save_fig(fig_ode, "Fig2", 9.0, 4.6)

message("done -> ", OUT)

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
maps$panel <- factor(maps$panel, levels = c("Observed", "ConvLSTM forecast"))
maps$month <- factor(maps$month, levels = sprintf("Month %d", leads))

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
enkf$panel <- factor(enkf$panel, levels = c("Prior (forecast)",
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
save_fig(fig_temporal, "Fig3", 9.4, 7.6)

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
gram$panel <- factor(gram$panel, levels = c("Quantum fidelity kernel", "Gaussian (RBF) kernel"))

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
save_fig(fig_quantum, "Fig4", 8.4, 7.2)

# =============================================================================
# Fig 7 — Pillar 9: diffusion, reference vs trained sampler
# =============================================================================
message("Fig 7: diffusion (fits two models, ~1 min)")
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
pl$panel <- factor(pl$panel, levels = c("Real", "Pure-R\nreference", "Trained\n(torch)"))
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
stats_df$set <- factor(stats_df$set, levels = levels(pl$panel))
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
save_fig(fig_diff, "Fig5", 8.6, 7.4)

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
elen <- sqrt((edges$x - edges$xend)^2 + (edges$y - edges$yend)^2)
gstat <- rbind(data.frame(v = deg,  panel = "Node degree"),
               data.frame(v = elen, panel = "Edge length (degrees)"))
gstat$panel <- factor(gstat$panel, levels = c("Node degree", "Edge length (degrees)"))
p10b <- ggplot(gstat, aes(v, fill = panel)) +
  geom_histogram(bins = 34, colour = "white", linewidth = 0.15) +
  facet_wrap(~panel, scales = "free", nrow = 1) +
  scale_fill_manual(values = c("Node degree" = "#7B5AA6",
                               "Edge length (degrees)" = "#2E7D5B"), guide = "none") +
  labs(title = "B  What the graph encodes",
       subtitle = sprintf(paste("the k-nearest-neighbour relation is asymmetric, so after symmetrising,",
                                "degree\nranges %d-%d rather than sitting at k = 6; most edges are short but a tail",
                                "reaches\nacross sparsely surveyed ground"), min(deg), max(deg)),
       x = NULL, y = "Count") +
  theme_edaphos()

fig_graph <- p10a / p10b + plot_layout(heights = c(1.5, 1))
save_fig(fig_graph, "Fig6", 7.8, 8.0)
