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

fig1 <- (map | dens) / cov_p + plot_layout(heights = c(1.45, 1))
save_fig(fig1, "Fig1", 9.2, 8.0)

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

fig3 <- (pa | pb) / (pc | pd) + plot_layout(heights = c(1, 1.15))
save_fig(fig3, "Fig2", 9.2, 7.4)

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

fig4 <- pf / pr + plot_layout(heights = c(1.25, 1))
save_fig(fig4, "Fig3", 7.6, 7.2)

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

fig5 <- pprof | ppar
save_fig(fig5, "Fig4", 9.0, 4.6)

message("done -> ", OUT)
