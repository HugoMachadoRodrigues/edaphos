# edaphos: Digital Soil Mapping with Causal, Physics-Informed and Generative Methods

`edaphos` is a research-oriented R package that implements frontier
algorithms for Digital Soil Mapping (DSM) beyond the regression-tree
state of the art (McBratney, Mendonça Santos and Minasny, 2003; Wadoux,
Minasny and McBratney, 2020). Its contributions are organised across
**ten research pillars**, each confronting a specific methodological gap
of the contemporary literature and equipped with a vignette that derives
the governing object from first principles.

## Details

From Greek \\\epsilon\delta\alpha\phi o\varsigma\\ — "soil, ground."

## Ten research pillars

- **1. Causal AI.**:

  DAG-backed backdoor adjustment via `dagitty` —
  [`causal_clorpt_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_clorpt_dag.md),
  [`causal_cerrado_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_cerrado_dag.md),
  [`causal_adjustment_set()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_adjustment_set.md),
  [`causal_estimate_effect()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_estimate_effect.md)
  — with an optional non-linear BART estimator via the `dbarts` Suggests
  dependency. An LLM-driven Knowledge-Graph extraction pipeline on top
  of `httr2`
  ([`causal_kg_new()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_new.md),
  [`causal_llm_extract()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_extract.md),
  [`causal_llm_ingest_corpus()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_corpus.md),
  [`causal_augment_dag()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_augment_dag.md))
  supports Ollama (Gemma 4), OpenAI and Anthropic backends. Corpus
  ingestion clients for SciELO
  ([`causal_corpus_scielo()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_corpus_scielo.md))
  and OpenAlex
  ([`causal_corpus_openalex()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_corpus_openalex.md))
  transparently page through their upstream APIs for
  multi-thousand-abstract pulls, deduplicated by DOI / title via
  [`causal_corpus_deduplicate()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_corpus_deduplicate.md).
  Production-grade ingestion over corpora of tens of thousands of
  abstracts is handled by
  [`causal_llm_ingest_corpus()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_corpus.md)'s
  `cache_dir` and `max_retries` arguments (resumable, idempotent,
  exponential backoff). Ontology alignment against the curated Cerrado
  vocabulary or **live FAO AGROVOC SPARQL**
  ([`causal_ontology_agrovoc_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align.md),
  `causal_kg_alignment(vocab = "agrovoc")`) is provided with on-disk
  caching, and a **concurrent batched alignment**
  ([`causal_ontology_agrovoc_align_batch()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_ontology_agrovoc_align_batch.md))
  dispatches up to `max_active` parallel HTTP requests so a 10 k-node KG
  resolves in minutes instead of hours. Paper-scale KGs are persisted
  and audited via
  [`causal_kg_save()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_save.md)
  /
  [`causal_kg_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_load.md)
  (portable RDS edge-list),
  [`causal_kg_to_turtle()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_to_turtle.md)
  (W3C RDF 1.1 Turtle export with reified provenance per edge),
  [`causal_kg_rank_edges()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_kg_rank_edges.md)
  (multi-source ranking by `n_sources` + `mean_confidence` +
  `agrovoc_support`) and a
  [`summary()`](https://rdrr.io/r/base/summary.html) method that reports
  node / edge / source counts, confidence distribution and DAG-ness.
  **Multi-extractor voting**
  ([`causal_llm_vote()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_vote.md),
  [`causal_llm_ingest_abstract_voted()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_llm_ingest_abstract_voted.md))
  runs N LLM backends on the same abstract and resolves disagreements by
  majority, weighted or intersection rules. **Bottom-up structure
  learning**
  ([`causal_structure_learn()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_structure_learn.md))
  recovers a DAG directly from horizon data through a `bnlearn` bridge
  (hc, tabu, pc-stable, mmhc) with optional bootstrap edge confidence,
  producing an `edaphos_causal_kg` that can be unioned with the
  LLM-derived Knowledge Graph.

- **2. Physics-Informed ML.**:

  Parametric pedogenetic Ordinary Differential Equation, solved in
  closed form and fitted through a horizon-average observation operator
  —
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md);
  Neural ODE with differentiable Runge-Kutta integrator on `torch` —
  [`piml_neural_ode_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit.md);
  hierarchical covariate-conditioned Neural ODE jointly fit across
  pedons —
  [`piml_hierarchical_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_hierarchical_fit.md).
  A **Bayesian posterior** over \\(\lambda_0, \mu, y\_\infty, y_0)\\ is
  returned by
  [`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md)
  via a Laplace approximation (the default) or an adaptive random-walk
  Metropolis sampler. The Neural-ODE variant is paired with
  [`piml_neural_ode_fit_ensemble()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit_ensemble.md),
  a deep ensemble whose empirical spread approximates the Bayesian
  predictive posterior with no extra torch machinery.

- **3. 4D Pedometry.**:

  Multi-layer stacked Convolutional LSTM with sequence-to-one and
  sequence-to-sequence training —
  [`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md);
  multi-step rollout forecasting —
  [`temporal_convlstm_rollout()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_rollout.md);
  optional mass-balance physics loss; reproducible synthetic SOC
  dynamics cube generator —
  [`temporal_synth_soc_cube()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_synth_soc_cube.md).

- **4. Foundation Models.**:

  SimCLR scaffold
  ([`foundation_simclr_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_simclr_pretrain.md),
  [`foundation_simclr_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_simclr_embed.md))
  plus a **MoCo v2** upgrade
  ([`foundation_moco_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain.md),
  [`foundation_moco_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed.md))
  with momentum encoder, dictionary queue and a raster-specific
  augmentation stack. A **planetary-scale tile pipeline**
  ([`foundation_tile_source_soilgrids()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_soilgrids.md),
  [`foundation_tile_source_worldclim()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_worldclim.md),
  [`foundation_tile_source_srtm()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_srtm.md),
  [`foundation_tile_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_align.md),
  [`foundation_tile_dataset()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_dataset.md))
  streams patches lazily from multi-source
  [`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  mosaics;
  [`foundation_moco_pretrain_tiles()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain_tiles.md)
  trains with checkpointing and on-device dispatch
  (`device = "cpu" | "mps" | "cuda"`), and
  [`foundation_moco_embed_raster()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed_raster.md)
  projects the trained encoder over an entire AoI. A **downstream
  fine-tuning API**
  ([`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md),
  [`foundation_fit_regressor()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_regressor.md))
  wraps the head construction, training loop, validation split and
  target normalisation behind a single call and supports both linear
  probing and full fine-tuning with a two-group learning-rate schedule.
  **Public pretrained weights** are distributed via Zenodo:
  [`foundation_weights_list()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_list.md)
  catalogues the registry,
  [`foundation_weights_download()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_download.md)
  fetches the artefact with SHA-256 verification and caches it under
  `tools::R_user_dir("edaphos")`, and
  [`foundation_weights_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_load.md)
  rebuilds the `edaphos_foundation_moco` wrapper from the saved state
  dict.

- **5. Autonomous Active Learning.**:

  Closed-loop sampling policy combining Quantile-Regression-Forest
  uncertainty, feature-space diversity and logistical cost —
  [`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md),
  [`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md),
  [`al_initial_design()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_initial_design.md),
  [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md),
  [`al_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_update.md);
  with both global and per-location Physics- Informed rejection gates —
  [`al_physics_gate_piml()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml.md),
  [`al_physics_gate_piml_hierarchical()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml_hierarchical.md).
  Information-theoretic batch acquisition is provided by
  [`al_query_batchbald()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query_batchbald.md),
  which maximises the mutual information between the batch and the model
  parameters via a greedy log-det submodular objective (Kirsch, van
  Amersfoort and Gal 2019).

- **6. Quantum ML.**:

  Pure-R state-vector simulator of the ZZFeatureMap encoding (Havlicek
  et al., 2019) with a quantum-kernel Gram matrix
  [`quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_kernel.md)
  and a closed-form Kernel Ridge Regression wrapper
  [`quantum_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_krr_fit.md).
  A full Qiskit-backed Variational Quantum Eigensolver bridge
  ([`quantum_hamiltonian()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian.md),
  [`quantum_hamiltonian_h2()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_h2.md),
  [`quantum_hamiltonian_organo_mineral()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_organo_mineral.md),
  [`quantum_vqe_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_fit.md),
  [`quantum_vqe_exact()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_vqe_exact.md))
  runs on `qiskit-aer` out of the box with three interchangeable back
  ends: exact statevector, **shot-based Aer** with SPSA and optional
  noise models, and **full IBM Quantum Runtime dispatch**
  ([`quantum_ibmq_submit()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_submit.md),
  [`quantum_ibmq_available()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_available.md),
  [`quantum_ibmq_backends()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_backends.md),
  [`quantum_ibmq_least_busy()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_ibmq_least_busy.md))
  with M3 readout and ZNE gate-folding mitigation (Kim et al., 2023). A
  **qiskit-nature bridge**
  ([`quantum_hamiltonian_from_pyscf()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_from_pyscf.md),
  [`quantum_hamiltonian_organo_mineral_nature()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_hamiltonian_organo_mineral_nature.md),
  [`quantum_nature_total_energy()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_nature_total_energy.md))
  lifts a user-supplied XYZ geometry through a PySCF RHF reference,
  frozen-core reduction, ActiveSpace projection and a `ParityMapper`
  with Z2 tapering, producing a qubit Hamiltonian ready for VQE
  minimisation. Curated presets cover the three canonical organo-mineral
  motifs: the carboxylate (`"formic_acid"`), the ortho-diol
  (`"methanediol"`), and a monodentate Fe(III)– carboxylate coordination
  complex (`"ferric_formate"`).

- **7. Bayesian Hierarchical Spatial.**:

  Hierarchical spatial linear model \\y = X\beta + w + \varepsilon\\
  with a Gaussian-process random effect \\w \sim GP(0, \sigma^2
  \rho(\cdot; \phi))\\ —
  [`bhs_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/bhs_fit.md).
  The \\\beta\\ and variance updates are conjugate and therefore
  closed-form; the range \\\phi\\ is profiled over a user-supplied grid
  by maximum likelihood, which keeps the whole sampler free of
  Metropolis steps. The Cholesky-heavy inner loop runs through an
  RcppArmadillo backend.
  [`predict()`](https://rdrr.io/r/stats/predict.html) performs Bayesian
  kriging at unobserved sites, propagating every posterior draw into the
  predictive distribution rather than plugging in a point estimate.

- **8. Neural Operators.**:

  Learns the solution operator \\\mathcal{G}: u(z) \mapsto y(z)\\
  between depth-function spaces instead of a pointwise regression. A 1-D
  **Fourier Neural Operator**
  ([`no_fno_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/no_fno_fit.md))
  applies \\(\mathcal{K}v)(z) = \mathcal{F}^{-1}(R\_\theta \cdot
  \mathcal{F}v)(z)\\ with the spectrum truncated to `n_modes` (Li et
  al., 2021); a **DeepONet**
  ([`no_deeponet_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/no_deeponet_fit.md))
  factorises \\\mathcal{G}(u)(z) \approx \sum_k b_k(u) t_k(z)\\ into
  branch and trunk networks (Lu et al., 2021), the constructive form of
  the Chen and Chen (1995) universal operator approximation theorem.
  Both expose a pure-R backend and a `torch` backend with full autograd
  and `"cpu"` / `"mps"` / `"cuda"` dispatch.

- **9. Diffusion Models.**:

  Denoising Diffusion Probabilistic Model (Ho, Jain and Abbeel, 2020)
  over soil-map patches.
  [`dm_cosine_schedule()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_cosine_schedule.md)
  builds the forward process \\q(x_t \mid x_0) = N(\sqrt{\bar\alpha_t}
  x_0, (1 - \bar\alpha_t) I)\\ on the cosine schedule of Nichol and
  Dhariwal (2021);
  [`dm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_fit.md)
  trains a denoiser \\\epsilon\_\theta(x_t, t)\\ by score matching;
  [`dm_sample()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_sample.md)
  runs ancestral sampling from \\t = T\\ down to 0, optionally
  conditioned on covariates. The `backend = "r"` trainer updates the
  readout layer only over randomly initialised hidden features — an
  Extreme-Learning-Machine regime (Huang, Zhu and Siew, 2006) — whereas
  `backend = "torch"` trains the full network.

- **10. Graph Neural Networks.**:

  Graph Attention Network (Veličković et al., 2018) over a k-NN
  co-location graph of profiles —
  [`gnn_build_graph()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_build_graph.md),
  with `edges = "spatial"`, `"feature"` or `"hybrid"` and optional
  self-loops.
  [`gnn_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_fit.md)
  trains multi-head attention \\\alpha\_{ij} =
  \mathrm{softmax}\_j(\mathrm{LeakyReLU}( a^\top \[W h_i \Vert W
  h_j\]))\\ by analytic reverse-mode gradients through the grouped
  softmax — checked against central finite differences in the test suite
  — with residual connections, head averaging, a transductive
  `train_mask` so no test label leaks into training, and a closed-form
  ridge readout.
  [`gnn_fit_ensemble()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_fit_ensemble.md)
  averages independent seeds so that the published comparison against a
  quantile regression forest is ensemble-versus-ensemble.
  [`gnn_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_embed.md)
  returns the learned node embeddings and
  [`gnn_causal_discovery()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_causal_discovery.md)
  hands them to Pillar 1's structure learner.

## How exports are named

Every exported function carries a domain prefix. There are no pillar
numbers in the API: the pillars organise the documentation, the prefixes
organise the functions.

- `causal_`:

  Causal inference and the LLM knowledge graph (Pillar 1).

- `piml_`:

  Physics-informed depth-profile models (Pillar 2).

- `temporal_`:

  4D pedometry: ConvLSTM, EnKF (Pillar 3).

- `foundation_`:

  Self-supervised encoders and their embeddings (Pillar 4).

- `al_`:

  Active learning: designs, acquisition policies, loops (Pillar 5).

- `active_`:

  One function,
  [`active_learning_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/active_learning_posterior.md),
  which is a Pillar 5 posterior accessor. It predates the `al_` prefix
  and kept the longer name; there is no second `active_` family.

- `quantum_`:

  Quantum kernels and VQE (Pillar 6).

- `bhs_`:

  Bayesian hierarchical spatial models (Pillar 7).

- `no_`:

  Neural operators: FNO, DeepONet (Pillar 8).

- `dm_`:

  Diffusion models (Pillar 9).

- `gnn_`:

  Graph neural networks (Pillar 10).

- `qf_`:

  The Pillar 4 x Pillar 6 bridge: quantum kernels over foundation
  embeddings.

- `uncertainty_`:

  The shared calibration API across pillars.

- `benchmark_`:

  Thin wrappers used by the cross-pillar benchmark.

- `spatial_`:

  One function,
  [`spatial_block_folds()`](https://hugomachadorodrigues.github.io/edaphos/reference/spatial_block_folds.md):
  buffered spatially blocked cross-validation folds, used by every
  benchmark in the package.

- `llm_`:

  Large-language-model extraction and annotation tooling.

- `edaphos_`:

  Package-level utilities: metrics, provenance, release helpers.

## On "pilar" and "pillar"

Both spellings appear, and the split is deliberate rather than
accidental. English prose says **pillar**; identifiers say **pilar**,
which is the Portuguese word. So
[`vignette("pilar6-quantum")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar6-quantum.md)
documents Pillar 6, and `inst/extdata/pilar10_gat_tuning.rds` holds
Pillar 10's tuning run. `DESCRIPTION` declares `Language: en-US, pt-BR`
for the same reason: five of the vignettes are written in Portuguese.

No exported function carries either spelling, so the distinction never
reaches code a user writes. It survives in file names, which are a
contract – renaming a vignette breaks every
[`vignette()`](https://rdrr.io/r/utils/vignette.html) call and bookmark
pointing at it – and the package is not willing to break that for an
orthographic preference.

## Vignettes

Each pillar ships a mathematically-derived vignette with examples on
real or reproducible synthetic data. Entry points:
[`vignette("pilar1-causal", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar1-causal.md),
[`vignette("pilar2-piml-profile", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar2-piml-profile.md),
[`vignette("pilar3-4d-soc", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar3-4d-soc.md),
[`vignette("pilar4-simclr-embeddings", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar4-simclr-embeddings.md),
[`vignette("pilar5-active-learning", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar5-active-learning.md),
[`vignette("pilar6-quantum", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar6-quantum.md),
[`vignette("pilar7-bayesian-hierarchical", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar7-bayesian-hierarchical.md),
[`vignette("pilar8-neural-operators", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar8-neural-operators.md),
[`vignette("pilar9-diffusion-models", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar9-diffusion-models.md),
[`vignette("pilar10-graph-attention", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar10-graph-attention.md).
Cross-pillar bridges have their own:
[`vignette("pilar1-pilar4-iv", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar1-pilar4-iv.md),
[`vignette("pilar4-pilar6-quantum", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/pilar4-pilar6-quantum.md),
[`vignette("uncertainty-unified", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/uncertainty-unified.md),
[`vignette("causal-discovery-trio", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/causal-discovery-trio.md),
[`vignette("llm-annotation-workflow", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/llm-annotation-workflow.md).
The end-to-end honest benchmark on 1212 real Brazilian WoSIS Cerrado
profiles lives in
[`vignette("case-cerrado-end-to-end", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/case-cerrado-end-to-end.md),
and
[`vignette("capstone-cerrado-campaign", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/capstone-cerrado-campaign.md)
puts the pillars together on a sampling-campaign decision. Start at
[`vignette("getting-started", package = "edaphos")`](https://hugomachadorodrigues.github.io/edaphos/articles/getting-started.md).

## References

McBratney, A. B., Mendonça Santos, M. L. and Minasny, B. (2003). On
digital soil mapping. *Geoderma* **117**, 3-52.

Wadoux, A. M. J.-C., Minasny, B. and McBratney, A. B. (2020). Machine
learning for digital soil mapping: applications, challenges and
suggested solutions. *Earth-Science Reviews* **210**, 103359.

## See also

Useful links:

- <https://github.com/HugoMachadoRodrigues/edaphos>

- Report bugs at
  <https://github.com/HugoMachadoRodrigues/edaphos/issues>

## Author

**Maintainer**: Hugo Rodrigues <rodrigues.machado.hugo@gmail.com>
([ORCID](https://orcid.org/0000-0002-8070-8126)) \[copyright holder\]

Authors:

- Hugo Rodrigues <rodrigues.machado.hugo@gmail.com>
  ([ORCID](https://orcid.org/0000-0002-8070-8126)) \[copyright holder\]
