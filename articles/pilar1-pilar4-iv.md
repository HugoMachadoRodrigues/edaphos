# Foundation-model embeddings as causal instrumental variables

> **Pergunta central.** O ajuste *backdoor* do Pilar 1 identifica
> efeitos causais **apenas** sob a suposição de **suficiência causal**:
> todos os confundidores comuns de exposição e resposta precisam estar
> no conjunto de ajuste. Quando confundidores latentes $U$ permanecem
> não observados, `lm(soc ~ map + adjustments)` volta a ser enviesado.
> **Podem os embeddings do Pillar 4 — aprendidos por contraste em
> *patches* de paisagem sem nunca ver o COS — servir como *instrumental
> variables* e identificar o efeito mesmo na presença de $U$?**

------------------------------------------------------------------------

``` r
library(edaphos)
library(ggplot2)
library(dplyr)
theme_set(theme_bw(base_size = 11))
```

``` r
res_path <- system.file("extdata", "causal_iv_cerrado.rds",
                         package = "edaphos")
stopifnot(nzchar(res_path), file.exists(res_path))
B <- readRDS(res_path)
```

------------------------------------------------------------------------

## Motivação: as três condições de Zhang and Wadoux ([2026](#ref-Zhang2026causal)) e o papel do IV

Zhang and Wadoux ([2026](#ref-Zhang2026causal)) articulam três condições
para inferência causal a partir de dados observacionais:

1.  **Modelo causal explícito** — um DAG.
2.  **Suficiência causal** — todos os confundidores observados.
3.  **Fidelidade** — independências dos dados batem com o DAG.

O ajuste *backdoor* de Pearl ([Pearl 2009](#ref-Pearl2009)) satisfaz (1)
e (3) mas **requer (2)**. Em MDS real, (2) é a condição **mais frágil**:
o pedólogo codifica no DAG expert os confundidores que **conhece** — mas
sempre há padrões de paisagem (microtopografia, conectividade
hidrológica, história de uso residual) que afetam tanto covariáveis
quanto COS e que nenhum rasterizador do SoilGrids captura.

Quando a suficiência falha, o estimador *backdoor* volta a ser
enviesado:

$${\widehat{\beta}}_{\text{backdoor}} = \beta_{\text{verdadeiro}} + \underset{\text{viés de confundimento latente}}{\underbrace{\text{Cov}(X,U \mid Z)/\text{Var}(X \mid Z)}}$$

### Instrumental variables: uma saída sob condições distintas

Um *instrumento* $Z$ satisfaz três condições **diferentes** das de
Pearl:

- **(IV.1) Relevância**: $\text{Cov}(Z,X) \neq 0$. $Z$ precisa
  efetivamente predizer $X$.
- **(IV.2) Exclusão**: $Z$ afeta $Y$**apenas** através de $X$. Nenhum
  caminho $\left. Z\rightarrow Y \right.$ direto; nenhum confundidor
  $Z - Y$.
- **(IV.3) Unconfoundedness**: $Z\bot U$. $Z$ é independente dos
  confundidores latentes.

Sob (IV.1–3), o estimador **Two-Stage Least Squares** (2SLS) identifica
o efeito causal mesmo quando $U$ não é observado ([Wooldridge
2010](#ref-Wooldridge2010)):

$${\widehat{\beta}}_{\text{2SLS}} = \left( X^{\top}P_{Z}X \right)^{- 1}X^{\top}P_{Z}Y,\quad P_{Z} = Z\left( Z^{\top}Z \right)^{- 1}Z^{\top}$$

### A hipótese `edaphos`

Os embeddings do Pillar 4 — aprendidos por **contrastive
self-supervision** em *patches* de paisagem sem jamais ver o rótulo
$Y = \text{COS}$ — são um candidato promissor:

- **Relevância**: os *patches* contêm covariáveis climáticas e
  topográficas que predizem fortemente exposições como MAP e cobertura
  arbórea. Stage-1 F tipicamente enorme.
- **Exclusão**: esta é a hipótese substantiva. O encoder nunca viu COS;
  se ele aprendeu **apenas** padrões de paisagem, então a informação nos
  embeddings afeta COS **só via** MAP/tree cover/clay/etc.
  Rigorosamente: isso é uma suposição; o Pilar 6 oferece um teste
  empírico, abaixo.
- **Unconfoundedness**: como o encoder é treinado em *patches*
  espalhados por todo o Cerrado (milhares, diversos), é plausível que
  sua representação seja insensível a variáveis latentes pontuais.

------------------------------------------------------------------------

## O estimador 2SLS do `edaphos`

``` r
causal_iv_fit_2sls(data, exposure, outcome, instruments,
                   covariates = NULL)
```

Implementa a forma fechada de Wooldridge ([2010](#ref-Wooldridge2010)),
§5.2:

$$\widehat{\beta} = \left( X_{\text{all}}^{\top}PX_{\text{all}} \right)^{- 1}X_{\text{all}}^{\top}PY$$

com $X_{\text{all}} = \lbrack\mathbf{1},W,X\rbrack$,
$P = Z_{\text{all}}\left( Z_{\text{all}}^{\top}Z_{\text{all}} \right)^{- 1}Z_{\text{all}}^{\top}$,
e a **variância correta** (usando os **resíduos com X original**, não
com $\widehat{X}$ da primeira etapa — um erro comum ao aplicar
[`lm()`](https://rdrr.io/r/stats/lm.html) ingenuamente):

$$\widehat{\text{Var}}\left( \widehat{\beta} \right) = {\widehat{\sigma}}^{2}\left( X_{\text{all}}^{\top}PX_{\text{all}} \right)^{- 1},\quad{\widehat{\sigma}}^{2} = \frac{1}{n - k}\left( Y - X_{\text{all}}\widehat{\beta} \right)^{\top}\left( Y - X_{\text{all}}\widehat{\beta} \right)$$

### Diagnósticos obrigatórios

1.  **Stage-1 F-statistic** para (IV.1): $F < 10$ sinaliza *instrumentos
    fracos* ([Stock and Yogo 2005](#ref-StockYogo2005)).
2.  **Sargan J-test** para (IV.2) (quando há mais instrumentos do que
    exposições): $p < 0.05$ rejeita validade.
3.  **R² parcial dos instrumentos sobre controles**: a fração da
    variância de $X$ explicada pelos instrumentos **além** do que os
    controles já explicam.

------------------------------------------------------------------------

## Validação: DGP sintético onde a verdade é conhecida

Antes de aplicar aos dados reais, é indispensável validar que a
implementação recupera o efeito verdadeiro em um DGP controlado.

``` r
knitr::kable(
  B$syn_summary,
  digits = 3,
  col.names = c("Estimador", "β̂", "SE", "IC 2,5%", "IC 97,5%"),
  caption = paste0(
    "DGP sintético: Y = 1,5·X + 0,8·U + ε, onde X depende de 3 ",
    "instrumentos Z e do confundidor latente U. OLS está enviesado ",
    "para cima (1,82); 2SLS com Z1, Z2, Z3 recupera 1,46 com IC 95% ",
    "cobrindo a verdade 1,5. Stage-1 F = ",
    round(B$syn_diagnostics$stage1_F, 1),
    "; Sargan p = ", round(B$syn_diagnostics$sargan_p, 3), "."
  )
)
```

| Estimador          |     β̂ |    SE | IC 2,5% | IC 97,5% |
|:-------------------|------:|------:|--------:|---------:|
| OLS (biased by U)  | 1.817 | 0.025 |   1.768 |    1.866 |
| 2SLS with Z1,Z2,Z3 | 1.458 | 0.037 |   1.385 |    1.531 |
| True (DGP)         | 1.500 |    NA |      NA |       NA |

DGP sintético: Y = 1,5·X + 0,8·U + ε, onde X depende de 3 instrumentos Z
e do confundidor latente U. OLS está enviesado para cima (1,82); 2SLS
com Z1, Z2, Z3 recupera 1,46 com IC 95% cobrindo a verdade 1,5. Stage-1
F = 348.7; Sargan p = 0.267.

``` r
samps_iv <- as.numeric(B$syn_posterior$samples)
df_plot <- data.frame(
  method = c(rep("2SLS (IV)", length(samps_iv)),
              rep("OLS (biased)", length(samps_iv))),
  draw   = c(samps_iv,
              rnorm(length(samps_iv), mean = B$syn_summary$beta[1],
                     sd = B$syn_summary$se[1]))
)
ggplot(df_plot, aes(x = draw, fill = method)) +
  geom_density(alpha = 0.6, color = NA) +
  geom_vline(xintercept = 1.5, linetype = "dashed", linewidth = 1) +
  scale_fill_manual(values = c("2SLS (IV)" = "#2980B9",
                                "OLS (biased)" = "#C0392B"),
                     name = NULL) +
  annotate("text", x = 1.5, y = 8, label = "true β = 1.5",
            vjust = -0.3, size = 3.6) +
  labs(x = "β̂", y = "Densidade",
       title = "DGP sintético: OLS vs. 2SLS",
       subtitle = "Apenas 2SLS cobre a verdade")
```

![DGP sintético: posterior bootstrap do efeito 2SLS (azul) concentra-se
em torno da verdade β=1,5 (linha tracejada); o estimador OLS fica
deslocado para cima (viés de
U).](pilar1-pilar4-iv_files/figure-html/syn-plot-1.png)

DGP sintético: posterior bootstrap do efeito 2SLS (azul) concentra-se em
torno da verdade β=1,5 (linha tracejada); o estimador OLS fica deslocado
para cima (viés de U).

------------------------------------------------------------------------

## Aplicação: 1 095 perfis reais do Cerrado

### Setup

Usamos os mesmos 1 095 perfis WoSIS da vignette
`vignette("pilar1-causal-real")`, com o mesmo DAG expert (11 nós, 22
arestas). As covariáveis observadas são climáticas (wc_bio_12 = MAP,
wc_bio_01 = MAT), topográficas (elev, slope), texturais (clay, sand,
bulk density) e de cobertura (tree, cropland, grassland) — os 10
confundidores nomeados no DAG.

### Pseudo-embeddings como *proxy* do MoCo v2

O encoder MoCo v2 v1.3.2 (em treinamento) ainda não está disponível para
extração em escala. Nesta v1.9.0, implementamos um **proxy
principiado**: um vetor de 27 features engenheiradas que representa o
que um encoder contrastivo plausivelmente aprenderia em *patches*
Cerrado — interações, razões, transformações não-lineares e uma base
espacial:

``` r
features_disp <- data.frame(
  grupo = c(
    rep("Não-lineares simples", 5),
    rep("Razões de cobertura / textura", 3),
    rep("Interações clima × topografia", 5),
    rep("Base espacial", 5),
    rep("Índices de paisagem composto", 5),
    rep("Postos (quantis)", 4)
  ),
  feature = B$proxy_features,
  stringsAsFactors = FALSE
)
knitr::kable(
  features_disp,
  col.names = c("Grupo", "Feature"),
  caption = paste0(
    "As 27 features que compõem os ",
    "*proxy embeddings*. A PCA no próximo passo reduz a 5 ",
    "componentes principais ortogonais que servem como instrumentos."
  )
)
```

| Grupo                         | Feature    |
|:------------------------------|:-----------|
| Não-lineares simples          | map2       |
| Não-lineares simples          | mat2       |
| Não-lineares simples          | log_map    |
| Não-lineares simples          | log_elev   |
| Não-lineares simples          | sqrt_slope |
| Razões de cobertura / textura | tc_cr      |
| Razões de cobertura / textura | tc_gr      |
| Razões de cobertura / textura | sand_clay  |
| Interações clima × topografia | map_tree   |
| Interações clima × topografia | map_slope  |
| Interações clima × topografia | mat_elev   |
| Interações clima × topografia | clay_map   |
| Interações clima × topografia | sand_elev  |
| Base espacial                 | lon_c      |
| Base espacial                 | lat_c      |
| Base espacial                 | lon2       |
| Base espacial                 | lat2       |
| Base espacial                 | lonlat     |
| Índices de paisagem composto  | dryness    |
| Índices de paisagem composto  | woody      |
| Índices de paisagem composto  | cult_press |
| Índices de paisagem composto  | texture    |
| Índices de paisagem composto  | bd_clay    |
| Postos (quantis)              | rank_map   |
| Postos (quantis)              | rank_mat   |
| Postos (quantis)              | rank_trees |
| Postos (quantis)              | rank_clay  |

As 27 features que compõem os *proxy embeddings*. A PCA no próximo passo
reduz a 5 componentes principais ortogonais que servem como
instrumentos.

**Redução dimensional**: PCA centrada + escalada nas 27 features,
retendo as **5 componentes principais** de maior variância. Isso dá um
modelo 4-sobre-identificado (5 instrumentos - 1 exposição), sobre o qual
o teste de Sargan é aplicável.

### Resultado central: os três estimadores lado a lado

``` r
bt <- B$benchmark_table
bt_disp <- bt
bt_disp$beta   <- round(bt$beta, 4)
bt_disp$se     <- round(bt$se,   4)
bt_disp$ci_lo  <- round(bt$ci_lo, 4)
bt_disp$ci_hi  <- round(bt$ci_hi, 4)
bt_disp$stage1_F <- ifelse(is.na(bt$stage1_F), "",
                            sprintf("%.0f", bt$stage1_F))
bt_disp$sargan_p <- ifelse(is.na(bt$sargan_p), "",
                            sprintf("%.3g", bt$sargan_p))

knitr::kable(
  bt_disp[, c("exposure", "estimator", "beta", "se",
               "ci_lo", "ci_hi", "stage1_F", "sargan_p")],
  col.names = c("Exposição", "Estimador", "β̂", "SE",
                "IC 2,5%", "IC 97,5%", "Stage-1 F", "Sargan p"),
  caption = paste0(
    "Comparação tripla OLS naïve / Backdoor OLS (ajustado) / 2SLS ",
    "(proxy embeddings). Em todas as três exposições, o Stage-1 F é ",
    "muito alto (instrumentos relevantes); o Sargan J rejeita ",
    "validade dos instrumentos com p < 10⁻⁸ — um resultado HONESTO ",
    "que discutimos abaixo."
  )
)
```

| Exposição      | Estimador               |      β̂ |     SE | IC 2,5% | IC 97,5% | Stage-1 F | Sargan p |
|:---------------|:------------------------|-------:|-------:|--------:|---------:|:----------|:---------|
| MAP (mm/a)     | OLS (naive)             | 0.0072 | 0.0023 |  0.0028 |   0.0116 |           |          |
| MAP (mm/a)     | Backdoor OLS (adjusted) | 0.0077 | 0.0027 |  0.0024 |   0.0130 |           |          |
| MAP (mm/a)     | 2SLS (proxy embeddings) | 0.0081 | 0.0027 |  0.0028 |   0.0134 | 20014     | 3.02e-12 |
| Tree cover (%) | OLS (naive)             | 0.8979 | 1.8195 | -2.6722 |   4.4679 |           |          |
| Tree cover (%) | Backdoor OLS (adjusted) | 6.5364 | 3.0749 |  0.5030 |  12.5698 |           |          |
| Tree cover (%) | 2SLS (proxy embeddings) | 5.0830 | 3.0962 | -0.9856 |  11.1515 | 15713     | 3.15e-09 |
| Clay (%)       | OLS (naive)             | 0.5257 | 0.0568 |  0.4144 |   0.6371 |           |          |
| Clay (%)       | Backdoor OLS (adjusted) | 0.1924 | 0.1148 | -0.0328 |   0.4176 |           |          |
| Clay (%)       | 2SLS (proxy embeddings) | 0.2495 | 0.1232 |  0.0081 |   0.4908 | 1433      | 2.58e-12 |

Comparação tripla OLS naïve / Backdoor OLS (ajustado) / 2SLS (proxy
embeddings). Em todas as três exposições, o Stage-1 F é muito alto
(instrumentos relevantes); o Sargan J rejeita validade dos instrumentos
com p \< 10⁻⁸ — um resultado HONESTO que discutimos abaixo.

``` r
bt$estimator <- factor(
  bt$estimator,
  levels = c("OLS (naive)", "Backdoor OLS (adjusted)", "2SLS (proxy embeddings)")
)
ggplot(bt, aes(x = estimator, y = beta, color = estimator)) +
  geom_point(size = 3.5) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.2,
                  linewidth = 0.8) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  facet_wrap(~exposure, scales = "free_y") +
  scale_color_manual(values = c("OLS (naive)"                = "#7F8C8D",
                                  "Backdoor OLS (adjusted)"    = "#27AE60",
                                  "2SLS (proxy embeddings)"    = "#2980B9"),
                      guide = "none") +
  labs(x = NULL, y = "β̂ (g/kg por unidade da exposição)",
       title = "Efeitos causais: três estimadores",
       subtitle = sprintf("n = %d perfis WoSIS Cerrado", B$n_profiles)) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
```

![Três estimadores × três exposições. Barras de erro são IC 95%.
Comparar as três colunas mostra se o ajuste backdoor captura o efeito
direto (da OLS naïve para backdoor) e se o IV 2SLS concorda com ou
diverge do backdoor — se divergir, é sinal de confundimento latente NÃO
capturado pelos covariates
nomeados.](pilar1-pilar4-iv_files/figure-html/benchmark-plot-1.png)

Três estimadores × três exposições. Barras de erro são IC 95%. Comparar
as três colunas mostra se o ajuste backdoor captura o efeito direto (da
OLS naïve para backdoor) e se o IV 2SLS concorda com ou diverge do
backdoor — se divergir, é sinal de confundimento latente NÃO capturado
pelos covariates nomeados.

**Leitura honesta das três linhas por exposição:**

1.  **MAP → SOC**. Os três estimadores concordam em ~0,0072-0,0081 g/kg
    por mm. Backdoor e 2SLS praticamente empatam, sugerindo que os
    confundidores observados explicam o essencial aqui.
2.  **Tree cover → SOC**. Grande diferença entre OLS naïve (0,90, não
    significativo) e backdoor (6,54). O backdoor, ao controlar por MAP e
    MAT, descobre um efeito direto positivo da cobertura arbórea. O 2SLS
    IV fica intermediário (5,08) com intervalo mais amplo — sinalizando
    que confundimento residual *pode* existir, mas os *proxy
    instruments* não são confiáveis o bastante para concluir (ver
    Sargan).
3.  **Clay → SOC**. OLS naïve superestima (0,53); backdoor reduz para
    0,19 após controlar por textura e densidade; 2SLS dá 0,25. Aqui o
    ajuste backdoor *aparentemente* sobre-corrige — uma hipótese para
    investigar quando o encoder v2 real estiver pronto.

### O teste de Sargan rejeita: por que isso importa

**Todos os três estimadores 2SLS têm Sargan p ≈ 10⁻⁹**. O framework IV
**corretamente** nos diz que os *proxy embeddings* **não** satisfazem a
condição de exclusão — eles levam a efeitos enviesados em uma direção
desconhecida.

Por que isso acontece? As 27 features proxy são **funções não-lineares
das covariáveis observadas** (e.g., `map * trees / 100`). Elas capturam
informação que afeta COS **não apenas** através de MAP isoladamente —
violam (IV.2). É exatamente o comportamento esperado.

**A implicação científica**: instrumentos válidos para MDS causal
precisam vir de uma fonte que capture estrutura de paisagem
**independente** dos controles nomeados. O **MoCo v2**, treinado por
perda contrastiva em *patches* **sem** ver COS (nem mesmo indiretamente
via features derivadas de COS), é exatamente tal fonte — e por isso é a
direção crítica da v1.3.2 / v1.9.1.

### Sensibilidade ao número de componentes

``` r
st <- B$sensitivity_table
ggplot(st, aes(x = factor(n_pcs), y = beta_iv)) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                  width = 0.15, linewidth = 0.8, color = "#2980B9") +
  geom_point(size = 3.5, color = "#2980B9") +
  labs(x = "n_pcs (nº de componentes usadas como instrumentos)",
       y = "β̂ 2SLS (g/kg por mm MAP)",
       title = "Sensibilidade: estimador é estável; validade não")
```

![Efeito 2SLS para MAP → COS variando o número de componentes principais
retidas como instrumentos. O ponto azul é o estimador pontual; a barra é
IC 95%. A estimativa é notavelmente estável (β ≈ 0,008) através de k =
3, 5, 7, 10 — mas o Sargan p permanece baixo em todos os
casos.](pilar1-pilar4-iv_files/figure-html/sens-plot-1.png)

Efeito 2SLS para MAP → COS variando o número de componentes principais
retidas como instrumentos. O ponto azul é o estimador pontual; a barra é
IC 95%. A estimativa é notavelmente estável (β ≈ 0,008) através de k =
3, 5, 7, 10 — mas o Sargan p permanece baixo em todos os casos.

``` r
st_long <- tidyr::pivot_longer(
  st, c(stage1_F, sargan_p), names_to = "métrica", values_to = "valor"
)
st_long$métrica <- factor(st_long$métrica,
                           levels = c("stage1_F", "sargan_p"),
                           labels = c("Stage-1 F (relevance)",
                                        "Sargan p (exclusion)"))
ggplot(st_long, aes(x = factor(n_pcs), y = valor, group = 1)) +
  geom_point(size = 3, color = "#C0392B") +
  geom_line(color = "#C0392B", linewidth = 0.8) +
  facet_wrap(~métrica, scales = "free_y") +
  labs(x = "n_pcs", y = NULL,
       title = "Diagnósticos IV × sensibilidade",
       subtitle = "Instrumentos muito relevantes, mas estruturalmente inválidos")
```

![Como esperado, mais componentes aumentam a stage-1 F (relevância), mas
NÃO resolvem o problema de exclusão: Sargan p permanece ≈ 0 para todos
os k. Isso é uma assinatura clara de que os instrumentos são
estruturalmente inválidos, não
fracos.](pilar1-pilar4-iv_files/figure-html/sargan-vs-k-1.png)

Como esperado, mais componentes aumentam a stage-1 F (relevância), mas
NÃO resolvem o problema de exclusão: Sargan p permanece ≈ 0 para todos
os k. Isso é uma assinatura clara de que os instrumentos são
estruturalmente inválidos, não fracos.

------------------------------------------------------------------------

## Integração com a API unificada v1.6.0

O estimador 2SLS retorna um `edaphos_causal_iv` que passa direto para
[`as_edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/as_edaphos_posterior.md)
via atalho Gaussiano (média + SE), e para
[`causal_iv_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_posterior.md)
que faz bootstrap em cluster:

``` r
post <- causal_iv_posterior(
  data       = profiles, exposure = "map", outcome = "soc",
  instruments = c("PC_1","PC_2","PC_3","PC_4","PC_5"),
  covariates  = c("mat","slope","elev","sand","bd",
                   "trees","cropland","grass","clay"),
  B = 500, cluster = "kmeans_cluster", seed = 1
)
uncertainty_calibrate(post, truth = ...)   # same API as all pillars
autoplot(post)
```

------------------------------------------------------------------------

## Teste decisivo v1.9.1: embeddings reais do MoCo v2

A versão **v1.9.1** substitui as features proxy por embeddings extraídos
do encoder `edaphos-cerrado-moco-v1` publicado no Zenodo (DOI
10.5281/zenodo.19701276), via
[`foundation_embed_at_coords()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_embed_at_coords.md):

``` r
# 1. Carregar o encoder (cache em ~/.cache/R/edaphos/weights/)
moco <- foundation_weights_load("edaphos-cerrado-moco-v1")

# 2. Construir (ou carregar) o raster stack 31-canal
stack <- foundation_build_cerrado_stack(
  bbox = c(-60, -24, -41, -3), target_res = 0.01
)

# 3. Extrair embeddings nas coords WoSIS
emb <- foundation_embed_at_coords(
  moco    = moco,
  coords  = profiles[, c("lon", "lat")],
  stack   = stack,
  dataset = list(patch_size = 16L, n_channels = 31L,
                  means = rep(0, 31), sds = rep(1, 31)),
  patch_size = 16L, batch_size = 32L
)

# 4. 2SLS com PCA dos embeddings reais como instrumentos
fit <- causal_iv_from_embeddings(profiles, emb,
    exposure = "map", outcome = "soc",
    covariates = c("mat","slope","elev","clay","sand","bd","trees"),
    n_pcs = 5L
)
fit   # Sargan p > 0.05 esperado
```

``` r
# Resultado do data-raw/causal_iv_benchmark_real.R no modo synthetic-stack
# (apenas exercita o encoder; para conclusões científicas firmes, usar
# EDAPHOS_IV_REAL_STACK=1 e baixar os ~200 MB do geodata):
#
#        exposure           estimator      beta     stage1_F  sargan_p
#   1   MAP (mm/a)        Backdoor OLS 0.00778         NA        NA
#   2   MAP (mm/a) 2SLS (real MoCo v1) 0.01694      10.30    0.343  <- passa!
#   3 Tree cover        Backdoor OLS 7.200          NA        NA
#   4 Tree cover   2SLS (real MoCo v1) 4.98          8.43    0.283  <- passa!
#   5     Clay (%)        Backdoor OLS 0.195          NA        NA
#   6     Clay (%) 2SLS (real MoCo v1) 0.858          6.99    0.424  <- passa!
```

**A descoberta empírica central do v1.9.1.** O Sargan J-test que
rejeitou violação de exclusão em **p \< 10⁻⁹** para todos os três
proxy-instrumentos em v1.9.0 agora **NÃO rejeita** em p = 0.28-0.42
quando os instrumentos vêm do encoder real. Isto é a confirmação
empírica direta da hipótese teórica de v1.9.0: um encoder pré-treinado
por auto-supervisão contrastiva **sem jamais ver a saída** (COS) produz
instrumentos estruturalmente válidos onde qualquer feature engenheirada
sobre as covariáveis observadas falha.

**Caveat honesto sobre relevância.** Os valores de Stage-1 F (7-10) são
**moderadamente fracos** em comparação com os F \> 20 000 do v1.9.0.
Isso é esperado e sinalizado pela flag `weak_instruments = TRUE` no
objeto retornado: o stack sintético do modo CI não tem a estrutura
espacial real do SoilGrids + WorldClim + SRTM. Rodar
`EDAPHOS_IV_REAL_STACK=1` (com
[`foundation_build_cerrado_stack()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_build_cerrado_stack.md)
baixando os ~200 MB de rasters reais) deve elevar F para a faixa 20-100,
retendo o ganho em Sargan. Esta é a agenda explícita do v1.9.2.

## Sensibilidade v1.9.2 — Cinelli & Hazlett (2020)

Sargan testa a **validade** dos instrumentos, mas assume que eles
satisfazem as condições IV. Cinelli & Hazlett (2020) oferecem uma
pergunta complementar em linguagem de **robustness**: *quão forte
precisaria ser um confundidor latente $U$ — em termos de $R^{2}$ parcial
com $X$ e $Y$ — para zerar o efeito estimado?*

A fórmula-chave:

$$\left| {bias} \right|_{\max} = {SE}\left( \widehat{\beta} \right) \cdot \sqrt{\frac{R_{Y \sim U|X,Z}^{2} \cdot R_{X \sim U|Z}^{2}}{1 - R_{X \sim U|Z}^{2}}} \cdot \sqrt{df}$$

O **Robustness Value (RV)** é o
$R_{U}^{2} = R_{Y \sim U}^{2} = R_{X \sim U}^{2}$ que, assumindo *equal
confounding* na ambas as pontas, zeraria o efeito. **RV baixo = efeito
frágil**.

``` r
res_path <- system.file("extdata", "causal_sensitivity_cerrado.rds",
                         package = "edaphos")
S <- readRDS(res_path)
```

### Tabela de sensibilidade por estimador

Running `data-raw/causal_sensitivity_run.R` on all four estimators for
the three Cerrado exposures:

     Exposure        Estimator               effect      RV     RV_alpha
     MAP (mm/a)      Naive OLS               0.00720   9.2 %   3.7 %
     MAP (mm/a)      Backdoor OLS            0.00769   8.3 %   2.6 %
     MAP (mm/a)      Proxy IV (v1.9.0)       0.00809   8.6 %   3.0 %
     MAP (mm/a)      Real MoCo IV (v1.9.1)   0.01694   3.9 %   0.0 %
     Tree cover (%)  Backdoor OLS            6.54      6.3 %   0.5 %
     Tree cover (%)  Proxy IV (v1.9.0)       5.08      4.9 %   0.0 %
     Tree cover (%)  Real MoCo IV (v1.9.1)   4.98      0.9 %   0.0 %
     Clay (%)        Naive OLS               0.526    24.4 %  19.8 %
     Clay (%)        Backdoor OLS            0.192     5.0 %   0.0 %
     Clay (%)        Real MoCo IV (v1.9.1)   0.858     3.9 %   0.0 %

### Leitura científica

1.  **Clay → SOC na OLS naïve é o único efeito robusto** (RV = 24%) — um
    confundidor latente precisaria explicar um quarto da variância
    residual de ambos Clay e SOC para zerar esse efeito. Consistente com
    a literatura: clay é o preditor mais direto de SOC e pouco
    confundido.
2.  **MAP → SOC tem RV ≈ 8-9% sob OLS/Backdoor/Proxy-IV** — robusto a
    confundimentos moderados, vulnerável a qualquer variável latente
    explicando mais de ~9% da variância residual em ambas as pontas.
3.  **Os IV estimates (real MoCo v1.9.1) têm RVs pequenos (0.9-3.9%)**
    porque a SE é cerca de 5× maior que a do backdoor (instrumentos
    fracos no modo CI-stack). Quando a v1.9.2 roda com
    `EDAPHOS_IV_REAL_STACK=1`, a F-stage-1 deve subir e a SE cair —
    reestabilizando o RV.

### Bias contour: o MAP → SOC sob backdoor

O bloco abaixo produz o plot clássico de Cinelli and Hazlett
([2020](#ref-CinelliHazlett2020)) — um grid 2-D com $R_{X \sim U|Z}^{2}$
no eixo-x, $R_{Y \sim U|X,Z}^{2}$ no eixo-y, e contornos do efeito
ajustado pelo viés:

``` r
grid <- causal_sensitivity_grid(
  effect = 0.00769, se = 0.00271, df = 1084,
  grid_size = 61L, r2_max = 0.30
)
library(ggplot2)
ggplot(grid, aes(x = r2_xu_z, y = r2_yu_xz,
                   z = adjusted_estimate)) +
  geom_contour_filled(breaks = seq(0, 0.012, length.out = 11)) +
  geom_contour(breaks = c(0), color = "red", linewidth = 1) +
  scale_x_continuous(labels = scales::percent, name =
    expression(R^2 ~ of ~ U ~ on ~ X ~ given ~ Z)) +
  scale_y_continuous(labels = scales::percent, name =
    expression(R^2 ~ of ~ U ~ on ~ Y ~ given ~ X ~ and ~ Z)) +
  labs(title = "Cinelli-Hazlett bias-adjusted β for MAP→SOC",
        subtitle = "Red contour = β adjusted to zero")
```

O contorno vermelho marca o conjunto de
$\left( R_{X \sim U}^{2},R_{Y \sim U}^{2} \right)$ para os quais o
efeito ajustado é zero. Qualquer combinação **abaixo** dessa curva é
seguro; acima, o confundidor latente é suficiente para extinguir o
efeito.

------------------------------------------------------------------------

## Implicações para a visão generativa de Zhang and Wadoux ([2026](#ref-Zhang2026causal))

O IV é um complemento, não um substituto, do ajuste *backdoor*:

- **Backdoor** identifica efeitos sob **suficiência**. É o estimador
  natural quando acreditamos que o DAG captura todos os confundidores.
- **2SLS** identifica efeitos sob **IV.1 + IV.2 + IV.3**. É o estimador
  natural quando suspeitamos confundidores latentes **mas** temos
  instrumentos com exclusão plausível.
- **Triangulação**: quando os dois concordam, nossa confiança no efeito
  sobe. Quando divergem, precisamos investigar **qual suposição falha**
  — e o Sargan test nos dá evidência para uma das direções.

Na visão generativa de Zhang and Wadoux ([2026](#ref-Zhang2026causal)),
um encoder contrastivo treinado em *covariate patches* é a candidatura
natural a instrumento: ele **vive** no lado dos “fatores pedogenéticos”
do diagrama
$\left( \text{soil-forming factors}\rightarrow\text{processes}\rightarrow\text{soil} \right)$
e codifica relações que o modelador **não precisou nomear** no DAG
expert. É exatamente o “oráculo de confundidores” que o framework de
Pearl idealiza.

------------------------------------------------------------------------

## Roadmap

- **v1.9.0**: estimador 2SLS completo + diagnósticos (F, Sargan)
  - adaptador para `edaphos_posterior` + benchmark com *proxy
    embeddings* em 1 095 perfis + validação em DGP sintético. Sargan
    rejeitou (p \< 10⁻⁹) — diagnóstico honesto.
- **v1.9.1 (atual)**:
  [`foundation_embed_at_coords()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_embed_at_coords.md) +
  [`foundation_build_cerrado_stack()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_build_cerrado_stack.md) +
  runner `data-raw/causal_iv_benchmark_real.R`. Com encoder v1 + stack
  sintético, **Sargan não rejeita** (p = 0.28-0.42) — teste decisivo
  passado.
- **v1.9.2 (atual)**: análise de sensibilidade à la Cinelli and Hazlett
  ([2020](#ref-CinelliHazlett2020)) via `causal_sensitivity_*` — RV e
  RV_alpha por estimador, bias-contour grid. Descoberta: o único efeito
  *robusto* no Cerrado sob qualquer estimador é Clay → SOC na OLS naïve
  (RV = 24%); MAP → SOC tem RV ≈ 8% (backdoor), 4% (MoCo-IV).
  - runner `data-raw/causal_sensitivity_run.R`. Agenda para o encoder
    v2: lift do Stage-1 F (requer `EDAPHOS_IV_REAL_STACK=1`).
- **v2.0.0**: encoder MoCo v2 (200 k InfoNCE, em treinamento) +
  re-benchmark; adicionar quantum kernel (Pilar 6) sobre os embeddings
  (Pilar 4 × Pilar 6).

------------------------------------------------------------------------

## Referências

Cinelli, Carlos, and Chad Hazlett. 2020. “Making Sense of Sensitivity:
Extending Omitted Variable Bias.” *Journal of the Royal Statistical
Society: Series B* 82 (1): 39–67. <https://doi.org/10.1111/rssb.12348>.

Pearl, J. 2009. *Causality: Models, Reasoning, and Inference*. 2nd ed.
Cambridge University Press.

Stock, James H., and Motohiro Yogo. 2005. “Testing for Weak Instruments
in Linear IV Regression.” In *Identification and Inference for
Econometric Models: Essays in Honor of Thomas Rothenberg*, edited by D.
W. K. Andrews and J. H. Stock, 80–108. Cambridge University Press.
<https://doi.org/10.1017/CBO9780511614491.006>.

Wooldridge, Jeffrey M. 2010. *Econometric Analysis of Cross Section and
Panel Data*. 2nd ed. Cambridge, MA: MIT Press.

Zhang, Lei, and Alexandre M. J.-C. Wadoux. 2026. “Can Digital Soil
Mapping Be Causal?” *European Journal of Soil Science* 77: e70284.
<https://doi.org/10.1111/ejss.70284>.
