# WDRO Look-Ahead Config

This directory keeps only the main Stage 2A W=3 look-ahead configuration
tables. These tables follow the MSP-stage idea of separate intensity,
location, and landfall/window inputs, but they are used only by the offline
WDRO-TerminalLOH look-ahead module.

## Main Tables

1. `lookahead_intensity_W3.csv`

   Typhoon intensity transition table.

   Columns: `from_a,to_a,prob`

2. `lookahead_location_W3.csv`

   Look-ahead location transition table on the extended `loc_id` line.
   `loc_id` may include zero or negative halo ids.
   `lookahead_location_W3.csv` is not a row-by-row copy of the original MSP
   location transition matrix; it extracts an empirical displacement kernel
   from `data/location.csv` and applies that kernel to the extended location
   set `loc=-2:10`, avoiding boundary truncation and allowing W=3
   look-ahead paths to enter the left and right halo regions.

   Columns: `from_loc_id,to_loc_id,prob`

3. `lookahead_window_W3.csv`

   Key-value table for global look-ahead settings.

   Required keys: `W`, `P`, `random_seed`, `loc_min`, `loc_max`,
   `halo_width`, `lf_terminal`

## Scope

- These files do not modify the original MSP state space.
- These files do not modify `data/location.csv`, `data/intensity.csv`, or
  `data/landfall_7.csv`.
- `W` is represented in path outputs by `tau=1,...,W`; it is not the original
  MSP `lf`, and this module does not introduce `lf=8,9,10`.
- The `row_id` mapping for MATLAB-safe indexing and other intermediate
  diagnostics are stored under:

  `terminalLoh_wdro/output/stage2_lookahead_W3/config_diagnostics/`

Downstream WDRO consequence samples should keep reachability `A` binary:
`A=1` means a feasible service path exists and `A=0` means fully unreachable.
Roads that remain passable but become slow should be represented by a larger
service cost / impedance / travel time `C`, not by fractional values such as
`A=0.3`.

## Post-Landfall W3 Transition Candidates

The three legacy files above remain unchanged and are retained for comparison.
Task-001 step-01 adds four separate engineering-candidate files:

1. `lookahead_intensity_postlandfall_W3.csv`
2. `lookahead_location_postlandfall_W3.csv`
3. `lookahead_lfw_postlandfall_W3.csv`
4. `lookahead_window_postlandfall_W3.csv`

The post-landfall intensity candidate reduces each existing `a=2:5`
enhancement probability to 20% of its legacy value. The removed probability
mass is allocated two-thirds to weakening and one-third to staying at the same
intensity. Enhancement remains possible but less likely. State `a=1` remains
absorbing, while `a=6` uses `6->5=0.60` and `6->6=0.40`.

The loc candidate uses the displacement kernel
`[-3,-2,-1,0,+1,+2,+3]` with probabilities
`[0.04,0.10,0.22,0.18,0.28,0.13,0.05]`. Most mass is assigned to adjacent
states, and farther moves in the same direction are less likely. Invalid
boundary targets are deleted and the remaining mass is renormalized; no
probability is clamped onto a boundary state.

The lfw candidate uses states `0:3` and a backward/stay/forward kernel of
`0.10/0.20/0.70`. Boundary rows delete invalid targets and renormalize the
remaining mass. A backward lfw transition is spatial trajectory variation; it
does not reverse time or restore previously damaged equipment.

`W1`, `W2`, and `W3` are consecutive one-hour time windows. They are not fixed
lfw states. The actual x coordinate is determined by loc, while the actual y
coordinate is determined by
`y = -89.9999703886 + lfw * 40`. The window value `P=20` is only the legacy
diagnostic sample count and is not the complete path count.

These probabilities are transparent and reproducible engineering candidates.
They have not been calibrated against real typhoon observations, have not been
accepted as final parameters, and are not connected to the formal path
generator yet.

### Run-002 Extension

Run-002 preserves the run-001 adjacent intensity probabilities and adds rare
two-level transitions. For `a=3:6`, `P(a->a-2)=0.02`; for `a=2:4`,
`P(a->a+2)=0.005`. These probabilities are deducted only from the stay
probability. State `a=1` remains absorbing, and two-level enhancement remains
less likely than two-level weakening.

The run-002 lfw kernel is backward/stay/forward-one/forward-two =
`0.05/0.18/0.75/0.02`. Invalid boundary probability is added to the stay
state, producing the exact rows documented in the run-002 audit. The loc and
Window candidate files are unchanged from run-001. Run-001 remains archived as
the adjacent-transition comparison case.

