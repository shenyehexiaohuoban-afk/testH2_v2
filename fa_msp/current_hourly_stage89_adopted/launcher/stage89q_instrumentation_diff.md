# Stage89Q instrumentation-only difference

Stage89Q inherits the accepted Stage85R five-hour training/OOS workflow, the Stage85H-A clean-process checkpoint boundary, and the Stage89N Stage89K single-loc4 adapter. The two arms share the same source, training seed, ordered OOS bank, current Stage89J W identity, Stage89K DRO TerminalLOH (`eta=0.03`), correct six-by-eight-hour model, physical parameters, solver settings, and tolerances. The only intended arm input difference is `cost_reserve_shortage=1000` versus `1500` yuan/kg.

The Stage89Q additions are instrumentation only:

- run the serializer regression with an explicit hourly-serialization switch: the OFF solve emits no hourly/site/grid/OD rows, while the ON solve emits the persisted schema; compare path totals and every reached stage before source freeze;
- stop before starting a new training iteration once the common 18000-second budget has been reached;
- write existing per-iteration forward/training quantities to `training_progress.csv`;
- read already-solved hourly variables and stream them in 100-path batches;
- reconstruct only hour-begin inventory from the previous hour's direct ending inventory (or the stage-begin state), with an explicit `RECONSTRUCTED` label;
- stream existing directed hourly HTT flows sparsely above `1e-8 kg`;
- save existing grid/electrolyzer hourly summary quantities;
- add batch row-count markers, manifests, closure QA, postprocessing, and Chinese figures.

The PowerShell orchestrator creates a run only in `-SmokeOnly` mode. A later formal invocation may continue that same run only when every serializer regression and closure row is PASS, no failure/training/checkpoint artifact exists, and the current HEAD equals the explicitly supplied source-freeze commit. It never overwrites or resumes a partially trained arm.

No decision variable, constraint, objective term, bound, state transition, forward pass, backward pass, cut formula, Stage1 cut semantics, hourly grid/H2/HTT equation, demand mapping, or Stage7 calculation is changed. Serialization does not trigger another optimization solve beyond the deliberately paired OFF/ON smoke regression.
