# Step-03R False-Near Diagnostics

## Scope

This audit follows Bertsimas and Mundru, Optimization-Based Scenario Reduction for Data-Driven Two-Stage Stochastic Optimization, Operations Research (2023; an online version may carry 2022). The borrowed principle is that scenario similarity should be checked against optimization objectives and decisions, not geometry alone. This project does not reduce, delete, merge, or reweight scenarios; it tests D+Ctilde using four-site deterministic T, complete loss profiles, and finite counterfactual distributions.

The audited unscaled distance is d_new=0.6*d_D+0.4*d_Ctilde with kappa=1 and C_bound=357.1526447416079 km. Step-03Q median scaling is used only when reproducing its WDRO activity solution because positive scalar scaling leaves pair rankings unchanged.

## Overall decision

A. CTILDE_DECISION_SIMILARITY_VALIDATED

## Pairwise statistics

- simple: Spearman(d_new,d_T)=0.999998, Spearman(d_new,d_loss_profile)=0.999998, formal false-near pairs=0.
- medium: Spearman(d_new,d_T)=0.875977, Spearman(d_new,d_loss_profile)=0.9193, formal false-near pairs=0.
- complex: Spearman(d_new,d_T)=0.42022, Spearman(d_new,d_loss_profile)=0.77086, formal false-near pairs=0.

## Severe false-near cases

No pair simultaneously met the formal lowest-1%-distance and highest-1%-decision/loss criteria. Counterfactuals therefore use the most severe stress pairs inside the lowest-distance set.

## Step-03Q near-perturbation reconciliation

- simple: Step-03Q DeltaT=0, single-scenario d_T=0.0563693, profile distance=67643.1, classification=SCENARIOS_NOT_WDRO_KEY.
- medium: Step-03Q DeltaT=1.00982e-10, single-scenario d_T=0.251843, profile distance=93630.3, classification=DOMINATED_BY_MORE_SEVERE_ACTIVE_SCENARIOS.
- complex: Step-03Q DeltaT=0, single-scenario d_T=0.55195, profile distance=807106, classification=CAPACITY_SATURATION.

## Counterfactual checks

Each listed pair was solved as scenario r alone, scenario s alone, and a 50/50 two-scenario empirical distribution. The single-scenario rows use the deterministic two-stage tie break; the mixture uses the unchanged loss model with a common T.

- simple pair (1,2), basis=LOWEST_1PCT_STRESS_PAIR_NO_FORMAL_FALSE_NEAR, d_new=0, mix distance from r/s=0/0.
- simple pair (1,3), basis=LOWEST_1PCT_STRESS_PAIR_NO_FORMAL_FALSE_NEAR, d_new=0, mix distance from r/s=0/0.
- simple pair (2,3), basis=LOWEST_1PCT_STRESS_PAIR_NO_FORMAL_FALSE_NEAR, d_new=0, mix distance from r/s=0/0.
- simple pair (1036,1297), basis=STEP03Q_NEAR_PERTURBATION, d_new=0.0500673, mix distance from r/s=0.0563693/2.96813e-12.
- medium pair (855,1343), basis=LOWEST_1PCT_STRESS_PAIR_NO_FORMAL_FALSE_NEAR, d_new=0, mix distance from r/s=1.67141e-10/1.67143e-10.
- medium pair (1343,1400), basis=LOWEST_1PCT_STRESS_PAIR_NO_FORMAL_FALSE_NEAR, d_new=0, mix distance from r/s=1.67143e-10/1.67141e-10.
- medium pair (144,1018), basis=LOWEST_1PCT_STRESS_PAIR_NO_FORMAL_FALSE_NEAR, d_new=0, mix distance from r/s=1.67144e-10/1.67143e-10.
- medium pair (1281,1242), basis=STEP03Q_NEAR_PERTURBATION, d_new=0.0172533, mix distance from r/s=0.0381856/0.213658.
- complex pair (177,1529), basis=LOWEST_1PCT_STRESS_PAIR_NO_FORMAL_FALSE_NEAR, d_new=0.0516383, mix distance from r/s=8.52651e-15/0.450475.
- complex pair (375,836), basis=LOWEST_1PCT_STRESS_PAIR_NO_FORMAL_FALSE_NEAR, d_new=0.0516525, mix distance from r/s=0.381856/8.5502e-15.
- complex pair (375,649), basis=LOWEST_1PCT_STRESS_PAIR_NO_FORMAL_FALSE_NEAR, d_new=0.0486088, mix distance from r/s=0.374103/8.37256e-15.
- complex pair (1823,919), basis=STEP03Q_NEAR_PERTURBATION, d_new=0.118338, mix distance from r/s=2.20945e-10/0.55195.