## Step-02A Main Path Sampling Convergence Audit

Step-02A samples the three independent post-landfall Markov chains jointly
from each initial state `a0=2:6`, `loc0=1:7`, `lfw0=0`. It compares nested
prefix samples at `N=[500,1000,2000,5000,10000]` for seeds
`20260721:20260725` against exact W1-W3 matrix-product distributions for
intensity, loc, lfw, and the joint `(a,loc,lfw)` state.

Run-001 passed all 11 implementation and integrity checks, and the three
candidate matrices remained byte-identical. No tested N met all convergence
criteria. At `N=10000`, the p95 maximum absolute error was `0.0094` and the
worst maximum absolute error was `0.0163`, but mean joint-state total variation
was `0.0359742731`, above the required `0.03`. Thresholds were not relaxed, so
no `main_path_samples.csv` was generated. The run is an ordinary sampling
audit only; it does not perform risk screening, tail enrichment, B3, WDRO,
Gurobi, or MSP execution.

### Run-002 Extension

Run-002 retains the same matrices, five convergence seeds, exact-distribution
method, and fixed thresholds. It tests nested samples at
`N=[15000,20000,30000]` and adds empirical transition-frequency checks against
all three configured matrices. The first passing sample size is `N=15000`,
with p95 maximum absolute error `0.0074`, worst maximum absolute error
`0.0154716667`, and mean joint-state total variation `0.0296189473`.

The largest empirical transition-probability error at the recommended N is
`0.00206671047`; no unsupported transition is observed. The fixed seed
`20260706` produces 15,000 paths for each of the 35 initial states, or 525,000
rows total. The resulting `main_path_samples.csv` is 64,519,633 bytes, so it is
kept in the ignored local output directory and represented in the Git archive
by `LARGE_FILE_MANIFEST.md` with its row count, size, and SHA-256.

### Run-003 Fixed-Seed Sample Audit

Run-003 reads the accepted run-002 `main_path_samples.csv` without resampling
or rewriting it. The source has 525,000 rows, exactly 15,000 rows for each of
the 35 initial states, and SHA-256
`972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d`.

Against exact W1-W3 matrix distributions, the fixed sample has p95 maximum
absolute error `0.00806666667`, worst maximum absolute error
`0.01313333333`, and mean joint-state total variation `0.02954596508`.
Nonconfigured transition records are zero. All acceptance criteria pass.

`path_probability` is retained only as an audit field. It must not be used to
reweight these already sampled records. Within each initial state, every main
sample record has the same empirical weight `1/15000`. Any downstream use that
weights the records again by `path_probability` would double-count the Markov
transition probabilities and change the intended empirical distribution.

## Step-02B-1 Observed Tail-Risk Coverage Audit

Step-02B-1 aggregates repeated records in the accepted 525,000-row main sample
without resampling. It evaluates each observed unique W1-W3 path with the
accepted Foundation wind model: `Rmax_ref=40`, radial decay `B=0.6`, the
existing intensity-to-Vmax mapping, and point-to-segment grid/road distances.
Grid and road exceedance thresholds are 25 m/s and 30 m/s.

The sample contains 256,884 observed unique paths. Across the 35 initial states,
the observed theoretical probability-mass coverage ranges from
`0.5887886837` to `0.7892712024`; path-count coverage ranges from
`0.0101094767` to `0.0174146284`. The equal-state mean theoretical mass
coverage is `0.6675433091`.

Risk quantiles use empirical mass `frequency/15000` within each initial state.
They never use `path_probability` as an empirical weight, and no artificial
combined risk score is formed. High-exposure paths are identified separately
for each risk proxy at the state-specific 99% and 99.5% quantiles. Pareto
candidates separately minimize theoretical path probability and maximize each
risk proxy. The audit does not generate supplemental paths or run B3/WDRO.

### Run-002 Corrected Observed Candidate Screening

Run-002 reads the run-001 unique-path risk table and stored q95/q99/q99.5
thresholds only. It does not recompute wind, quantiles, theoretical coverage,
or legal paths. Candidate risk must be positive. Values strictly above the
threshold and values tied at the threshold are reported separately; when a
threshold is zero, zero-risk paths are excluded.

