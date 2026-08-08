# Step-04C-C6 35-state SAA versus eta=0.03 TerminalLOH tables

Status: **ACCEPTED**
Judgment: **A**

The directory/file token `eta003` means `eta=0.03`; it does not mean eta=0.003.
All 35 frozen initial states were solved independently on their own 15000 nominal scenarios for SAA and Pearson chi-square eta=0.03, giving 70 isolated optimization combinations and two complete 35x4 TerminalLOH tables.
Every optimization combination ran in one isolated Python 3.9/gurobipy 12.0.1 process. SAA, DRO decomposition, independent fixed-T audit, and strict two-phase lexicographic replay ran inside that case process; the process exited and was released before the next case started. MATLAB Gurobi MEX was not used for the 70 optimization cases.
Different states were not pooled, path_probability was not reused, and each state's nominal record weight is 1/15000.

The primary objective is the frozen C5B/C5C yuan-consistent preparation plus shortage/VOLL objective. `C*y` is a strict lexicographic secondary tie-break and is neither currency nor transport cost.
State19 SAA and eta=0.03 reproduce C5C within the frozen tolerances. Every optimization, probability, LB/UB, strong-duality, lexicographic, state mapping, and EENS audit passed.

The 35-state equal-state means are descriptive, not probability-weighted expectations. No initial-state prior probability was constructed.
C2 independent paths, C3 Markov shifts, and the fixed pressure set were not rerun; their state19 conclusions are referenced from C5B/C5C.

eta=0.03 gives stable mean-EENS or q95 improvement across most relevant states and is suitable as the representative high-guarantee DRO table for MSP comparison.
Eta remains unfrozen. Eta=0.03 is only a representative high-guarantee radius for comparison, and inventory cannot solve complete road inaccessibility.
