# Canonical CLORPT pedogenetic DAG

Encodes Jenny (1941)'s Climate / Organisms / Relief / Parent material /
Time factors as a directed acyclic graph on common soil variables.
Useful as a textbook baseline DAG in causal analyses and as a template
to extend for a specific region.

## Usage

``` r
causal_clorpt_dag()
```

## Value

A `dagitty` graph object.

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE)) {
  dag <- causal_clorpt_dag()
  print(names(dag))

  # Only four of the five CLORPT factors come out exogenous:
  # Organisms does not, because the graph asserts Climate ->
  # Organisms.
  print(dagitty::exogenousVariables(dag))

  # Trap: these are conceptual labels, not column names. The DAG
  # shares no node at all with the bundled br_cerrado grid, so the
  # two cannot be handed to causal_estimate_effect() together.
  print(intersect(names(dag), names(br_cerrado)))

  # CEC is a common effect of Clay and SOC, i.e. a collider. Given
  # the shared causes Climate and Time the two are d-separated ...
  print(dagitty::dconnected(dag, "SOC", "Clay", c("Climate", "Time")))
  # ... and adding CEC to the conditioning set re-opens the path,
  # manufacturing a clay-carbon association that is not causal.
  # This is what "control for every covariate we measured" buys you.
  print(dagitty::dconnected(dag, "SOC", "Clay",
                            c("Climate", "Time", "CEC")))
}
#>  [1] "CEC"            "Clay"           "Climate"        "Erosion"       
#>  [5] "Organisms"      "ParentMaterial" "Relief"         "SOC"           
#>  [9] "TWI"            "Time"           "Weathering"     "pH"            
#> [1] "Climate"        "ParentMaterial" "Relief"         "Time"          
#> character(0)
#> [1] FALSE
#> [1] TRUE
```