Pareto screening is applied only inside the positive-risk candidate set for
the same initial state, risk proxy, and quantile level. Its two objectives are
lower `path_probability` and higher risk. Empirical mass remains
`frequency/15000`; `path_probability` is never used as an empirical weight.

After merging the four wind/exceedance proxies and removing duplicate paths,
q95/q99/q99.5 contain `23510/7316/4310` high-risk paths and
`268/239/215` Pareto paths. Boundary-tie path counts are
`5541/2387/1497`. Both per-proxy and combined candidate sets satisfy
`q99.5 subset q99 subset q95`.

### Run-003 Unobserved Legal-Path Search

Run-003 reads the run-001 joint-state wind-risk cache reference and quantile
thresholds, the corrected run-002 observed candidate keys, and the three
accepted postlandfall transition matrices. It does not resample the accepted
525,000-row main sample and does not modify any transition matrix.

The search constructs all nonzero joint transitions and caches the four
single-window risk contributions once for each of the 312 reachable
`(a,loc,lfw)` states. Reverse dynamic-programming upper bounds prune branches
whose best possible future risk cannot reach the applicable q95, q99, or
q99.5 threshold. Peak-wind proxies use a maximum recursion; cumulative
exceedance proxies use an additive recursion.

Across the 35 initial states there are 21,602,908 theoretical legal W1-W3
paths. The search fully expands 18,548,379 paths, a pruning ratio of
`0.141394343761`. Six representative weak/medium/strong and boundary/interior
initial states were also evaluated by streaming full enumeration. The pruned
search missed zero high-risk paths and added zero extra paths in those checks.

The four-proxy union contains 7,534,166 / 4,521,704 / 3,332,540 unobserved
high-risk legal paths at q95 / q99 / q99.5. The corresponding unobserved
Pareto counts are 858 / 788 / 764. Pareto screening is performed only within
the same initial state, risk proxy, and quantile level, minimizing theoretical
`path_probability` and maximizing risk. The theoretical probability is not an
empirical weight, and no combined risk score is constructed.

All 20 automated checks pass. The main sample remains 525,000 rows with
SHA-256 `972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d`.
The 2,121,759,312-byte detailed candidate table remains local under
`terminalLoh_wdro/output/`; Git stores the compact diagnostics, the small
Pareto table, and a large-file manifest. This run does not generate
supplemental samples or execute B3, WDRO, Gurobi, or MSP.

### Run-004 Pareto Archive Consistency Repair

Run-004 does not resample paths, recompute wind, or repeat the legal-path
search. It streams the existing run-003
`unobserved_high_risk_legal_paths.csv` and reexports rows whose stored Pareto
flags are already true.

Before repair, both the local and Git run-003 Pareto detail contained
`786/716/692` rows at q95/q99/q99.5, or 2,194 rows total. The accepted run-003
summary contained `858/788/764`, or 2,410 rows. The 216-row difference was
exactly the 72 Pareto paths per quantile level from initial states
`(a0,loc0,lfw0)=(2,1,0),(2,2,0),(2,3,0)`.

The discrepancy came from run-003 execution handling rather than the search
logic: after the outer command timed out, an incomplete-output cleanup attempt
overlapped the still-running MATLAB process. The Pareto detail lost its early
state blocks, while the large candidate table and the final summary remained
complete.

After reexport, the local and Git run-003 Pareto files both contain
`858/788/764` rows, total 2,410, with SHA-256
`c11670b10e311d48c12952817dfd589f2efdac97c98563bb28b228415e97489d`.
All 35 initial states and the three focus states match the unchanged run-003
summary. Every repaired row also has `pareto_only_output=1`. Run-004 has 18
passing checks and zero failures.

### Run-005 Physical Tail-Path Deduplication and Labels

Run-005 combines the run-002 observed Pareto detail and the corrected run-004
unobserved Pareto detail. It defines a physical path only by the complete
initial/W1/W2/W3 sequence
`(a0,loc0,lfw0,a1,loc1,lfw1,a2,loc2,lfw2,a3,loc3,lfw3)`.
No state from a different initial condition is merged, and no similarity-based
path reduction is performed.

The two inputs contain 1,595 observed source records and 2,410 unobserved
source records, or 4,005 label records total. Exact physical-key deduplication
produces 1,126 unique paths and removes 2,879 repeated proxy/quantile records.
There are 268 observed paths and 858 unobserved paths, with zero physical-path
overlap between the sources.

