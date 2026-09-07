# B4D Stable Checkpoint Review

Review date: 2026-09-07. This is a pre-commit record of mechanical checks on existing run-005 evidence. No simulation or optimization was rerun.

- Review: PASS; fixed cases 14/14; mandatory QA 25/25.
- Branch: `task/002-stage2b-b3-smoke`.
- Upstream: `origin/task/002-stage2b-b3-smoke`.
- Parent HEAD: `eeaeb65493bb844b86b4e3a1521eaf6ae6567069`.
- Initial ahead/behind: 0/0; staged files: none.
- Checkpoint commit: the commit introducing this file; intentionally not self-embedded.
- Push status at document creation: NOT_EXECUTED_YET. Final commit and remote verification are reported by the checkpoint task after push.
- Evidence scope: FULL_RUN_005_SMALL (compact engineering evidence). The 32 original files total 258208 bytes: 22 CSV, 8 JSON, 2 Markdown. Largest: final_summary.json 84631 bytes; precheck.json 83645 bytes; issue_by_issue_result_ledger.csv 11785 bytes.
- The original output_manifest.csv verifies all 31 listed artifacts; it predates and therefore excludes this checkpoint document. Original evidence remains byte-identical.

## Mechanical Evidence

All requested smoke, system-identity, no-op, direct-refuel OFF, B3 regression, B4C regression and design-readiness gates pass. CASE-10 arrives at 1.2166666666667 h. Summing its forensic interval ledger reproduces no-delivery EENS 1470.0 kWh and delivery EENS 785.00000000001 kWh, reduction 684.99999999999 kWh. This synthetic result establishes interface physics only, not formal HTT performance.

The 14 system-identity rows reconcile with maximum stored absolute residual 2.1316282072803006e-14 kg. Existing B3 run-005 evidence confirms 3883 checks PASS, mass residual 2.842170943040401e-14 kg and road C difference 0 km. Existing B4C run-008-b4d-regression evidence confirms 23 QA PASS, CASE-3/4 coupling gates PASS and identity residual 1.5987211554602254e-14 kg. These historical regression directories are not included in this checkpoint; their compact summaries are included.

All three B4D sources exist, are nonempty and parse/compile in memory. Their declared paths, benchmark constants, direct-refuel rejection, B3 motion calls and B4C interval calls correspond to run-005 evidence. No hardcoded absolute user/debug path, rescue optimizer, rolling dispatcher or formal W_OOS loop was found. Current B4D hashes are pinned below; the historical source-preservation manifest records protected B3/B4C sources, not B4D source hashes.

## Source Identity

All three sources are untracked before staging and classified B4D-created.

| Path | Bytes | SHA256 |
| --- | ---: | --- |
| W_OOS/V1/src/htt_state.py | 4504 | e42449def95ec6b62fdeed3265463bc8ab17dfea182c3e07f8493a0d9de0e252 |
| W_OOS/V1/src/htt_transfer.py | 9925 | 210b23344faf91f43155095df0fb3e665c09735f4eca79f5ded40e291d48e64b |
| W_OOS/V1/src/b4d_htt_given_action_smoke.py | 65403 | 118d7c3e79d143dcce5e796afceff222bb9a99041938d133077bbeadb0244941 |

B3 engine.py SHA256: `435245e9ccdae96ebf9ed4f6c8444445d7d575de2145bd778a2de6d8aaaf8407`.
B3 road.py SHA256: `9593be7482093711ba043df8ed5de5df34d4885d181ebf7bc23076a9f61fa842`.
B4C b4_event_driven_restoration_smoke.py SHA256: `93acc3107036da09c7e48b0f53941607a62d0f3f80359d2da9cbdc39f0f72c99`.
All match run-005 before/after hashes and have empty Git diffs against parent HEAD. The same check passes for the B3 test runner and protected MAT input listed in source_preservation_manifest.csv.

## Worktree Preservation

Baseline: tracked_dirty_before=31; untracked_before=23505 files / 783 status entries. The existing log diff consists solely of the B4D smoke entry; this checkpoint adds only its verified review entry. The other 30 tracked dirty files are PRE_EXISTING_DIRTY. All untracked content outside the exact manifest is PRE_EXISTING_UNTRACKED for staging purposes and remains local, including prior B4D attempts and regression outputs. No reset, stash, restore, clean, delete or move is used.

Expected after commit, subject to final mechanical verification: tracked_dirty_after=30; untracked_after=23470 files / 780 status entries; index empty. The 35 original untracked selected files become tracked; this new closeout is also committed. Baseline tracked SHA256 and every original untracked file's size/mtime are compared after push. MATLAB PID 9668 and its creation time are recorded before/after; no MATLAB/Gurobi process is launched or terminated.

## Exact 37-File Commit Manifest

```text
W_OOS/V1/src/htt_state.py
W_OOS/V1/src/htt_transfer.py
W_OOS/V1/src/b4d_htt_given_action_smoke.py
codex_rule/log.md
W_OOS/V1/results/b4d-htt-given-action/run-005/00_plain_language_summary_zh.md
W_OOS/V1/results/b4d-htt-given-action/run-005/00_report_zh.md
W_OOS/V1/results/b4d-htt-given-action/run-005/analysis_control_card.json
W_OOS/V1/results/b4d-htt-given-action/run-005/b3_regression_summary.json
W_OOS/V1/results/b4d-htt-given-action/run-005/b4c_regression_summary.json
W_OOS/V1/results/b4d-htt-given-action/run-005/B4D_checkpoint_closeout.md
W_OOS/V1/results/b4d-htt-given-action/run-005/case10_fixedFC_recovery_forensic.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/case13_station_mediated_refuel_forensic.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/case6_multistop_forensic.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/communication_qa.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/data_preservation_qa.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/direct_refuel_flag_audit.json
W_OOS/V1/results/b4d-htt-given-action/run-005/electrical_interval_ledger.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/electrical_root_ledger.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/exact_modified_files.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/final_summary.json
W_OOS/V1/results/b4d-htt-given-action/run-005/fixed_case_tests.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/htt_config.json
W_OOS/V1/results/b4d-htt-given-action/run-005/htt_event_timeline.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/HTT_H2_interval_ledger.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/htt_H2_transfer_ledger.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/htt_movement_ledger.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/htt_vehicle_state_ledger.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/issue_by_issue_result_ledger.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/level_coverage_matrix.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/MFCV_H2_interval_ledger.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/output_manifest.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/precheck.json
W_OOS/V1/results/b4d-htt-given-action/run-005/QA_closeout.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/QA_closeout.json
W_OOS/V1/results/b4d-htt-given-action/run-005/source_preservation_manifest.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/station_H2_interval_ledger.csv
W_OOS/V1/results/b4d-htt-given-action/run-005/system_H2_identity.csv
```

No B3/B4C historical result, BASE2/MSP/SAA/DRO file or unrelated output is selected. B4D semantics remain 2 x 80 kg HTT, station-only transfers, P=Q=0, no electrical root/source, traction NOT_MODELED_IN_B4D and direct HTT-to-MFCV OFF. No B5 or reference policy work is started.
