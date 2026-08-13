# Quantum kernel over foundation-model embeddings

> **Hipótese.** Os embeddings do MoCo v2 (Pilar 4) são o melhor resumo
> da paisagem que o pacote produz — 64 dimensões onde ~40 000 parâmetros
> treinados por contraste capturaram estrutura que nenhuma feature
> engenheirada consegue. O ZZFeatureMap do Pilar 6 é o kernel mais
> expressivo classicamente simulável (8 qubits → dim 2⁸ = 256 de
> Hilbert). Se a fusão não superar nem ranger sobre covariáveis brutas,
> nem RBF sobre os próprios embeddings, nem Q-KRR sobre covariáveis
> brutas, então *o lift quântico sobre representação-foundation é
> cosmético* para esta tarefa — e isso também é um resultado científico.

------------------------------------------------------------------------

## Arquitetura da fusão

    raw covariates (31 layers)
            │
            ▼
       MoCo v2 encoder  ──────────►  64-dim embedding vector
            │                                │
            ▼                                │
       raster patch                          │
                                             ▼
                                       qf_embed_reduce()
                                       (PCA → top-n, pi-rescale)
                                             │
                                             ▼
                                       ZZFeatureMap
                                       (n qubits → dim 2^n Hilbert)
                                             │
                                             ▼
                                   Kernel Ridge Regression

- `qf_embed_reduce(embeddings, n_pcs = 8L)` faz PCA + re-escala para
  `[-pi, pi]` (domínio natural do ZZFeatureMap).
- `qf_kernel_compare(X_q, reps = 2L)` compara a matriz Gram quântica,
  RBF e linear sobre o mesmo `X_q` — Frobenius distance
  - effective rank.
- `qf_krr_fit(embeddings, y, n_pcs, reps, lambda)` compõe tudo numa
  única função.
- `qf_krr_benchmark(embeddings, covariates, y, ...)` roda as quatro
  regressões lado a lado.

------------------------------------------------------------------------

## Diagnóstico de kernel: quão diferente é o quantum do RBF?

Usando 300 perfis WoSIS e os embeddings reais do encoder v1:

``` r

bundle <- readRDS(system.file("extdata", "quantum_foundation_cerrado.rds",
                                package = "edaphos"))
bundle$kernel_comparison
```

A questão central aqui é *se os kernels são materialmente diferentes*.
Frobenius distance entre `K_quantum` e `K_rbf` próxima de zero sugere
que o lift quântico não adiciona nada; valores maiores sinalizam
estrutura capturada exclusivamente pelo quantum.

------------------------------------------------------------------------

## 5-fold spatial CV: o benchmark head-to-head

Produzido por `data-raw/quantum_foundation_benchmark.R`.

O bloco abaixo **lê o artefacto publicado** em vez de reproduzir uma
saída digitada à mão. Esta secção mostrava, até esta versão, um bloco
`#>` escrito manualmente dentro de um chunk `eval = FALSE`: era
indistinguível de saída real do knitr para quem lê, e continuou a
publicar números censurados durante meses depois de o código que os
produziu ter sido corrigido. Um chunk que não corre não pode
desactualizar-se com aviso — só em silêncio.

O `eval = TRUE` abaixo é deliberado e é a única excepção nesta vinheta,
cujo chunk de setup desliga a avaliação globalmente: ler o `.rds`
publicado não custa nada e não precisa de torch nem de rede, ao
contrário do resto do documento.

``` r

f <- system.file("extdata", "quantum_foundation_cerrado.rds",
                 package = "edaphos")
if (nzchar(f)) {
  s <- as.data.frame(readRDS(f)$cv_summary)
  print(s[order(-s$r2_pooled),
          c("method", "rmse_pooled", "mae_mean", "r2_pooled", "r2_mean")],
        row.names = FALSE, digits = 3)
}
#>                         method rmse_pooled mae_mean r2_pooled r2_mean
#>  Quantum KRR on raw covariates        15.5     9.21   -0.0748  -0.350
#>        ranger (raw covariates)        15.5     8.97   -0.0753  -0.795
#>  Quantum KRR on foundation PCs        15.6     9.33   -0.0887  -0.295
#>      RBF-KRR on foundation PCs        16.1     9.77   -0.1591  -0.449
```

### Leitura honesta