The q95/q99/q99.5 sets contain 1,126 / 1,027 / 979 unique paths. Their labels
are nested: 99 paths appear in one quantile level, 48 in two levels, and 979 in
all three. `highest_listed_level` is only a reporting field; all individual
level and proxy labels remain in `unique_tail_paths.csv`.

Unique paths selected by each risk proxy are: grid peak wind 310, grid
cumulative exceedance 779, road peak wind 310, and road cumulative exceedance
811. Across the 35 initial states, candidate counts range from 19 to 53, with
mean 32.1714 and median 33.

All duplicate records have consistent `path_probability` within tolerance
`1e-12`; the conflict count is zero. The accepted main sample remains 525,000
rows with SHA-256
`972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d`.
Run-005 has 13 passing checks and zero failures. It does not select B3
representatives or run sampling, wind calculations, path search, D/A/C, B3,
WDRO, Gurobi, or MSP.

## Step-03A B3-Smoke Fixed-Resistance Consequence Chain

Step-03A run-001 uses the accepted `persistent_fixed_resistance` convention
with `Rmax=40`, `Wstep=40`, three 1 h slices, and no repair. It is a smoke test
of the path-to-consequence chain only; it does not define a formal nominal
distribution and does not run WDRO or MSP.

Five initial states are selected deterministically from the run-005 candidate
count distribution: `(5,4,0)` minimum count, `(2,6,0)` maximum count,
`(2,1,0)` low-intensity/left-location, `(4,4,0)` medium/center, and `(6,7,0)`
high-intensity/right-location. Each state contributes two ordinary main-sample
paths, two observed candidates, and two unobserved candidates, giving 30 unique
physical paths. Each path has 20 fixed-resistance repetitions, or 600 B3-smoke
scenarios.

Ordinary paths retain `frequency/15000`; observed candidates retain their
existing main-sample weight and are not added again. Unobserved candidates have
`empirical_weight=0` and `nominal_inclusion_status=pending_after_B3`. The 30
selected paths must not be interpreted as an equal-weight probability model.

Each line and road draws one fixed resistance threshold per path/repetition and
reuses it across W1-W3. Failed lines, closed roads, and slowdown severity are
persistent for the full 3 h. The path's actual stage-specific `a`, `loc`, and
`lfw` determine Vmax and center coordinates. D is
`P_loss_kW * 1 h / (eta_FC * LHV_H2)` in kg-H2. A is binary. C uses finite
masked cost: current shortest-path `dist(n)` when A=1 and zero when A=0.

The ordinary/observed/unobserved source groups have Hres3h D ranges
`[0,607.9699]`, `[18.0018,607.9699]`, and `[22.9114,607.9699]` kg. Their mean
site-node reachable shares are `0.95338`, `0.61340`, and `0.52947`. Overall
masked C ranges from 0 to `102.9575 km`.

Final-stage multi-line-failure shares are `0.395/1.000/0.990`, and road
disconnection shares are `0.255/0.765/0.900` for ordinary/observed/unobserved.
All 400 candidate scenarios have structural and full consequence signatures
not present in the 200 selected ordinary smoke scenarios. This is a smoke-set
comparison only, not a claim against every path in the full 525,000-row main
sample.

All 16 automatic checks pass. Fixed-threshold reuse, damage persistence, D/A/C
domains, 20 repetitions per path, path traceability, same-seed replay, input
hash preservation, and prohibited-call scans all pass. The 858 unobserved
candidates remain `pending_after_B3`; run-001 does not decide their inclusion.

## Step-03B Expanded B3 Candidate Validation

Step-03B run-001 evaluates all 1,126 run-005 candidates and 1,126 matched
non-candidate main-sample references. Each of the 35 initial states contributes
the same number of references as candidates. Reference paths are selected
deterministically across low, medium, and high values of an unweighted envelope
of the four accepted wind-risk proxy percentile ranks. No candidate path is
included in the reference set.

All 2,252 paths use 20 `persistent_fixed_resistance` repetitions, producing
45,040 scenarios and 135,120 W-stage summaries. The observed candidates retain
their main-sample empirical identity. The 858 unobserved candidates keep
`empirical_weight=0` and `nominal_inclusion_status=pending_after_B3`; this run
does not form a formal expectation or change the nominal distribution.

