# Extreme-aware convex formulation

For one state19 decision T, the nominal term is `J_base(T)=gamma*sum(T)+rho_chi2_eta(Q_nominal(T))`.
For each frozen physical path e, `L_e(T)=max_m Q(T,xi_e,m)` over its five deterministic replicas.
The tested stress risks are `R1(T)=max_e L_e(T)` and `R2(T)=average of the top-k L_e(T)`, with k=2 and k=3.
Each model minimizes `J_base(T)+beta_ext*R_ext(T)`, where `beta_ext=kappa*J_base(T_base)/R_ext(T_base)` and kappa is a behavior-test scale, not probability.
The extreme paths and replicas receive no nominal probability mass.
