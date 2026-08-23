# Stage-89P original-paper analysis mapping

Stage89P borrows the *result-analysis structure* of Siddig & Song, not their numerical values. The local paper copy is `tmp/pdfs/siddig_song_2201.10678.pdf` (SHA-256 is recorded in `source_manifest.csv`). Sections 4.1-4.3 first report OOS policy performance with 95% confidence intervals, then show action by period and by observed hurricane intensity/cost setting; the random-landfall model treats dissipation and landfall as absorbing events.

| Original-paper analysis object | Stage89P project counterpart | Comparability |
|---|---|---|
| Relief procurement by period (Eq. 21; Figures 6-7; Tables 6-7) | H2 production in operating Stages 1-6 | Structural analogy; units and physical constraints differ |
| Supply-point inventory / prepositioning | Four-site H2 inventory | Structural analogy; H2 faces ongoing ordinary demand and electrolysis limits |
| Observed hurricane intensity | FA-MSP current `a_t`, observed before the Stage-t decision | Direct state-role analogy; intensity scales are not numerically interchangeable |
| Predicted/landfall location | FA-MSP current `loc_t` | State-role analogy; geometry and service model differ |
| Random landfall time and hurricane dissipation | True Stage7 arrival and physical `a=1` dissipation | Related random-termination structure; `lf=8` is separately reported as absorbing, not dissipation |
| Unmet relief demand at landfall | Ordinary H2 shortage during preparation | NOT DIRECTLY COMPARABLE: timing and service meaning differ |
| Logistics cost plus unmet-demand penalty | Actual modeled operating cost plus ordinary shortage cost | Partial analogy; Stage89P separates the soft TerminalLOH penalty |
| Clairvoyance/perfect-information benchmark | Potential deterministic 48h solve with the full OOS path known | FUTURE OPTION ONLY; not run in Stage89P |
| None with an exact one-to-one role | Stage7 TerminalLOH soft reserve target/gap | NOT DIRECTLY COMPARABLE; it is a soft adequacy target, not realized disaster H2 demand |

The paper's main OOS sample is 1000 paths and uses mean +/- 1.96 standard errors. Stage89P uses the same normal-mean formula on 10000 accepted OOS paths and Wilson intervals for event probabilities. No perfect-information, rolling-horizon, static two-stage, or new benchmark optimization was run.
