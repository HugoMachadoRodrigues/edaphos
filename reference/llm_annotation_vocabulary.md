# Canonical pedometric vocabulary for LLM-KG claims

Controlled list of variable names used by the prompt template in
[`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md)
and by the gold-standard annotation tooling. Keeping these labels stable
across thousands of abstracts is essential for computing precision /
recall against the gold standard: free-form labels like `"tree_cover"`
vs `"tree cover"` vs `"vegetation_cover"` would artificially depress
matching accuracy.

## Usage

``` r
llm_annotation_vocabulary()
```

## Value

Character vector of canonical variable names.

## Examples

``` r
head(llm_annotation_vocabulary(), 10)
#>  [1] "precipitation"             "mean_annual_precipitation"
#>  [3] "temperature"               "mean_annual_temperature"  
#>  [5] "elevation"                 "slope"                    
#>  [7] "aspect"                    "twi"                      
#>  [9] "clay"                      "sand"                     
```