The repeated maximum `607.969887897881 kg-H2` is the physical consequence of
all non-source-node load being unavailable for all three 1 h slices. It is
derived from `P_loss * 3 h / (eta_FC * LHV_H2)`, not a capacity clip or a
hardcoded D cap. There are 11,761 upper-bound hits: 1,194 matched-reference,
1,533 observed-candidate, and 9,034 unobserved-candidate scenarios. No scenario
exceeds the derived bound and the evaluator contains no D clipping assignment.

Matched reference / observed candidate / unobserved candidate Hres3h mean D is
`160.2241 / 478.4650 / 545.6251 kg`. Their site-node reachable shares are
`0.92654 / 0.50413 / 0.35694`; A=0 shares are reported separately from C.
Reachable-only mean C is `19.9383 / 22.0855 / 21.6891 km`. The unobserved
candidate W3 reachable share falls to `0.18761`, with a mean 16.87 nodes per
scenario unreachable from every site.

Against all 22,520 matched-reference scenarios, candidate scenarios produce
22,480 structural signatures and 22,485 full D/A/C signatures not present in
the reference set. No candidate exceeds the reference D maximum because the
reference set already reaches the physical full-outage bound. The informative
difference is therefore the higher saturation frequency, lower accessibility,
and new line/road/A/D/C combinations, not a higher numerical cap.

All 21 automatic checks pass. The 66,314,882-byte stage summary remains under
`terminalLoh_wdro/output/`; Git records its 135,120 rows and SHA-256 in a large
file manifest. No WDRO, Gurobi, optimization, or MSP is run.

## Step-03C Tail Probability Mass and Path-Level Consequences

Step-03C run-001 is a read-only audit of run-005 and the accepted Step-03B
45,040 scenarios. It does not call the wind, damage, or B3 evaluators. Each of
the 1,126 candidate paths is aggregated over exactly 20 resistance repetitions
into one path-level row. The 268 observed and 858 unobserved identities remain
unchanged.

For each of the 35 conditional initial states, the observed candidate
theoretical probability mass ranges from `5.80636056e-09` to
`5.754577669888e-05`; the unobserved candidate mass ranges from
`4.0679136e-12` to `3.49390100192e-07`; the combined candidate mass ranges
from `5.84841098533333e-09` to `5.7609148814144e-05`. These are products of
the three accepted intensity, loc, and lfw transition matrices. The maximum
matrix-recomputation error against run-005 is `6.7763e-21`.

Observed candidate path-average D ranges from `26.7572` to `607.9699 kg-H2`;
unobserved candidate path-average D ranges from `112.2794` to
`607.9699 kg-H2`. Their mean full-loss shares are `0.28601` and `0.52646`,
mean A=0 shares are `0.49587` and `0.64306`, and path-level reachable-only C
means range over `9.3959-30.6830 km` and `7.9596-33.3234 km` respectively.

The equal-weight mean across the 35 conditional states gives unobserved-tail
raw contributions of probability mass `2.99832e-08`, D `1.81499e-05 kg`,
full-loss probability `2.62699e-08`, and A=0 probability `2.69712e-08`.
These values are candidate-subset contributions only. They are not divided by
candidate probability mass and are not a formal nominal expectation.

The exact full D/A/C comparison marks 22,485 candidate scenarios as novel.
After rounding D to 1 kg and reachable C to 1 km while retaining the A pattern,
22,417 remain novel. Independent structural diagnostics find 21,446 novel A
patterns, 22,225 novel line-failure combinations, 22,292 novel road-disconnect
combinations, and 22,480 novel joint line-road/full structural scenarios.
Therefore the novelty is not explained only by continuous floating-point C
differences.

All 16 automatic checks pass. Probabilities are not renormalized, no candidate
is assigned `1/15000` as theoretical probability, and all 858 unobserved paths
remain `empirical_weight=0` and `pending_after_B3`. No wind/B3 rerun, WDRO,
Gurobi, optimization, or MSP is executed.

## Step-03D Nominal B3 Sample-Size Stability

Step-03D run-001 uses only the accepted 525,000-row main Monte Carlo sample.
For each of the 35 initial states and three reproducible seeds, the 15,000 main
records are deterministically permuted once. The tested sizes
`N=[500,1000,2000,5000,10000,15000]` are exact nested prefixes. Every selected
record has weight `1/N`; `path_probability` is not applied as a second weight.

Each record receives one `persistent_fixed_resistance` B3 scenario. The run
evaluates 1,575,000 full scenarios plus 52,500 same-seed N=500 replay scenarios.
The replay is identical for all 105 state/seed blocks. The 268 observed-tail
paths appear only through their natural main-sample records; no candidate rows
are appended and none of the 858 unobserved candidates appears.

