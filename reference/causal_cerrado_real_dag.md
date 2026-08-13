# Real-data Cerrado pedogenetic DAG

Structural causal model over the exact covariate column names that
appear in the v1.3.1 case-study bundle (WoSIS 0-10 cm topsoil SOC +
SoilGrids + WorldClim + SRTM + WorldCover). Unlike
[`causal_cerrado_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_cerrado_dag.md),
which uses short schematic labels (`elev`, `slope`, `twi`, `map_mm`,
`ndvi`, `soc`), this DAG is wired against `bio1`, `bio12`,
`soilgrids_clay`, `wc_landcover_trees` etc. so that
[`causal_estimate_effect()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_estimate_effect.md)
can consume the real profiles data frame without renaming.

## Usage

``` r
causal_cerrado_real_dag()
```

## Value

A `dagitty` DAG whose nodes match the column names of the `profiles`
data frame in `inst/extdata/case_cerrado_results.rds`.

## Details

The edges encode six classes of Cerrado pedogenetic relations:

- Relief -\> climate:

  Elevation modulates temperature (adiabatic lapse) and precipitation
  (orographic forcing) via `elev -> bio1`, `elev -> bio12`,
  `elev -> slope`.

- Climate -\> vegetation / land cover:

  Bio1 (mean annual temperature) and bio12 (mean annual precipitation)
  drive the fraction of land covered by trees, grassland and cropland.

- Relief -\> texture:

  Steep slopes export fine fractions (`slope -> soilgrids_clay`) and
  accumulate coarse fractions downslope (`slope -> soilgrids_sand`).

- Texture -\> bulk density:

  Fine-textured soils compact differently
  (`soilgrids_clay -> soilgrids_bdod`).

- Climate + texture -\> SOC (direct):

  Both sides drive decomposition vs mineral protection.

- Land cover -\> SOC:

  Native savanna vs. pasture vs. cropland produce 3-4x SOC differences
  in Cerrado topsoil; the land-cover fractions are the dominant single
  factor.

## See also

[`causal_cerrado_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_cerrado_dag.md)
for the short-label schematic version;
[`causal_adjustment_set()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_adjustment_set.md)
and
[`causal_estimate_effect()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_estimate_effect.md)
for identification + estimation.

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE)) {
  dag  <- causal_cerrado_real_dag()
  prof <- readRDS(system.file("extdata", "case_cerrado_results.rds",
                              package = "edaphos"))$profiles

  # The whole point of this DAG: all of its nodes are real columns
  # of the WoSIS case-study table, whereas the schematic
  # causal_cerrado_dag() shares only two names with it.
  print(all(names(dag) %in% names(prof)))
  print(intersect(names(causal_cerrado_dag()), names(prof)))

  # Total vs direct effect of clay on topsoil SOC. The total effect
  # only needs slope; the direct effect must additionally block bulk
  # density (a mediator) and then sand as well, because bdod is a
  # collider of clay and sand.
  print(causal_adjustment_set(dag, "soilgrids_clay",
                              "soc_topsoil_gkg", effect = "total"))
  print(causal_adjustment_set(dag, "soilgrids_clay",
                              "soc_topsoil_gkg", effect = "direct"))

  # Roughly two thirds of the clay effect is mediated: the total
  # slope is about 0.54 g/kg SOC per unit of soilgrids_clay, the
  # direct one about 0.19 with an interval that only just clears
  # zero. Report which one you mean.
  print(causal_estimate_effect(prof, dag, "soilgrids_clay",
                               "soc_topsoil_gkg", effect = "total"))
  print(causal_estimate_effect(prof, dag, "soilgrids_clay",
                               "soc_topsoil_gkg", effect = "direct"))
}
#> [1] TRUE
#> [1] "elev"  "slope"
#> [1] "slope"
#> [1] "slope"          "soilgrids_bdod" "soilgrids_sand"
#> <edaphos_causal_effect>
#>   soilgrids_clay -> soc_topsoil_gkg   (estimator: lm)
#>   adjustment set : {slope}
#>   total effect   : 0.5371   (95% CI: 0.4239, 0.6504)
#>   naive effect   : 0.5257   (un-adjusted, likely confounded)
#> <edaphos_causal_effect>
#>   soilgrids_clay -> soc_topsoil_gkg   (estimator: lm)
#>   adjustment set : {slope, soilgrids_bdod, soilgrids_sand}
#>   direct effect  : 0.1949   (95% CI: 0.009367, 0.3804)
#>   naive effect   : 0.5257   (un-adjusted, likely confounded)
```
