# Repository File Audit

Audit date: 2026-07-14

Scope: read-only scan of `C:\Users\chaos\Desktop\biye\test\testH2_v2` before
preparing the initial GitHub baseline. No model, data, or output file was changed.

## Repository Size

- Files scanned: 370
- Total size: approximately 0.294 GB
- Files larger than 20 MB: 4
- Files larger than 50 MB: 1
- Files larger than 100 MB: 0

### Files Larger Than 20 MB

| Size (MB) | >50 MB | >100 MB | Path | Classification |
|---:|:---:|:---:|---|---|
| 94.11 | yes | no | `terminalLoh_wdro/output/stage2_lookahead_W3_B2_DAC_samples_R200/lookahead_scenario_site_node.csv` | Generated output; ignore |
| 29.41 | no | no | `terminalLoh_wdro/output/stage1_single_window_DA_update/terminal_loh_allocation_WDRO.csv` | Generated output; ignore |
| 23.89 | no | no | `terminalLoh_wdro (2).zip` | Duplicate/archive transfer file; ignore |
| 21.48 | no | no | `terminalLoh_wdro.zip` | Archive transfer file; ignore |

The 94.11 MB CSV is below GitHub's 100 MB single-file limit but is close to it
and is a reproducible output, so it must remain excluded.

## Archives and Video

- ZIP: `terminalLoh_wdro.zip` (21.48 MB)
- ZIP: `terminalLoh_wdro (2).zip` (23.89 MB)
- RAR: none
- 7z: none
- Video files (`mp4`, `mov`, `avi`, `mkv`, `wmv`, `webm`, `mpeg`, `mpg`,
  `m4v`): none

## MAT, FIG, and Large CSV Files

### MAT Files

| Size (MB) | Path | Recommendation |
|---:|---|---|
| 17.85 | `output_h2/wind_terminal_loh_preview/terminal_loh_wind_mc_preview.mat` | Generated output; ignore through `output_h2/` |
| 0.47 | `output_h2/details/selected_path_diagnostics.mat` | Generated output; ignore through `output_h2/` |
| 0.01 | `data/yuanqi/near_stage_msp_input.mat` | Required input; upload |
| 0.01 | `data/yuanqi/near_stage_seed_compat.mat` | Required compatibility input; upload |

FIG files: none found. No broad `*.mat` or `*.fig` ignore rule is used because
MAT inputs can be required research data and FIG files may later be intentional
source artifacts.

### CSV Files Larger Than 5 MB

| Size (MB) | Path |
|---:|---|
| 94.11 | `terminalLoh_wdro/output/stage2_lookahead_W3_B2_DAC_samples_R200/lookahead_scenario_site_node.csv` |
| 29.41 | `terminalLoh_wdro/output/stage1_single_window_DA_update/terminal_loh_allocation_WDRO.csv` |
| 18.98 | `output_h2/wind_terminal_loh_preview/wdro/terminal_loh_allocation_WDRO.csv` |
| 18.98 | `terminalLoh_wdro/output/stage1_single_window/terminal_loh_allocation_WDRO.csv` |
| 15.63 | `terminalLoh_wdro/output/stage2_damage_persistence_v2/damage_persistence_v2_by_slice.csv` |
| 13.99 | `terminalLoh_wdro/output/stage2_lookahead_W3_B1_DAC_samples/lookahead_scenario_site_node.csv` |
| 6.78 | `terminalLoh_wdro/output/stage2_damage_persistence_smoke/damage_persistence_by_slice.csv` |
| 5.14 | `terminalLoh_wdro/output/stage2_damage_persistence_v2/road_AC_stage_diagnostics_v2.csv` |

All are generated outputs and are excluded by directory-level rules. Required
CSV inputs under `data/` and configuration CSV files remain uploadable.

## Sensitive File Review

The scan checked filenames for `.env`, license, credential, password, token,
secret, certificate, and private-key indicators. It also scanned text-like files
up to 5 MB for private-key headers and common GitHub, OpenAI, AWS, password, and
token assignment patterns.

- Sensitive filename candidates found: none
- Sensitive content-pattern matches found: none
- `.env` files found: none
- Solver license files found: none
- Open-source repository `LICENSE` file found: none

This is a repository-preparation scan, not a substitute for a dedicated secret
scanner. Re-run a secret scan before making the repository public, and never add
local Gurobi licenses or account credentials.

## Duplicate, Backup, Cache, and Output Findings

- `terminalLoh_wdro (2).zip` is an obvious duplicate/archive backup name.
- The two 18.98 MB `terminal_loh_allocation_WDRO.csv` files under `output_h2/`
  and `terminalLoh_wdro/output/` are byte-for-byte identical.
- `data/.ipynb_checkpoints/` contains notebook checkpoint copies and is ignored.
- `terminalLoh_wdro/output/`: 120 files, approximately 199.87 MB.
- `output_h2/`: 115 files, approximately 53.15 MB.

These files were not deleted or moved; the new `.gitignore` only prevents them
from entering the initial repository history.

## Recommended Upload Scope

Upload:

- root MATLAB entry points and research scripts;
- `fa_h2/`;
- `terminalLoh_wdro/src/`, `config/`, `docs/`, and `checks/`;
- `data/`, except notebook checkpoint caches;
- `scripts/` and `utils/`;
- `codex_rule/`;
- root `README.md`, `AGENTS.md`, `.gitignore`, and `docs/baseline/`.

Ignore:

- `terminalLoh_wdro/output/`;
- `output_h2/`;
- archives and video files;
- MATLAB/Python/notebook caches and temporary files;
- local logs and scratch directories;
- `.env`, solver licenses, certificates, private keys, credential directories,
  and other local secrets.
