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
