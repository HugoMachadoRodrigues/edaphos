# print.edaphos_causal_effect

    Code
      print(direct)
    Output
      <edaphos_causal_effect>
        ndvi -> soc   (estimator: lm)
        adjustment set : {map_mm, slope, twi}
        direct effect  : 18.43   (95% CI: 14.61, 22.25)
        naive effect   : 49.36   (un-adjusted, likely confounded)

---

    Code
      print(total)
    Output
      <edaphos_causal_effect>
        soilgrids_clay -> soc_topsoil_gkg   (estimator: lm)
        adjustment set : {slope}
        total effect   : -0.07328   (95% CI: -0.217, 0.07044)
        naive effect   : -0.07384   (un-adjusted, likely confounded)

# print.edaphos_causal_iv

    Code
      print(over)
    Output
      <edaphos_causal_iv>
        X -> Y  (estimator: 2SLS, n = 200)
        covariates  : W
        instruments : Z1, Z2, Z3
        effect      : 1.4573  (se = 0.0746, 95% CI [1.3111, 1.6035])
        stage-1 F   : 75.19 (p = 2.33e-32)  partial R^2 = 0.536
        Sargan J    : chi2(2) = 0.11, p = 0.945

---

    Code
      print(just)
    Output
      <edaphos_causal_iv>
        X -> Y  (estimator: 2SLS, n = 200)
        instruments : Z1
        effect      : 1.4419  (se = 0.1068, 95% CI [1.2325, 1.6512])
        stage-1 F   : 71.40 (p = 6.26e-15)  partial R^2 = 0.265

# print.edaphos_dag_test

    Code
      print(tst)
    Output
      <edaphos_dag_test>
        120 profiles, 11 of the graph's 11 nodes have data
        implied conditional independencies : 66
        rejected at 5% (pooled)         : 6 (9%)
        largest violated partial correlation: 0.941
      
        The graph is not compatible with the covariance structure of
        these data. Any adjustment set derived from it is minimal and
        sufficient only relative to a graph the data reject, so effects
        estimated with it should be reported as adjusted associations
        with sensitivity bounds, not as identified causal effects.

# print/summary.edaphos_causal_kg and print.edaphos_causal_kg_summary

    Code
      print(kg)
    Output
      <edaphos_causal_kg>
        nodes : 3
        edges : 3
        confidence: min = 0.50, median = 0.70, max = 0.90
        DAG        : yes

---

    Code
      summary(kg)
    Output
      <edaphos_causal_kg_summary>
        nodes      : 3
        edges      : 3
        sources    : 2 unique
        DAG        : yes
        confidence : min=0.50  q25=0.60  med=0.70  q75=0.80  max=0.90
        top source : A  (3 edges)

---

    Code
      print(empty)
    Output
      <edaphos_causal_kg>
        nodes : 0
        edges : 0

---

    Code
      summary(empty)
    Output
      <edaphos_causal_kg_summary>
        nodes      : 0
        edges      : 0
        sources    : 0 unique
        DAG        : yes

# print.edaphos_causal_4d

    Code
      print(res)
    Output
      <edaphos_causal_4d>  (Pillar 1 x Pillar 3 bridge)
        target effect : map -> soc
        adjustment    : z
        window / step : 10 / 5
        n windows     : 5
        beta_hat mean : 0.7929 (range [0.2362, 1.2951])
        Mann-Kendall  : S=10, tau=1, p=0.0275, trend=increasing

# print.edaphos_causal_al_query

    Code
      print(q)
    Output
      <edaphos_causal_al_query>  (Pillar 1 x Pillar 5 bridge)
        target effect : x -> y
        adjustment    : z
        strategy      : leverage
        n_select      : 3
        top-3 candidates:
        pool_index   leverage expected_var_reduction
      8          8 0.12741947             0.11301869
      5          5 0.11088379             0.09981583
      2          2 0.08684346             0.07990429

