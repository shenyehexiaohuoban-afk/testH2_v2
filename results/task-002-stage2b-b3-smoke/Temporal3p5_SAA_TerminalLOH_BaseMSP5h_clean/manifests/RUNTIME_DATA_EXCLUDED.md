# BASE2-SAA runtime data excluded from Git

The files below remain preserved locally for reproducibility but are excluded
from this freeze commit because they are large runtime artifacts. Their exact
path, byte size, and SHA-256 are recorded here.

| Local path | Bytes | SHA-256 |
|---|---:|---|
| `training/runs/run-20260904-233558/training/checkpoint/checkpoint_final.mat` | 331093960 | `a1b1450519fc7ab9a0e4ae96f81aa397613990683f6ce39f7d2dd6d2984da18c` |
| `training/runs/run-20260904-233558/training/checkpoint/checkpoint_final.mat.latest.mat` | 331093960 | `a1b1450519fc7ab9a0e4ae96f81aa397613990683f6ce39f7d2dd6d2984da18c` |
| `training/runs/run-20260904-233558/training/checkpoint/checkpoint_final_20260905_043728752.mat` | 331093960 | `a1b1450519fc7ab9a0e4ae96f81aa397613990683f6ce39f7d2dd6d2984da18c` |
| `training/runs/smoke-20260904-233049/training/checkpoint/checkpoint_final.mat` | 304006448 | `1cd74cecb619222b6445b12a4e03afec758b4b028a9f27482b75e245d49438a3` |
| `training/runs/run-20260904-233558/oos_modeC/path_summary/oos_path_summary.csv` | 4516762 | `35f92651ee8ff99337144c65534a79a89e7cd372fe04a4e114c0fa404363a7e3` |
| `training/runs/run-20260904-233558/oos_modeC/path_summary/oos_stage_summary.csv` | 7736313 | `b04f65fc70de860ff24e40ad916f8306bbf074cba8fe9fc3e90507f34446904c` |
| `training/runs/run-20260904-233558/oos_modeC/path_summary/oos_stage_site_summary.csv` | 22188686 | `12213c2f052c9f62074a56223443c45d92f9794e9e67bb8ebe88b546964d7688` |
| `training/runs/run-20260904-233558/oos_modeC/hourly_site/oos_hour_site.csv` | 290372312 | `a8ab59eeba1930535bb856dbaa4fd1f360f43cc30fe7d23541012b01262ba2d4` |
| `training/runs/run-20260904-233558/oos_modeC/grid_hourly/oos_hour_system.csv` | 54332143 | `72d5c7875e00a6c37e27377d0b8398a6550233c1a9b02d3236638799662c885b` |
| `training/runs/run-20260904-233558/oos_modeC/htt_od/oos_positive_htt_flows.csv` | 1839904 | `67737041fdade940d37b4a4e9f5fc980feb4278fe3b439c6d9bb4c7cb74949d9` |
| canonical bank `results/task-002-stage2b-b3-smoke/89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000/run-003/oos/loc4/oos_path_bank.mat` | 108009 | `6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6` |

The local files were not deleted, moved, compressed, or overwritten.

## Source versus active candidate table

The frozen source table is the solver-native CSV at
`terminalLoh_wdro/partial_temporal_refinement/terminalLoh_saa_base2/run-001/terminal_loh_table_saa.csv`
with SHA-256 `1e2968cf045ea883a60cd2e287f6f26ac6a23b735a432e5235c0e68b905ca4`.
The active candidate table is the candidate-local loader CSV at
`program/terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_temporal3p5_saa_candidate.csv`
with SHA-256 `b74433fe8a19caedb75ac3071225480e279c136f3d1285ba503a184f12c5fcdc`.

Mechanical comparison confirms the 35 state rows carry the same `state_id`,
intensity, location, lfw, and T1-T4/total TerminalLOH numeric values. The SHA
difference is therefore due to the intentional loader packaging and schema:
the active table uses quoted CSV fields and adds candidate identity, SAA mode,
eta, tank-capacity, source-stage, and source-run metadata while omitting the
solver diagnostic/objective columns and absolute grouped-bank paths. This is a
format/metadata wrapper difference, not a changed TerminalLOH solution.
