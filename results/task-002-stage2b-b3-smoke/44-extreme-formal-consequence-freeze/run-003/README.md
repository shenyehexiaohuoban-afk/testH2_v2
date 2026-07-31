# Step-04C-A2 extreme formal consequence freeze

Mechanical audit: **PASS**.

- The 268 support-in paths were replayed from their existing nominal formal identities. The historical proxy composite has Spearman rho `0.526366`, q95 hit rate `0.166667`, and obvious-false-positive share `0.416667` against the one existing formal consequence realization per path.
- All six state19 support-in paths include complete SAA and DRO total and W1-W3 shortage detail. DRO improves formal loss on `1` of the six and worsens none.
- All 858 support-out paths received five deterministic conditional consequence replicas: 4,290 unique namespace identities. Random-stream collision, byte replay, D/A/C domain, persistence, and business-logic audits passed: `True`.
- Under state19 SAA T, 3919 replicas and 787 paths meet the conservative low-theoretical-probability/high-formal-loss rule. The reference state19 nominal q95/q99 losses are `61314.277096` / `188736.506145`.
- State19 SAA mean loss/shortage on the 4,290 replicas are `419577.004127` / `208.386979 kg`; DRO values are `418595.750349` / `207.890628 kg`. DRO improves loss on `0.215152` of replicas.
- The consequence replicas are frozen stress realizations, not empirical probabilities. No enhanced DRO, eta/epsilon calibration, all-state optimization, WDRO, MSP, Word, transition-matrix, or formal generator modification was performed.

Classifications:

- `A. FORMAL_CONSEQUENCE_IDENTITIES_FROZEN`
- `H-A. SUPPORT_OUT_EXTREMES_ACTUALLY_HARMFUL`
- `A. PROCEED_TO_STEP04C_B_EXTREME_AWARE_DRO`

Runtime: `312.340999 s`; solver calls: `10`; fixed-T scenario evaluations: `64940`.
