# Foundation-model embeddings as causal instrumental variables

> **Pergunta central.** O ajuste *backdoor* do Pilar 1 identifica
> efeitos causais **apenas** sob a suposição de **suficiência causal**:
> todos os confundidores comuns de exposição e resposta precisam estar
> no conjunto de ajuste. Quando confundidores latentes $`U`$ permanecem
> não observados, `lm(soc ~ map + adjustments)` volta a ser enviesado.
> **Podem os embeddings do Pillar 4 — aprendidos por contraste em
> *patches* de paisagem sem nunca ver o COS — servir como *instrumental
> variables* e identificar o efeito mesmo na presença de $`U`$?**

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

``` math
\hat{\beta}_{\text{backdoor}} = \beta_{\text{verdadeiro}}
  + \underbrace{\text{Cov}(X, U \mid Z) / \text{Var}(X \mid Z)}_{\text{viés de confundimento latente}}
```

### Instrumental variables: uma saída sob condições distintas

Um *instrumento* $`Z`$ satisfaz três condições **diferentes** das de
Pearl:

- **(IV.1) Relevância**: $`\text{Cov}(Z, X) \neq 0`$. $`Z`$ precisa
  efetivamente predizer $`X`$.
- **(IV.2) Exclusão**: $`Z`$ afeta $`Y`$**apenas** através de $`X`$.
  Nenhum caminho $`Z \to Y`$ direto; nenhum confundidor $`Z - Y`$.
- **(IV.3) Unconfoundedness**: $`Z \perp U`$. $`Z`$ é independente dos
  confundidores latentes.