# print.edaphos_spatial_folds

    Code
      print(buffered)
    Output
      <edaphos_spatial_folds>
        81 rows, 5 blocks, buffer 10 km
        test rows per fold : 15, 15, 16, 21, 14
        training rows kept : 35, 47, 46, 39, 49
        discarded to buffer: 31, 19, 19, 21, 18 (26.7% of all rows)
        realised min train-test distance: 10.0 km

---

    Code
      print(unbuffered)
    Output
      <edaphos_spatial_folds>
        81 rows, 5 blocks, buffer 0 km
        test rows per fold : 15, 15, 16, 21, 14
        training rows kept : 66, 66, 65, 60, 67
        discarded to buffer: 0, 0, 0, 0, 0 (0.0% of all rows)
        realised min train-test distance: 3.8 km
        NOTE: buffer_km = 0 reproduces unbuffered blocking, which
              under-states generalisation error when the property is
              autocorrelated at the realised distance above.

# print/summary.edaphos_posterior

    Code
      print(post)
    Output
      <edaphos_posterior>
        method      : ensemble
        query_type  : map
        units       : g/kg
        n_samples   : 200
        query shape : 3
        mean range  : [-0.0418, +0.0406]  mean = +0.0115
        sd   range  : [+0.9291, +1.0700]  mean = +1.0033

---

    Code
      summary(post)
    Output
      <edaphos_posterior>
        method      : ensemble
        query_type  : map
        units       : g/kg
        n_samples   : 200
        query shape : 3
        mean range  : [-0.0418, +0.0406]  mean = +0.0115
        sd   range  : [+0.9291, +1.0700]  mean = +1.0033
      
      Quantiles (over query shape):
        q05   : min=-1.8715  med=-1.7696  max=-1.4716
        q50   : min=-0.0877  med=-0.0494  max=+0.0033
        q95   : min=+1.5960  med=+1.5996  max=+1.6438

---

    Code
      print(gauss)
    Output
      <edaphos_posterior>
        method      : gaussian
        query_type  : param
        n_samples   : 500
        query shape : 2
        mean range  : [+1.0000, +2.0000]  mean = +1.5000
        sd   range  : [+0.1000, +0.2000]  mean = +0.1500
        epistemic sd: [+0.0800, +0.1000]  mean = +0.0900
        aleatoric sd: [+0.0600, +0.1700]  mean = +0.1150

# print/summary.edaphos_al_model

    Code
      print(m)
    Output
      <edaphos_al_model>
        target : lead 
        covariates : dist, elev 
        coords : x, y 
        n labeled : 30 
        iterations : 1 
        last RMSE : <dbl> 

---

    Code
      summary(m)
    Output
       iter n_labeled rmse_oob mean_uncertainty
          0 25 <dbl> NA
          1 30 <dbl> <dbl>

# print.edaphos_temporal_kalman

    Code
      print(ku)
    Output
      <edaphos_temporal_kalman>
        n_ens  : 20
        n_obs  : 1
        innovation : mean=+2.8585  |max|=2.8585
        gain_row_norm : mean=2.2027  max=2.2027
        analysis_sd   : mean=0.9572  max=1.5119

# print.edaphos_temporal_al_query

    Code
      print(q)
    Output
      <edaphos_temporal_al_query>  (Pillar 3 x Pillar 5 bridge)
        grid dims : 4 x 4
        combine   : gain
        n_select  : 4
        top-4 cells (sorted by priority):
         row col      gain analysis_sd  priority
      7    3   2 0.9446753   0.6516738 0.9446753
      4    4   1 0.9082078   0.7774452 0.9082078
      6    2   2 0.8983897   0.2121425 0.8983897
      15   3   4 0.7698414   0.4820801 0.7698414

# print.edaphos_piml_profile

    Code
      print(fit)
    Output
      <edaphos_piml_profile>
        dy/dz = -lambda0 * exp(-mu*z) * (y - y_inf)
        lambda0 = 0.05 mu = 0.00604
        y0 = 30.4 y(Inf) = 5.96 (kappa = 8.28)
        y_inf = 5.96 (ODE coordinate, not the attained value)
        n obs = 5 (point) rmse = 0.0952
        converged = TRUE 

