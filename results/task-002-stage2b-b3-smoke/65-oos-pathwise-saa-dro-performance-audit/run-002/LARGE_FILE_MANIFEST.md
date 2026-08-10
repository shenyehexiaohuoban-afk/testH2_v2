# LARGE_FILE_MANIFEST

| role | file | data rows | bytes | SHA-256 | Git policy |
|---|---|---:|---:|---|---|
| 10000-row paired master table | `pathwise_saa_dro_comparison.csv` | 10000 | 5114286 | `58336879de53ea1d216315af7c813c02944b1a0e9746246184ffecb519e9914b` | local-only if large |
| 6053-row terminal-hit input/output table | `terminal_hit_deltaT_deltaI.csv` | 6053 | 1234272 | `3e766f53e72dc4ae344810a46d0f294ed71be2b15324705c507ad38eacc6a3af` | lightweight result |
| top 10 percent inventory-gain paths | `high_inventory_gain_paths.csv` | 1000 | 180516 | `727d60ccbf09ada0d005c6f589daf38d516ca0c8169c82b141bf570a63fe766b` | lightweight result |

Frozen source: `C:\Users\chaos\Desktop\biye\test\testH2_v2\results\task-002-stage2b-b3-smoke\58-main-msp-terminal-gap-mechanism-audit\run-004\terminal_target_vs_final_inventory.csv`; 20000 rows; 4630799 bytes; SHA-256 `1d23404cf46629bc3db4f983b47fe2e5b1a2260d0379a792b1674b4681419165`; protected prior accepted result, not copied.
Frozen OOS: `output_h2/details/h2_OOS.csv`; SHA-256 `6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85`; protected input, not copied.
No MAT, workspace, cache, new scenario data, or solver output was created.