Relative to the same-state/same-seed N=15,000 reference, the p95 absolute
errors for N=500/1000/2000/5000/10000 are:

- D mean: `12.4923/9.7748/5.8828/3.3914/1.9514 kg`;
- D q95: `50.7323/36.0036/29.4575/16.0925/7.0916 kg`;
- D q99: `73.3710/42.5497/27.2755/22.9114/13.0922 kg`;
- full-loss probability: `0.0252/0.0202/0.0092/0.0050/0.002833`;
- A=0 share: `0.015970/0.009228/0.006277/0.003378/0.001618`;
- reachable C mean: `0.16945/0.15413/0.09403/0.05037/0.02870 km`;
- reachable C q95: `0.89813/0.67963/0.45014/0.21681/0.13709 km`.

The slowest metrics are full-loss probability in relative terms and D q99 in
absolute/seed-dispersion terms. Low-risk states can have a near-zero N=15,000
full-loss reference, so small absolute count changes create relative errors of
100% or more. At N=10,000 the D q99 p95 absolute error is still `13.0922 kg`
and its p95 across-state seed standard deviation is `16.2771 kg`.

No accepted B3 D/A/C stability threshold exists in the project. The run does
not invent one. The conservative diagnostic recommendation is therefore
`N=15000` per initial state, the largest tested and reference sample. This is a
sample-design recommendation, not a formal threshold PASS decision.

All 15 automatic checks pass. Four PNGs report D, accessibility/full-loss,
reachable C, and W3 damage-count convergence. No nominal probability change,
candidate augmentation, WDRO, Gurobi optimization, or MSP is executed.

## Step-03E Intensity-to-Vmax Mapping Sensitivity

Step-03E run-001 uses the five Step-03A representative states
`(5,4,0)`, `(2,6,0)`, `(2,1,0)`, `(4,4,0)`, and `(6,7,0)`. For each state
and the three Step-03D resistance seeds, it reuses the exact first 2,000
records of the Step-03D nested permutation. The same path, line resistance,
and road resistance inputs are shared by all wind modes.

The accepted fixed map is M0: `[0,20.8,28.55,37.05,46.20,55.50] m/s`.
The bounded sensitivity intervals for `a=2:5` are
`[17.2,24.4]`, `[24.5,32.6]`, `[32.7,41.4]`, and `[41.5,50.9] m/s`,
referenced to the current national standard `GB/T 19201-2006 Grade of
tropical cyclones`, supervised and administered by the China Meteorological
Administration. M1 uses one `Uniform(0,1)` grade quantile per path consequence
realization, shared across W1-W3. This is a sensitivity assumption, not an
accepted wind-speed distribution. M2L and M2H use the bounded low and high
endpoints. `a=1` remains 0; `a=6` remains 55.5 in every mode because the
standard does not provide a finite upper bound.

Across the 15 state/seed blocks, the mean M0/M1/M2L/M2H D values are
`153.85/155.24/109.28/205.29 kg-H2`. Relative to M0, M1 changes mean D by
`+1.39 kg-H2` on average, while M2L and M2H change it by `-44.57` and
`+51.44 kg-H2`. M2H also raises mean A=0 share by `0.04`, W3 failed lines by
`2.04`, and W3 closed roads by `1.47`; M2L lowers them by `0.03`, `1.60`, and
`1.03` respectively.

The endpoint effects are explained by threshold crossings. Relative to M0,
M2H adds 282,749 grid-line observations above 25 m/s, 15,270 above 50 m/s,
and 282,845 road-edge observations above 30 m/s. M2L removes 290,033 grid
observations above 25 m/s and 295,291 road observations above 30 m/s. No road
observation exceeds 60 m/s because the tested maximum remains 55.5 m/s.

M0 reproduces all Step-03D N=2000 metrics with maximum absolute difference
`4.55e-13`. All 15 automatic checks pass. Endpoint mapping shifts are often
much larger than the Step-03D three-seed dispersion, but `a=6` occurs in the
tested paths and lacks a traceable finite upper bound. The decision is therefore
`INCONCLUSIVE_NEEDS_A6_DATA`; no random-wind model is adopted. No candidate
path, WDRO, Gurobi optimization, or MSP is used.

## Step-03F a=6 Wind-Data Audit and Sensitivity