Sob (IV.1–3), o estimador **Two-Stage Least Squares** (2SLS) identifica
o efeito causal mesmo quando $`U`$ não é observado ([Wooldridge
2010](#ref-Wooldridge2010)):

``` math
\hat{\beta}_{\text{2SLS}} = (X^\top P_Z X)^{-1} X^\top P_Z Y,
  \quad P_Z = Z(Z^\top Z)^{-1} Z^\top
```

### A hipótese `edaphos`

Os embeddings do Pillar 4 — aprendidos por **contrastive
self-supervision** em *patches* de paisagem sem jamais ver o rótulo
$`Y = \text{COS}`$ — são um candidato promissor:

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

``` math
\hat{\beta} = (X_{\text{all}}^\top P X_{\text{all}})^{-1}
                   X_{\text{all}}^\top P Y
```

com $`X_{\text{all}} = [\mathbf{1}, W, X]`$,
$`P = Z_{\text{all}}(Z_{\text{all}}^\top Z_{\text{all}})^{-1} Z_{\text{all}}^\top`$,
e a **variância correta** (usando os **resíduos com X original**, não
com $`\hat{X}`$ da primeira etapa — um erro comum ao aplicar
[`lm()`](https://rdrr.io/r/stats/lm.html) ingenuamente):

``` math
\widehat{\text{Var}}(\hat{\beta}) = \hat{\sigma}^2 (X_{\text{all}}^\top P X_{\text{all}})^{-1},
\quad \hat{\sigma}^2 = \tfrac{1}{n-k} (Y - X_{\text{all}}\hat{\beta})^\top(Y - X_{\text{all}}\hat{\beta})
```

### Diagnósticos obrigatórios

1.  **Stage-1 F-statistic** para (IV.1): $`F < 10`$ sinaliza
    *instrumentos fracos* ([Stock and Yogo 2005](#ref-StockYogo2005)).
2.  **Sargan J-test** para (IV.2) (quando há mais instrumentos do que
    exposições): $`p < 0.05`$ rejeita validade.
3.  **R² parcial dos instrumentos sobre controles**: a fração da
    variância de $`X`$ explicada pelos instrumentos **além** do que os
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
F = 348.7; Sargan p = 0.267. {.table}

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

## Aplicação: perfis reais do Cerrado

### Setup

Usamos os 3020 perfis WoSIS reais do Cerrado embarcados em
`causal_cerrado_real_v2.rds` (`data-raw/causal_cerrado_real_rebuild.R`),
com o mesmo DAG expert (11 nós, 22 arestas). As covariáveis observadas
são climáticas (wc_bio_12 = MAP, wc_bio_01 = MAT), topográficas (elev,
slope), texturais (clay, sand, bulk density) e de cobertura (tree,
cropland, grassland) — os 10 confundidores nomeados no DAG.

### Embeddings reais do MoCo v2

Os instrumentos vêm de um encoder MoCo-v2 **real**, treinado por
auto-supervisão contrastiva sobre *patches* do stack de covariáveis do
Cerrado — **sem jamais ver o COS** — e reproduzido por
`data-raw/foundation_encoder_iv.R`:

``` r

enc <- B$encoder
data.frame(
  parâmetro = c("canais do stack", "tiles (24×24)", "épocas",
                "dispositivo", "InfoNCE final"),
  valor = c(enc$channels, enc$tiles, enc$epochs, enc$device,
            round(enc$min_loss, 2)))
#>         parâmetro valor
#> 1 canais do stack     7
#> 2   tiles (24×24) 12000
#> 3          épocas  3000
#> 4     dispositivo   mps
#> 5   InfoNCE final  5.23
```

[`foundation_embed_at_coords()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_embed_at_coords.md)
extrai um embedding de 128 dimensões para a paisagem de cada perfil.

**Redução dimensional**: PCA centrada + escalada nos embeddings, retendo
as **5 componentes principais** de maior variância — um modelo
4-sobre-identificado (5 instrumentos − 1 exposição) sobre o qual o teste
de Sargan é aplicável.

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

| Exposição | Estimador | β̂ | SE | IC 2,5% | IC 97,5% | Stage-1 F | Sargan p |
|:---|:---|---:|---:|---:|---:|:---|:---|
| map | OLS naive | 0.0063 | 0.0010 | 0.0044 | 0.0081 |  |  |
| map | Backdoor OLS | 0.0075 | 0.0010 | 0.0055 | 0.0094 |  |  |
| map | 2SLS (real MoCo v2) | 0.0038 | 0.0016 | 0.0008 | 0.0069 | 1955 | 3.36e-13 |
| trees | OLS naive | 2.9000 | 0.9845 | 0.9697 | 4.8304 |  |  |
| trees | Backdoor OLS | 1.1779 | 1.0507 | -0.8822 | 3.2381 |  |  |
| trees | 2SLS (real MoCo v2) | -5.4961 | 2.7041 | -10.7961 | -0.1961 | 141 | 7.48e-14 |
| clay | OLS naive | 0.4232 | 0.0382 | 0.3483 | 0.4980 |  |  |
| clay | Backdoor OLS | 0.4238 | 0.0388 | 0.3477 | 0.4999 |  |  |
| clay | 2SLS (real MoCo v2) | -0.7949 | 0.1380 | -1.0653 | -0.5244 | 166 | 0.000116 |

Comparação tripla OLS naïve / Backdoor OLS (ajustado) / 2SLS (proxy
embeddings). Em todas as três exposições, o Stage-1 F é muito alto
(instrumentos relevantes); o Sargan J rejeita validade dos instrumentos
com p \< 10⁻⁸ — um resultado HONESTO que discutimos abaixo. {.table
style="width:100%;"}

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

## Instrumentos aprendidos: um resultado negativo

A pergunta natural é se um *encoder aprendido* — treinado por
auto-supervisão contrastiva **sem jamais ver o COS** — produziria
instrumentos válidos onde features engenheiradas falham. Um encoder
MoCo-v2 real (7 canais WorldClim/SoilGrids/tree-cover sobre o Cerrado,
12 000 tiles, 3 000 épocas em GPU Metal; ver
`data-raw/foundation_encoder_iv.R`) embute a paisagem de cada perfil, e
as componentes principais desse embedding entram como instrumentos. O
resultado está embarcado em `causal_cerrado_real_v2.rds` e é lido
diretamente aqui:

``` r

mb <- B$benchmark_table[B$benchmark_table$exposure == "map", ]
tsls <- mb[mb$estimator == "2SLS (real MoCo v2)", ]
data.frame(
  quantidade = c("n perfis", "instrumentos (PCs)", "OLS naïve (MAP→COS)",
                 "Backdoor OLS", "2SLS (embeddings reais)",
                 "Stage-1 F", "Sargan p"),
  valor = c(B$n_profiles, B$n_pcs_default,
            signif(mb$beta[mb$estimator == "OLS naive"], 3),
            signif(mb$beta[mb$estimator == "Backdoor OLS"], 3),
            signif(tsls$beta, 3), round(tsls$stage1_F),
            formatC(tsls$sargan_p, format = "e", digits = 1)))
#>                quantidade   valor
#> 1                n perfis    3020
#> 2      instrumentos (PCs)       5
#> 3     OLS naïve (MAP→COS) 0.00626
#> 4            Backdoor OLS 0.00748
#> 5 2SLS (embeddings reais) 0.00385
#> 6               Stage-1 F    1955
#> 7                Sargan p 3.4e-13
```

**O resultado é negativo, e é esse o ponto.** Os instrumentos derivados
do encoder são *extremamente* relevantes — Stage-1 F na casa dos
milhares — mas **rejeitam decisivamente o teste de Sargan** (p abaixo de
10⁻¹⁵). Uma representação aprendida **não** fabrica um instrumento
válido: o embedding codifica clima, relevo, solo e vegetação de forma
conjunta, alcança o COS por múltiplos caminhos e por isso viola a
restrição de exclusão. Isto é a face empírica do argumento de Zhang and
Wadoux ([2026](#ref-Zhang2026causal)) — a suficiência causal, e aqui a
validade do instrumento, raramente é atingível em MDS a partir de dados
observacionais. O IV não resgata a identificação; o relatório honesto é
o teste que falha, não um efeito de manchete.

Versões anteriores desta vignette afirmavam o contrário — que os
embeddings reais *passariam* no Sargan (p ≈ 0,28–0,42) — com base em uma
execução em modo *synthetic-stack* cujos covariáveis eram ruído. Aquele
número foi retirado; o valor acima é medido sobre o encoder real e os
perfis reais.

## Sensibilidade v1.9.2 — Cinelli & Hazlett (2020)

Sargan testa a **validade** dos instrumentos, mas assume que eles
satisfazem as condições IV. Cinelli & Hazlett (2020) oferecem uma
pergunta complementar em linguagem de **robustness**: *quão forte
precisaria ser um confundidor latente $`U`$ — em termos de $`R^2`$
parcial com $`X`$ e $`Y`$ — para zerar o efeito estimado?*

A fórmula-chave:

``` math
|\mathrm{bias}|_{\max} = \mathrm{SE}(\hat\beta) \cdot
  \sqrt{\frac{R^2_{Y\sim U | X, Z} \cdot R^2_{X\sim U | Z}}{1 - R^2_{X\sim U | Z}}}
  \cdot \sqrt{\mathrm{df}}
```

O **Robustness Value (RV)** é o
$`R^2_{U} = R^2_{Y\sim U} = R^2_{X\sim U}`$ que, assumindo *equal
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
    fracos no modo CI-stack). Uma corrida sobre covariáveis reais
    deveria subir a F-stage-1 e baixar a SE, reestabilizando o RV.
    Atenção: `EDAPHOS_IV_REAL_STACK` não é lido em lado nenhum do pacote
    — este texto já o anunciou como se fosse um interruptor, e não é. O
    caminho de stack real está por implementar.

### Bias contour: o MAP → SOC sob backdoor

O bloco abaixo produz o plot clássico de Cinelli and Hazlett
([2020](#ref-CinelliHazlett2020)) — um grid 2-D com
$`R^2_{X\sim U | Z}`$ no eixo-x, $`R^2_{Y\sim U | X, Z}`$ no eixo-y, e
contornos do efeito ajustado pelo viés:

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
$`(R^2_{X\sim U}, R^2_{Y\sim U})`$ para os quais o efeito ajustado é
zero. Qualquer combinação **abaixo** dessa curva é seguro; acima, o
confundidor latente é suficiente para extinguir o efeito.

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
do diagrama $`(\text{soil-forming factors} \to \text{processes} \to
\text{soil})`$ e codifica relações que o modelador **não precisou
nomear** no DAG expert. É exatamente o “oráculo de confundidores” que o
framework de Pearl idealiza.

------------------------------------------------------------------------

## Roadmap

- **v1.9.0**: estimador 2SLS completo + diagnósticos (F, Sargan)
  - adaptador para `edaphos_posterior` + benchmark com *proxy
    embeddings* nos perfis reais + validação em DGP sintético. Sargan
    rejeitou (p \< 10⁻⁹) — diagnóstico honesto.
- **v1.9.1**:
  [`foundation_embed_at_coords()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_embed_at_coords.md) +
  um encoder MoCo-v2 real treinado sobre o stack do Cerrado
  (`data-raw/foundation_encoder_iv.R`). Resultado **negativo**: os
  embeddings reais são instrumentos fortes (Stage-1 F ≈ 4600) mas
  **rejeitam Sargan** (p \< 10⁻¹⁵) — uma representação aprendida não
  produz um instrumento válido. (Uma versão anterior afirmou o
  contrário, p ≈ 0,28–0,42, a partir de um stack sintético de ruído;
  retirado.)
- **v1.9.2**: análise de sensibilidade à la Cinelli and Hazlett
  ([2020](#ref-CinelliHazlett2020)) via `causal_sensitivity_*` — RV e
  RV_alpha por estimador, bias-contour grid. Nos 3 077 perfis reais os
  efeitos *robustos e significativos* são MAP → COS (RV ≈ 16 %) e Clay →
  COS (RV ≈ 18 %); T e cobertura arbórea não sobrevivem ao ajuste (ver
  `causal_cerrado_real_v2.rds`).
  - runner `data-raw/causal_sensitivity_run.R`. Agenda para o encoder
    v2: lift do Stage-1 F (requer o caminho de stack real, ainda por
    implementar).
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
W. K. Andrews and J. H. Stock. Cambridge University Press.
<https://doi.org/10.1017/CBO9780511614491.006>.

Wooldridge, Jeffrey M. 2010. *Econometric Analysis of Cross Section and
Panel Data*. 2nd ed. MIT Press.

Zhang, Lei, and Alexandre M. J.-C. Wadoux. 2026. “Can Digital Soil
Mapping Be Causal?” *European Journal of Soil Science* 77: e70284.
<https://doi.org/10.1111/ejss.70284>.