---

    Code
      print(bulge)
    Output
      <edaphos_piml_profile>
        dy/dz = -lambda0 * exp(-mu*z) * (y - y_inf)
        lambda0 = 0.00927 mu = 0.00103
        y0 = 15.6 y(Inf) = 1.23 (kappa = 9.04)
        y_inf = 1.23 (ODE coordinate, not the attained value)
        n obs = 5 (point) rmse = 1.88
        converged = TRUE 
        NOTE: the observations are not monotone in depth, and this model is monotone
              by construction (first-order relaxation, lambda > 0). It cannot represent
              an argillic bulge, an E horizon under an A, or a buried A. The fit is a
              least-squares compromise, not a description of the profile.

# print.edaphos_piml_mech

    Code
      print(fit)
    Output
      <edaphos_piml_mech>
        v dC/dz = I0 exp(-z/z_r) - k C (steady-state advection-reaction)
        dC/dz = -lambda (C - [A + B exp(-z/z_r)]), lambda = k/v, B = I0/k
        y0 = 31 A (deep floor) = 6.19 
        B = 14.2 z_r = 24.2 cm lambda = 0.135 /cm
        implied Jackson beta = 0.96
        n obs = 5 (point) rmse = 0.139 converged = TRUE

# print/summary.edaphos_piml_bayes

    Code
      print(lap)
    Output
      <edaphos_piml_bayes>
        method : laplace
        n draws : 2000
        sigma (noise): 0.00969
        posterior summary (natural scale):
       parameter mean sd q2.5 q50 q97.5
         lambda0 0.0374 0.0122 0.0189 0.0354 0.0668
              mu 0.0351 0.00551 0.0256 0.0347 0.0474
           y_inf -10.6 11.8 -41.3 -8.09 3.62
              y0 31 0.602 29.8 31 32.2
           kappa 1.15 0.571 0.399 1.02 2.59
          y_asym 6.06 0.178 5.71 6.06 6.42
           sigma 0.0103 0.00376 0.00474 0.00967 0.0192

---

    Code
      summary(lap)
    Output
        parameter mean sd q2.5 q50 q97.5
      1 lambda0 0.0374 0.0122 0.0189 0.0354 0.0667
      2 mu 0.0351 0.00551 0.0256 0.0347 0.0474
      3 y_inf -10.6 11.8 -41.3 -8.09 3.62
      4 y0 31 0.602 29.8 31 32.2
      5 kappa 1.15 0.571 0.399 1.02 2.59
      6 y_asym 6.06 0.178 5.71 6.06 6.42
      7 sigma 0.0103 0.00376 0.00474 0.00967 0.0192

---

    Code
      print(mc)
    Output
      <edaphos_piml_bayes>
        method : mcmc
        n draws : 800
        accept rate: 0.67 chains: 2
        max split-Rhat: 1.92 min bulk ESS: 46 <-- NOT CONVERGED
        the posterior summary below is not trustworthy:
          - max split-R-hat 1.92 > 1.01
          - min bulk ESS 46 < 400
        Increase n_iter, or use method = "laplace" and report it as
        an approximation.
        sigma (noise): 0.00969
        posterior summary (natural scale):
       parameter mean sd q2.5 q50 q97.5 rhat ess
         lambda0 0.0428 0.00432 0.0356 0.0422 0.0561 1.29 67.6
              mu 0.0319 0.00208 0.0286 0.032 0.0354 1.53 59.3
           y_inf -3.14 2.44 -8.88 -2.31 1.02 1.07 46.2
              y0 31.4 0.98 29.8 31.3 33.5 1.38 50.5
           kappa 1.35 0.182 1.01 1.38 1.83 1.29 67.6
          y_asym 6.07 0.123 5.84 6.08 6.31 1.07 46.2
           sigma 0.0327 0.00426 0.0249 0.0323 0.0409 1.92 58.6

