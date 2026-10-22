# Pilar 3 on real data — 4D NDVI forecasting with sequential Bayesian assimilation

## 1. Why this vignette exists

The original Pillar 3 vignette
([`vignette("pilar3-4d-soc")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar3-4d-soc.md))
demonstrates the stacked ConvLSTM ([Shi et al. 2015](#ref-Shi2015)) on
the synthetic SOC cube produced by
[`temporal_synth_soc_cube()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_synth_soc_cube.md).
As of **v1.5.0** the Pillar 3 story runs on **real Cerrado
spatio-temporal data**: 168 monthly time steps (January 2010 – December
2023) of three channels assembled over a 2° × 2° AoI centred on the
Goiás / Minas Gerais triple-junction (lon –48 to –46, lat –16 to –14, 10
× 10 = 100 cells at 0.2° resolution):

1.  **NDVI** from MODIS MOD13Q1 250 m 16-day composites aggregated to
    monthly means ([Didan 2015](#ref-Didan2015mod13q1)) — the forecast
    target.
2.  **Monthly precipitation** (mm/month) from NASA POWER (MERRA-2
    bias-corrected) monthly mean daily totals ([Stackhouse Jr. et al.
    2018](#ref-Stackhouse2018power); [Sparks
    2018](#ref-Sparks2018nasapower)). We originally targeted CHIRPS
    0.05° ([Funk et al. 2015](#ref-Funk2015chirps)) but the Climate
    Hazards Group data portal was returning HTTP 403 for every v2.0
    `global_monthly/tifs/` request at the v1.5.0 freeze; POWER is a
    fully-open NASA alternative with comparable accuracy over the
    Cerrado and a single-point REST API that returns the full 14-year
    series in one call.
3.  **Mean monthly air temperature** (°C) from NASA POWER T2M
    ([Stackhouse Jr. et al. 2018](#ref-Stackhouse2018power)), fetched in
    the same REST call as the precipitation. (We originally targeted
    WorldClim 2.1 static climatology ([Fick and Hijmans
    2017](#ref-Fick2017worldclim)) but the `geodata.ucdavis.edu` server
    was in maintenance at the v1.5.0 freeze; POWER T2M has the added
    benefit of being **year-specific** rather than a long- term average,
    so all three channels now carry genuine year-to- year climate
    variability.)

The vignette also demonstrates the v1.5.0 new function
[`temporal_kalman_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_kalman_update.md):
a stochastic Ensemble Kalman Filter ([Evensen 1994](#ref-Evensen1994);
[Burgers et al. 1998](#ref-Burgers1998enkf)) that sequentially
assimilates new in-situ observations into the ConvLSTM forecast without
retraining the network.

> **The results in this article have been withdrawn.** They need `$obs`,
> `$scaling`, `$truth_future` from `temporal_cerrado_results.rds`, which
> were removed on 2026-08-28 because they carried observed values at
> named coordinates. The package can no longer reproduce the forecast
> and assimilation figures, so the article stops here rather than
> display numbers that nothing in it backs. See `PROVENANCE.md` and
> `data-raw/build/stripped_elements.csv` in the repository.

Burgers, Gerrit, Peter Jan van Leeuwen, and Geir Evensen. 1998.
“Analysis Scheme in the Ensemble Kalman Filter.” *Monthly Weather
Review* 126 (6): 1719–24.
<https://doi.org/10.1175/1520-0493(1998)126%3C1719:ASITEK%3E2.0.CO;2>.

Didan, Kamel. 2015. *MOD13Q1 MODIS/Terra Vegetation Indices 16-Day L3
Global 250 m SIN Grid V006*. NASA EOSDIS Land Processes DAAC.
<https://doi.org/10.5067/MODIS/MOD13Q1.006>.

Evensen, Geir. 1994. “Sequential Data Assimilation with a Nonlinear
Quasi-Geostrophic Model Using Monte Carlo Methods to Forecast Error
Statistics.” *Journal of Geophysical Research: Oceans* 99 (C5):
10143–62. <https://doi.org/10.1029/94JC00572>.

Fick, S. E., and R. J. Hijmans. 2017. “WorldClim 2: New 1-Km Spatial
Resolution Climate Surfaces for Global Land Areas.” *International
Journal of Climatology* 37 (12): 4302–15.
<https://doi.org/10.1002/joc.5086>.

Funk, Chris, Pete Peterson, Martin Landsfeld, et al. 2015. “The Climate
Hazards Infrared Precipitation with Stations — a New Environmental
Record for Monitoring Extremes.” *Scientific Data* 2: 150066.
<https://doi.org/10.1038/sdata.2015.66>.

Shi, X., Z. Chen, H. Wang, D.-Y. Yeung, W.-K. Wong, and W.-C. Woo. 2015.
“Convolutional LSTM Network: A Machine Learning Approach for
Precipitation Nowcasting.” *Advances in Neural Information Processing
Systems* 28: 802–10.

Sparks, Adam H. 2018. “nasapower: A NASA POWER Global Meteorology,
Surface Solar Energy and Climatology Data Client for R.” *Journal of
Open Source Software* 3 (30): 1035.
<https://doi.org/10.21105/joss.01035>.

Stackhouse Jr., Paul W., David Westberg, James M. Hoell, William S.
Chandler, and Taiping Zhang. 2018. *NASA Prediction of Worldwide Energy
Resources (POWER) — Release 8 methodology*. NASA Langley Research
Center.
