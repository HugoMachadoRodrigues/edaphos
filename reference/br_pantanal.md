# Synthetic Pantanal-wetland soil sample (MS, Brazil)

A 45 x 45 pixel grid covering a ~40 km square in the Brazilian Pantanal
(Mato Grosso do Sul) with the same column schema as
[`br_cerrado`](https://hugomachadorodrigues.github.io/edaphos/reference/br_cerrado.md).
Distinct distributions vs Cerrado:

## Usage

``` r
br_pantanal
```

## Format

A data frame with 2025 rows and 8 columns: same schema as
[`br_cerrado`](https://hugomachadorodrigues.github.io/edaphos/reference/br_cerrado.md).

## Source

Synthetic; see `data-raw/prepare_br_pantanal.R`.

## Details

- Very flat (elev 80-150 m, slopes 0-3 deg).

- Strongly bimodal TWI and NDVI from the channel/floodplain
  geomorphology.

- Highly variable SOC (8-95 g/kg) shaped by the flood pulse.