# print.edaphos_quantum_krr

    Code
      print(fit)
    Output
      <edaphos_quantum_krr>
        n_qubits = 2   reps = 1   lambda = 0.2
        n_train  = 20   training RMSE = 0.5704

# print.edaphos_qf_krr

    Code
      print(fit)
    Output
      <edaphos_qf_krr>  (Pillar 4 x Pillar 6 bridge)
        n_pcs  = 3  (qubits = 3)
        reps   = 1
        lambda = 0.100
        n_train = 30

# print.edaphos_piml_qkrr

    Code
      print(fit)
    Output
      <edaphos_piml_qkrr>  (Pillar 2 x Pillar 6 bridge)
        n_qubits = 2   reps = 1   lambda = 0.1
        alpha    = 0.50  (quantum weight; 1-alpha on physics)
        sigma    = 1.22  (residual RBF bandwidth)
        n_train  = 12   training RMSE = 2.025

# print.edaphos_gnn_graph

    Code
      print(s$g)
    Output
      <edaphos_gnn_graph>  (Pillar 10 -- co-location graph)
        n_nodes : 24   k-NN : 4   n_edges : 120
        features (2) : x1, x2

# print.edaphos_gnn_gat, edaphos_gnn_ensemble, edaphos_qf_krr_gat

    Code
      print(fit)
    Output
      <edaphos_gnn_gat> (Pillar 10 -- Graph Attention Network)
        n_nodes : 24 k-NN : 4
        layers : 1 heads : 1 hidden/head : 4
        emb_dim : 6
        initial MSE = 0.0182 final MSE = 0.018 (epochs = 10)

---

    Code
      print(ens)
    Output
      <edaphos_gnn_ensemble>
        members = 2 nodes = 24 trained on = 24
        mean between-member sd = 0.0415

---

    Code
      print(qk)
    Output
      <edaphos_qf_krr_gat>  (Pillar 6 x Pillar 10)
        GAT emb_dim   : 4
        qubits (PCs)  : 3
        reps          : 1   lambda = 0.5
        n_train       : 24

# print.edaphos_no_deeponet and edaphos_al_neural_operator_query

    Code
      print(fit)
    Output
      <edaphos_no_deeponet> (Pillar 8 -- Deep Operator Network)
        branch 2x4 -> trunk 1x4, output_dim = 2
        n_train = 8 n_depths = 6
        initial MSE = 0.889 final MSE = 0.83 (epochs = 10)

---

    Code
      print(q)
    Output
      <edaphos_al_neural_operator_query> (Pillar 8 x Pillar 5)
        pool size : 8
        n_select : 2
        top candidates (NO vs ODE disagreement, normalised):
        pool_index score no_ode_disagreement no_uncertainty_sd
      5 5 2920 5.94 0.00203
      2 2 2540 5.98 0.00235

# print.edaphos_no_fno

    Code
      print(fit)
    Output
      <edaphos_no_fno> (Pillar 8 -- Fourier Neural Operator)
        n_depths = 6 n_modes = 2 width = 4 blocks = 1
        n_train = 8 C_in = 1
        initial MSE = 0.878 final MSE = 0.878

# print.edaphos_dm_fit and edaphos_al_diffusion_query

    Code
      print(fit)
    Output
      <edaphos_dm_fit> (Pillar 9 -- Denoising Diffusion Probabilistic Model)
        patch shape : 6 x 6
        n_train : 4 cond_dim = 0
        T (steps) : 4 hidden = 4
        initial loss = 6.66 final loss = 1.24

---

    Code
      print(q)
    Output
      <edaphos_al_diffusion_query> (Pillar 9 x Pillar 5)
        pool size : 36
        combine : sd
        top-3 cells:
        row col posterior_mean posterior_sd score
      6 6 1 0.913 3.84 3.84
      5 5 1 -0.77 3.8 3.8
      1 1 1 -0.803 3.78 3.78