**Este benchmark é um controlo negativo.** O stack que o encoder vê é
ruído branco — [`stats::rnorm()`](https://rdrr.io/r/stats/Normal.html)
em cada célula de cada canal — portanto os “embeddings de fundação”
descrevem uma paisagem sem sinal, por construção. Três dos quatro
métodos prevêem a partir de variáveis que *não podem* conter informação
sobre o COS.

**Os quatro métodos são piores do que prever a média.** Todos os $`R^2`$
agrupados são negativos, incluindo o do `ranger` sobre covariáveis
reais. Os quatro ficam próximos uns dos outros e a diferença entre eles
não merece leitura.

**O que esta secção dizia antes, e porquê.** Dizia que apenas o `ranger`
atingia $`R^2 > 0`$ e que as três regressões por kernel “degeneram para
R² = 0 — o mínimo aplicável”, prevendo “essencialmente a média”. Nada
disso era medido. O $`R^2`$ não tem mínimo aplicável: é a eficiência de
Nash–Sutcliffe e vai a $`-\infty`$. A função calculava
`max(0, 1 - SS_res/SS_tot)`, de modo que todo o valor negativo — 17 dos
20 pares método×fold — era achatado para exactamente zero. Isso converte
*“pior do que a média”* em *“não explica variância nenhuma”*, que são
coisas diferentes, e a versão lisonjeira foi a publicada.

**Duas colunas de $`R^2`$, porque uma delas é instável.**
[`edaphos_r2()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_r2.md)
é Nash–Sutcliffe contra a média do *próprio* fold de teste; um fold
cujos perfis calham homogéneos tem denominador pequeno e $`R^2`$
volátil. O fold 2 desta partição tem sd(COS) = 5,9 g/kg contra 11–21 nos
outros quatro, e o `ranger` marca −4,28 lá — sozinho, esse fold arrasta
a média dele para −0,80 e fá-lo parecer o pior dos quatro. Agrupado
sobre os folds, o `ranger` é −0,075, no meio do lote. A coluna agrupada
é a que se lê.

**Por que o resultado é este?** A explicação está no desenho, não numa
hipótese por testar: o stack é ruído. Versões anteriores desta secção
listavam três “hipóteses falseáveis” — stack sintético, encoder
sub-treinado, poucos qubits — como se fossem razões para esperar outra
resposta mais tarde. Não são: cada uma é razão para a corrida ser *não
informativa*, e nenhuma é indício de que uma corrida corrigida
favoreceria o kernel quântico. Duas foram entretanto corridas e ambas
responderam contra ele; ver a tabela de seis métodos em
`inst/extdata/benchmark_wosis_6pilar.rds`, sobre covariáveis SoilGrids /
WorldClim / SRTM medidas.

### O que isso significa como contribuição científica

O valor do v2.0.0 não é bater os baselines (tentamos e não batemos). É:

1.  **Construir a infraestrutura** que compõe Pilar 4 com Pilar 6 de
    modo completo e reproduzível —
    [`qf_embed_reduce()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_embed_reduce.md),
    [`qf_kernel_compare()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_kernel_compare.md),
    [`qf_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_krr_fit.md),
    [`qf_krr_benchmark()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_krr_benchmark.md),
    todas exportadas e testadas.
2.  **Formalizar a hipótese** — a fusão quantum-foundation é um
    candidato natural no arcabouço generativo de Zhang and Wadoux
    ([2026](#ref-Zhang2026causal)) e de
    ([**SchuldKilloran2019?**](#ref-SchuldKilloran2019)), mas requer ou
    um encoder mais rico ou um stack mais real.
3.  **Deixar o teste decisivo pronto** — quando o encoder v2 e os dados
    reais de geodata estiverem disponíveis, basta re-rodar
    `data-raw/quantum_foundation_benchmark.R` para obter uma comparação
    equitativa.

------------------------------------------------------------------------

## Roadmap

- **v2.0.0 (atual)**: infraestrutura Pilar 4 × Pilar 6 completa; kernel
  comparison; 4-way CV benchmark empata em ~14 g/kg RMSE sobre 1 095
  perfis com stack sintético.
- **v2.0.1**: re-rodar com encoder v2 (200 k InfoNCE steps, em
  treinamento). Se Quantum-over-foundation superar *todos* os baselines,
  a hipótese do Havlíček et al. ([2019](#ref-Havlicek2019)) é confirmada
  no domínio de MDS.
- **v2.0.2**: re-rodar com raster stack real. Se o ganho aparece aqui
  mas não com o stack sintético, isso responde se a limitação está no
  encoder ou no stack. O caminho de stack real está por implementar: o
  `EDAPHOS_IV_REAL_STACK=1` que esta lista anunciava não é lido em lado
  nenhum do pacote.
- **v2.0.3**: submissão ao CRAN + paper “Quantum kernels over
  foundation-model embeddings for Digital Soil Mapping” (se resultados
  confirmarem ganho).

------------------------------------------------------------------------

## Referências

Havlíček, V., A. D. Córcoles, K. Temme, et al. 2019. “Supervised
Learning with Quantum-Enhanced Feature Spaces.” *Nature* 567: 209–12.
<https://doi.org/10.1038/s41586-019-0980-2>.

Zhang, Lei, and Alexandre M. J.-C. Wadoux. 2026. “Can Digital Soil
Mapping Be Causal?” *European Journal of Soil Science* 77: e70284.
<https://doi.org/10.1111/ejss.70284>.
