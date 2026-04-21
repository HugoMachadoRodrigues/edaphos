===== pillar1_adjset =====
map_mm, slope, twi

===== pillar1_fit =====
<edaphos_causal_effect>
  ndvi -> soc
  adjustment set : {map_mm, slope, twi}
  direct effect  : 18.43   (95% CI: 14.61, 22.25)
  naive effect   : 49.36   (un-adjusted, likely confounded)

===== pillar2_param =====
<edaphos_piml_profile>
  dy/dz = -lambda0 * exp(-mu*z) * (y - y_inf)
  lambda0 = 0.005289  mu = -0.09641
  y_inf   = 61.91     y0 = 22.83   
  n obs   = 4         rmse = 1.757
  converged = TRUE 

===== pillar2_neural =====
<edaphos_piml_neural_ode>
  dy/dz = f_theta(z, y), MLP hidden = 16 -> 16 
  n obs = 4  rmse = 1.38  final loss = 0.008627

===== pillar3_fit =====
<edaphos_temporal_convlstm>
  input_dim = 2   hidden = [12, 6]   kernel = 3
  return_sequence = TRUE   epochs = 120   final loss = 0.007865

===== pillar4_fit =====
<edaphos_foundation_simclr> (experimental; Pillar 4 scaffold)
  in_channels = 5  feature_dim = 16  proj_dim = 8
  batch = 32  temperature = 0.2
  epochs = 40  final loss = 2.84

===== pillar5_model =====
<edaphos_al_model>
  target     : soc 
  covariates : elev, slope, twi, map_mm, ndvi 
  coords     : x, y 
  n labeled  : 70 
  iterations : 9 
  last RMSE  : 4.942 

===== pillar5_history_tail =====
   iter n_labeled rmse_oob mean_uncertainty
6     5        50 5.387328          20.1760
7     6        55 5.376662          19.1320
8     7        60 5.294309          19.1900
9     8        65 4.913287          18.3640
10    9        70 4.942248          16.9916

===== pillar6_fit =====
<edaphos_quantum_krr>
  n_qubits = 3   reps = 2   lambda = 0.1
  n_train  = 140   training RMSE = 0.6431

===== pillar6_acc =====
test accuracy: 0.72  (60 test samples)