# print.edaphos_bhs and edaphos_al_bhs_query

    Code
      print(fit)
    Output
      <edaphos_bhs> (Pillar 7 -- Bayesian Hierarchical Spatial)
        backend : gibbs
        n_obs : 30
        p (covariates + intercept) : 2
        MCMC draws kept : 50
        phi (profile-MLE) : 10
        beta posterior means:
          (Intercept) 0.0908 (sd 0.138)
          x 1.99 (sd 0.124)
        sigma^2 posterior mean : 0.208
        tau^2 posterior mean : 0.2
        spatial share sigma^2/(sigma^2 + tau^2) : 0.51
        practical range 3/phi : 0.3 (nearest-neighbour spacing 0.0326, same units as coords)
        <-- phi railed at the upper end of its bracket; the bracket, not
            the data, set the correlation rate

---

    Code
      print(q)
    Output
      <edaphos_al_bhs_query> (Pillar 7 x Pillar 5)
        pool size : 5
        n_draws : 20 n_select: 3
        top candidates by avg posterior variance:
        pool_index posterior_var posterior_sd
      5 5 0.41 0.641
      1 1 0.409 0.64
      3 3 0.408 0.639

# print.edaphos_tile_dataset

    Code
      print(td)
    Output
      <edaphos_tile_dataset>
        stack       : 20 x 20 x 2 (rows x cols x channels)
        patch_size  : 4 x 4
        n_patches   : 10
        channels    : a, b

# print.edaphos_foundation_classifier (fields: foundation_fit_classifier)

    Code
      print(x)
    Output
      <edaphos_foundation_classifier>
        n classes     : 3  (Ferralsol, Acrisol, Arenosol)
        feature_dim   : 64   head: mlp
        regime        : linear probe (backbone frozen)
        device        : cpu
        final loss    : 0.61
        best val_acc  : 0.720

---

    Code
      print(x)
    Output
      <edaphos_foundation_classifier>
        n classes     : 3  (Ferralsol, Acrisol, Arenosol)
        feature_dim   : 64   head: mlp
        regime        : full fine-tuning
        device        : cpu
        final loss    : 0.61

# print.edaphos_foundation_regressor (fields: foundation_fit_regressor)

    Code
      print(x)
    Output
      <edaphos_foundation_regressor>
        feature_dim   : 64   head: linear   loss: huber
        regime        : full fine-tuning
        device        : mps
        y_mean / y_sd : 21.5  /  7.25
        final loss    : 0.35
        best val_rmse : 0.55

# print.edaphos_foundation_ensemble (fields: foundation_finetune_ensemble)

    Code
      print(x)
    Output
      <edaphos_foundation_ensemble>
        task    : regression
        K_ens   : 3
        final losses : min=0.27  median=0.31  max=0.4

# print.edaphos_foundation_moco (fields: foundation_moco_pretrain)

    Code
      print(x)
    Output
      <edaphos_foundation_moco>  (MoCo v2 -- Pillar 4)
        in_channels = 6  feature_dim = 128  proj_dim = 64
        queue_size = 4096  momentum = 0.9990  tau = 0.2  batch = 64
        epochs = 3  final InfoNCE loss = 6.9

# print.edaphos_foundation_simclr (fields: foundation_simclr_pretrain)

    Code
      print(x)
    Output
      <edaphos_foundation_simclr> (experimental; Pillar 4 scaffold)
        in_channels = 6  feature_dim = 128  proj_dim = 64
        batch = 32  temperature = 0.5
        epochs = 2  final loss = 3.9

# print.edaphos_piml_hierarchical (fields: piml_hierarchical_fit)

    Code
      print(x)
    Output
      <edaphos_piml_hierarchical>
        n pedons   : 40 
        covariates : clay, map_mm 
        final loss : 0.21  (epochs = 3)