Step-03F run-001 traces the accepted `a=6 -> 55.5 m/s` value through the
offline preview, Foundation, persistence, and B3 consequence chains. The value
is already hardcoded in the initial Git snapshot. None of the defining source
files links it to a paper, historical sample, or configuration record, so its
pre-repository origin cannot be recovered from this repository.

The historical audit uses the CMA best-track annual files from 1949 through
2024. The files were obtained through the ModelScope `ai4s/CMA` mirror of the
CMA Tropical Cyclone Data Center files; the original CMA source remains
`tcdata.typhoon.org.cn`. The CMA archive SHA-256 is
`1e36a4bf58088a2d9c32fc944c6cba8433a0d735894a6d64a68a5ec4d1aa2105`.
The CMA operational definition is the maximum 2-minute mean wind near the
10 m lower-level cyclone center, as confirmed by CMA under
`GB/T 19201-2006`.

Filtering `category=6` and wind `>=51 m/s` gives 4,084 time records from 454
storms. The record-level distribution is: minimum `52`, mean `62.0872`, median
`60`, q75 `65`, q90 `75`, q95 `80`, q99 `90`, and observed maximum `110 m/s`.
The observed maximum is a sample maximum, not a physical upper bound. One CMA
record marked category 6 at 50 m/s is excluded by the current threshold, as is
one 55 m/s extratropical-category record.

IBTrACS v04r01 is used only as a cross-check. The audit selects `cma_wind`,
requires the CMA agency interpolation flag `O`, converts knots to m/s, and
excludes USA/JTWC 1-minute, JMA/Tokyo 10-minute, WMO aggregate, and interpolated
CMA winds. The 4,084 rounded IBTrACS CMA-source winds exactly match the sorted
CMA source sample. The IBTrACS NetCDF SHA-256 is
`77b686af554b33ddec7b11d9e32d726ada90c5ce8c4e1a37c2c1d89e39fab5cc`.

The paired sensitivity reuses the Step-03E five states, N=2000 prefixes, and
three fixed-resistance seeds. Only the a=6 value changes:
`M0=55.5`, `M6_MEDIAN=60`, `M6_Q90=75`, and `M6_Q95=80 m/s`. Of the 30,000
path records, 2,495 contain a=6 and 27,505 do not. Every no-a=6 consequence is
bitwise identical across modes.

Across all 15 state/seed blocks, M0/median/q90/q95 D means are
`153.850/159.459/168.677/169.930 kg-H2`; full-loss shares are
`0.03463/0.04103/0.06270/0.07140`; A=0 shares are
`0.05984/0.06587/0.09315/0.10182`; W3 failed-line means are
`4.485/4.663/5.379/5.610`; and W3 closed-road means are
`2.327/2.491/3.246/3.531`.

Within the 2,495 records that actually contain a=6, the median/q90/q95 modes
increase mean D by `67.44/178.28/193.35 kg-H2`. Q90 and q95 changes exceed
the accepted Step-03E M0 three-seed ranges for primary consequences. The
decision is therefore `REVISE_A6_MAPPING`. This is a recommendation to perform
a separate mapping-calibration task, not an automatic modification: the formal
55.5 m/s value remains unchanged. No candidate paths, WDRO, Gurobi optimization,
or MSP are used.

## Step-03G Bounded Random a=6 Wind Sensitivity

Step-03G run-001 keeps the formal intensity mapping unchanged and compares the
current `a=6 -> 55.5 m/s` value with the project-bounded sensitivity assumption
`Triangular(51,55.5,60) m/s`. The value 60 m/s is only this study's
computational limit; it is not an official or physical upper bound and is not
used to reinterpret the Step-03F historical audit.

The test reuses the Step-03E/03F five representative states, the N=2000 nested
main-sample prefixes, and seeds `20260723:20260725`. This gives 30,000 base
path-resistance scenarios and 60,000 reported mode consequences. Wind and
component-resistance seeds are separate and reproducible. Each base scenario
draws one wind quantile, shared across W1-W3, and only stages with `a=6` use the
sampled value. All 27,505 no-a=6 records are exactly identical between modes.

There are 2,495 a=6 records. Their sampled winds have minimum/mean/median/q90/
q95/maximum values of `51.0524/55.4716/55.4356/57.9939/58.6354/59.7821 m/s`,
all within `[51,60]`.

