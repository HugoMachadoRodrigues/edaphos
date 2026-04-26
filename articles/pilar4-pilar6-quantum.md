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

Rodando `data-raw/quantum_foundation_benchmark.R`:

``` r
bundle$cv_summary
#>  method                          rmse_mean  rmse_sd  mae_mean  r2_mean  n_folds
#>  Quantum KRR on foundation PCs   14.3        5.9      8.7      0.00     5
#>  Quantum KRR on raw covariates   14.2        5.9      8.4      0.00     5
#>  RBF-KRR on foundation PCs       14.8        4.6      9.8      0.00     5
#>  ranger (raw covariates)         14.3        4.0      9.0      0.08     5
```

### Leitura honesta

**Os quatro métodos empatam em RMSE (~14 g/kg)**. Apenas o `ranger`
atinge $R^{2} > 0$ (consistente com o estudo `case-cerrado-end-to-end`
v1.3.1 onde o QRF lidera com RMSE $\approx 13,5$ g/kg sobre 1095 perfis
reais). As três regressões por kernel degeneram para R² = 0 — o mínimo
aplicável — sinalizando que **elas prevêem essencialmente a média**
sobre a partição espacial de teste.

**Por que isso?** Três hipóteses alternativas, cada uma falseável:

1.  **O stack sintético não carrega estrutura espacial real** — o
    encoder vê ruído gaussiano, produz embeddings sem sinal. Quando
    rodamos com `EDAPHOS_IV_REAL_STACK=1` (v1.9.3), isto se resolve.
2.  **O encoder v1 foi sub-treinado** (20 k InfoNCE steps, ~10% do
    orçamento MoCo v2 canônico). O v2 (200 k steps, em treinamento) deve
    produzir representações mais ricas — teste decisivo para o Pilar 4 ×
    Pilar 6.
3.  **6 qubits são pouco para capturar a não-linearidade do problema**.
    Aumentar para 8-10 qubits (ainda classicamente simulável) + mais
    `reps` na camada de entangling do ZZFeatureMap é uma direção natural
    — mas o custo computacional sobe como
    $O\left( N^{2} \cdot 4^{n} \right)$.

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
- **v2.0.2**: re-rodar com raster stack real
  (`EDAPHOS_IV_REAL_STACK=1`). Se o ganho aparece aqui mas não com o
  stack sintético, isso responde se a limitação está no encoder ou no
  stack.
- **v2.0.3**: submissão ao CRAN + paper “Quantum kernels over
  foundation-model embeddings for Digital Soil Mapping” (se resultados
  confirmarem ganho).

------------------------------------------------------------------------

## Referências

Havlíček, V., A. D. Córcoles, K. Temme, A. W. Harrow, A. Kandala, J. M.
Chow, and J. M. Gambetta. 2019. “Supervised Learning with
Quantum-Enhanced Feature Spaces.” *Nature* 567: 209–12.
<https://doi.org/10.1038/s41586-019-0980-2>.

Zhang, Lei, and Alexandre M. J.-C. Wadoux. 2026. “Can Digital Soil
Mapping Be Causal?” *European Journal of Soil Science* 77: e70284.
<https://doi.org/10.1111/ejss.70284>.
