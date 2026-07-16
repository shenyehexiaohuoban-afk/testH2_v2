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
