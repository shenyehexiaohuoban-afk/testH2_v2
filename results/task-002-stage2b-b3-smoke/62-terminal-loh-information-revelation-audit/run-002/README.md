# Step-05B-5 TerminalLOH information-revelation audit

Accepted read-only audit on the frozen baseline `06f10864f36a6358eb671632ce3e032ddf0ae97e`.

## Scope

- No MSP training, resampling, forward/backward pass, new cut, TerminalLOH change, or 200/2000 change.
- Common OOS: 10000x8, SHA-256 `6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85`.
- Information nodes use the true recombining FA-MSP exogenous state `(decision stage t, current Markov state k)`. The complete path or future terminal state is never used to define a node.
- All descendant frequencies use every frozen OOS path reaching that node. No-terminal descendants are retained as outcome zero with zero TerminalLOH.

## Key distinction

Step-05B-4's physical LP is clairvoyant: it knows the realized full path and terminal target before jointly reoptimizing earlier hydrogen flows. Its feasibility result cannot be interpreted as proof that the sequential FA-MSP policy had the same information.

## Information metrics

- `outcome_frequency`: empirical probability of a particular future outcome at `(t,k)`.
- `conditional_terminal_target_range`: station target range across terminal-state descendants, including valid zero-Target TerminalLOH states.
- `positive_target_modal_top_site_probability`: among descendants with a positive TerminalLOH vector, probability of the modal highest-target station.
- Exact-vector and top-site-certainty shares require exact equality within numerical tolerance; no arbitrary confidence threshold is used.

## Saved-cut audit boundary

The existing saved affine cuts are evaluated directly at archived replay inventory points. The maximum existing cut RHS identifies the active face. When multiple cuts tie, the first is reported and min/max/mean marginal values across tied cuts are retained. The audit covers 12 representative information nodes and is not a global proof about every saved cut.

The representative SAA models contain 1112 saved cuts and the representative eta=0.03 DRO models contain 1198 saved cuts.

## Output guide

- `total_capacity_gap_summary.csv`: system-total gap distribution for states16-19.
- `clairvoyant_lp_scope_audit.txt`: exact information boundary of Step-05B-4.
- `history_node_terminal_state_map.csv`: 289 information nodes and empirical descendant outcomes.
- `history_node_terminal_loh_dispersion.csv`: site-level mean/min/max/std/range by node.
- `stage_information_revelation_summary.csv`: lf=1..6 information curves for all OOS and selected subsets.
- `selected_path_inventory_trace.csv`: paired SAA/DRO inventory, production, ordinary service, and station allocation with node information.
- `selected_node_policy_alignment.csv`: stage/node aggregation of information and inventory alignment.
- `existing_cut_value_signal_audit.csv`: existing active-cut marginal value evidence.
- `state12_13_14_judgment.csv` and `state19_feasible_subset_judgment.csv`: bounded A/B/C/D classifications.
- `step05b5_judgment.txt`: final interpretation and next-step recommendation.

Final classifications: state12/state13/state14 are A information type; the physically feasible but unmet state19 subset is C mixed type; system-total-insufficient state16/17/18/state19 paths are E system-total type.