# print.edaphos_piml_neural_ode (fields: piml_neural_ode_fit)

    Code
      print(x)
    Output
      <edaphos_piml_neural_ode>
        dy/dz = f_theta(z, y), MLP hidden = 16 -> 16 
        n obs = 5  rmse = 0.42  final loss = 0.012

# print.edaphos_piml_neural_ode_ensemble (fields: piml_neural_ode_fit_ensemble)

    Code
      print(x)
    Output
      <edaphos_piml_neural_ode_ensemble>
        K members   : 5 (hidden = 16-16)
        n obs       : 5   ensemble rmse = 0.38
        fitted_sd   : min = 0.1   median = 0.4   max = 1.6

# print.edaphos_temporal_convlstm (fields: temporal_convlstm_fit)

    Code
      print(x)
    Output
      <edaphos_temporal_convlstm>
        input_dim = 3   hidden = [8, 4]   kernel = 3
        return_sequence = FALSE   epochs = 3   final loss = 0.11

# print.edaphos_temporal_convlstm_ensemble (fields: temporal_convlstm_ensemble_fit)

    Code
      print(x)
    Output
      <edaphos_temporal_convlstm_ensemble>
        K_ens         : 4
        hidden_dims   : 8-4
        final_losses  : min=0.1000  median=0.1150  max=0.1500

# print.edaphos_quantum_hamiltonian (fields: quantum_hamiltonian)

    Code
      print(.mock_hamiltonian())
    Output
      <edaphos_quantum_hamiltonian>
        n_qubits = 4   n_terms = 9
        Pauli terms (top 8 by |coef|):
          IIII              -0.810000
          IZII              -0.220000
          IIIZ              -0.220000
          ZIII               0.170000
          IIZI               0.170000
          ZIZI               0.165000
          ZZII               0.120000
          XXYY               0.045000
          ... 1 more term(s)

# print.edaphos_quantum_hamiltonian_nature (attrs: quantum_hamiltonian_from_pyscf)

    Code
      print(h)
    Output
      <edaphos_quantum_hamiltonian_nature>
        variant     : (user geometry)
        basis       : sto3g     mapper : parity
        active sp.  : (a=1, b=1) particles / 2 spatial orbitals
        qubits      : 4   n_terms : 9
        nuc_rep     : 0.719969   frozen : 0.000000
        active_shft : -0.500000   ref_E  : -1.116759

---

    Code
      print(h)
    Output
      <edaphos_quantum_hamiltonian_nature>
        variant     : methanediol
        basis       : sto3g     mapper : parity
        active sp.  : ? particles / 2 spatial orbitals
        qubits      : 4   n_terms : 9
        nuc_rep     : 0.719969   frozen : 0.000000
        active_shft : -0.500000   ref_E  : -1.116759

# print.edaphos_quantum_vqe (fields: quantum_vqe_fit)

    Code
      print(x)
    Output
      <edaphos_quantum_vqe>
        Hamiltonian : 4 qubits / 9 Pauli terms
        ansatz      : EfficientSU2(reps = 2)
        optimizer   : COBYLA    backend : aer_statevector
        shots       : -    mitigation : none
        n params    : 16   n iter : 214
        energy      : -1.137270
        exact       : -1.137306
        gap         : 3.600e-05

---

    Code
      print(x)
    Output
      <edaphos_quantum_vqe>
        Hamiltonian : 4 qubits / 9 Pauli terms
        ansatz      : EfficientSU2(reps = 2)
        optimizer   : COBYLA    backend : ibmq
        shots       : 4000    mitigation : twirling
        ibmq backend: ibm_brisbane
        n params    : 16   n iter : -
        energy      : -1.137270
        exact       : -1.137306
        gap         : 3.600e-05

# print.edaphos_quantum_ibmq_job (fields: quantum_ibmq_submit)

    Code
      print(x)
    Output
      <edaphos_quantum_ibmq_job>
        backend     : ibm_brisbane
        job_id      : job-0001
        expectation : -1.120300  (std = 4.200e-03)
        shots       : 4000   mitigation : none