Across all 15 state/seed blocks, M0/M1 mean D values are
`153.849821/153.758503 kg-H2`; mean D q95 and q99 are unchanged at
`341.215940/390.002637 kg-H2`. Full-loss shares are
`0.0346333/0.0347667`, A=0 shares are `0.0598385/0.0599755`, reachable-only C
means are `20.035187/20.033156 km`, W3 failed-line means are
`4.485067/4.486367`, and W3 closed-road means are `2.326967/2.330933`.

Within the a=6 blocks, M0/M1 mean D values are `384.422058/384.055026 kg-H2`,
full-loss shares are `0.103809/0.107230`, A=0 shares are
`0.271925/0.271061`, reachable-only C means are `21.520843/21.567995 km`, W3
failed-line means are `15.112341/15.370288`, and W3 closed-road means are
`10.063788/10.218124`.

All 19 automatic checks pass. M0 matches the accepted Step-03E metrics within
`4.55e-13`, and the random-input identities match Step-03F. The decision is
`NEED_MORE_VALIDATION`: bounded random a=6 winds change some outcomes, but the
all-record shifts are mixed and none of the five primary comparisons exceeds
the existing Step-03D N=2000 p95 stability-error benchmark. The formal 55.5
m/s mapping is not modified. No candidate path, full B3 rerun, WDRO, Gurobi
optimization, or MSP is used.

## Step-03H Full-Intensity Stagewise Random Wind Sensitivity

Step-03H run-001 compares the current fixed mapping with an isolated
stagewise-random sensitivity mode. For each path-resistance scenario, M1 draws
independent `q1/q2/q3 ~ Uniform(0,1)` values for W1-W3. Equal intensity levels
in consecutive stages still receive new draws. Wind randomness remains part of
the second-layer joint B3 consequence realization; no third Monte Carlo layer
is introduced.

M1 uses triangular distributions by intensity level:
`a2=(17.2,20.8,24.4)`, `a3=(24.5,28.55,32.6)`,
`a4=(32.7,37.05,41.4)`, `a5=(41.5,46.2,50.9)`, and
`a6=(51,55.5,60) m/s`; a1 remains fixed at zero. The 60 m/s value retains the
Step-03G interpretation as a project computational limit, not an official or
physical upper bound.

The 90,000 stage-level draws contain 9,660/27,519/6,483/18,033/24,593/3,712
records for a1-a6. Their observed minimum/mean/median/q95/maximum speeds are:

- a1: `0/0/0/0/0 m/s`;
- a2: `17.2295/20.7934/20.7901/23.2651/24.3729 m/s`;
- a3: `24.6029/28.5230/28.5173/31.2895/32.4979 m/s`;
- a4: `32.7376/37.0596/37.0557/40.0742/41.3704 m/s`;
- a5: `41.5259/46.1784/46.1708/49.3650/50.8578 m/s`;
- a6: `51.2069/55.5386/55.4992/58.6818/59.9292 m/s`.

Across all 15 state/seed blocks, M0/M1 D mean is
`153.849821/155.874769 kg-H2`, D q95 is `341.215940/342.506978`, and D q99 is
`390.002637/392.221040`. Full-loss share changes from
`0.0346333` to `0.0353667`; A=0 share from `0.0598385` to `0.0612824`;
reachable-only C from `20.035187` to `20.049725 km`; W3 failed lines from
`4.485067` to `4.569500`; and W3 closed roads from `2.326967` to `2.393033`.

The paired stage D increases are `0.592787/0.644683/0.787479 kg-H2` for
W1/W2/W3. Failed-line increases are `0.036367/0.056133/0.084433`, and closed-
road increases are `0.023367/0.040633/0.066067`.

Relative to M0, M1 creates 54,438 upward and 50,866 downward grid-line
crossings at 25 m/s, 471/214 at 50 m/s, 47,656/56,483 road-edge crossings at
30 m/s, and no road-edge crossings at 60 m/s. The mixed up/down counts arise
because symmetric bounded grade-level sampling moves individual stage winds
both above and below the fixed representative values.

All 20 automatic checks pass. M0 matches Step-03E within `4.55e-13`; paths and
component resistance inputs match Step-03F. All five primary risk shifts are
nonnegative, but none exceeds the corresponding Step-03D N=2000 p95 sampling-
error benchmark. The decision is therefore `NEED_MORE_VALIDATION`. The formal
fixed mapping remains unchanged, and no candidate path, full B3 rerun, WDRO,
Gurobi optimization, or MSP is used.
