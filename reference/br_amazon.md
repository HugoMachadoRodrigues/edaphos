# Synthetic Amazon-rainforest soil sample (NW Brazil)

A 45 x 45 pixel grid covering a ~40 km square near Manaus (Amazonas)
with the same column schema as
[`br_cerrado`](https://hugomachadorodrigues.github.io/edaphos/reference/br_cerrado.md).
Distinct distributions vs Cerrado:

## Usage

``` r
br_amazon
```

## Format

A data frame with 2025 rows and 8 columns: same schema as
[`br_cerrado`](https://hugomachadorodrigues.github.io/edaphos/reference/br_cerrado.md).

## Source

Synthetic; see `data-raw/prepare_br_amazon.R`.

## Details

- Lower elevation (50-300 m) and gentler slopes (0-8 deg).

- Much higher rainfall (2200-3000 mm/y) and NDVI (0.75-0.95).

- Higher and more right-skewed SOC (35-90 g/kg).

Drop-in replacement for `br_cerrado` in any pillar / vignette – useful
as a second-region smoke test.
