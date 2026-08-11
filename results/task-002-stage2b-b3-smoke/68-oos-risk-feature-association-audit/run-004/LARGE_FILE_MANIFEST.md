# LARGE_FILE_MANIFEST

The 10000-row unified analysis table is local-only because it exceeds the lightweight result range.

| generated file | rows/dimensions | bytes | SHA-256 | Git policy |
|---|---:|---:|---|---|
| `delta_i_bin_feature_summary.csv` | 161 data rows | 15773 | `ca9e1e6b24aed101badfbbc83e75b65a2887a1536ce1bd030838508c6ff69263` | lightweight Git candidate |
| `delta_i_bins.csv` | 7 data rows | 947 | `8592b08fed0e9c7014f69c16ec8337ccdbff477cda53730da764cc0790a2f152` | lightweight Git candidate |
| `fig1_delta_i_bin_independent_risk_boxplots.png` | PNG figure | 145548 | `a93272eb082819663211f3d10f2d215bfa6fd7eff5f171169ae685dd96daf55c` | lightweight Git candidate |
| `fig2_independent_risk_vs_delta_i_scatter.png` | PNG figure | 365686 | `76af3cc16c04b6cf030df9fa50294e8473f47932da85053740374666d37476a9` | lightweight Git candidate |
| `fig3_terminal_hit_delta_i_distribution.png` | PNG figure | 38075 | `a073f48f0351df7ceb83c69b0865601a49265cc93f71182df5cb1b68cd8794c0` | lightweight Git candidate |
| `fig4_preparation_stage_count_delta_i.png` | PNG figure | 52960 | `0cc4a5d7091b8254545242043bbe1f06930dcc39039186801f3f030c708e8ca9` | lightweight Git candidate |
| `fig5_terminal_state_frequency_and_delta_i.png` | PNG figure | 168884 | `4107dd28041045ecb53fc52c9dda34283e9a37490569044e1599bd05218fa9d7` | lightweight Git candidate |
| `focus_20_50_vs_low_delta_summary.csv` | 56 data rows | 7683 | `0a9ebaee3ab96cf0a41bde76c45f273cf74a5b23db5ad5995e378883a863cd1e` | lightweight Git candidate |
| `independent_mechanical_audit.txt` | text | 830 | `7ace2d3a2e0181b97a371648ba54bccb78bdb885c9ae0f31f22989e46bdc57ee` | lightweight Git candidate |
| `low_delta_risk_and_saa_surplus_diagnostic.csv` | 3 data rows | 831 | `d6417b7fd3d7673ec2d7d444e3a78467ec0a10e53e0f8154fba2f71939b0a843` | lightweight Git candidate |
| `pathwise_risk_feature_analysis_table.csv` | 10000 data rows | 6975494 | `66ba1d7ad593b44b292626ecf24261dae37f0bd28b937e47af0947c1b2fb47f0` | local-only |
| `preparation_stage_comparison.csv` | 18 data rows | 2441 | `feccd83009d462d7f5e754f19e08022889abc9ca350d56aeb6426df669a9a85f` | lightweight Git candidate |
| `README.md` | text | 1395 | `2ef08c52def3bdbf03034bed55894dfc029f6f1e7d35b2ad0c24a649e547cb50` | lightweight Git candidate |
| `risk_feature_definitions.csv` | 23 data rows | 2916 | `eff6473256d8b13bfc1290d91c8b25020070518b4fe313f33e69e976a3d41671` | lightweight Git candidate |
| `saa_shortage_group_comparison.csv` | 10 data rows | 1721 | `e8c4e4e57f7cd46d1a9e3bf795d51a62399416d499042a139c10c84a01dea463` | lightweight Git candidate |
| `spearman_correlations.csv` | 23 data rows | 3283 | `8cc892bae39a3e393eb5c379a12d80416a774b67bf185b086f8a2a8ff63adc3e` | lightweight Git candidate |
| `step05b11_judgment.txt` | text | 5039 | `da5f677a01cc81c5b528a5e4cf78949a5a982c1b5fc7b69d982319803d7b5bec` | lightweight Git candidate |
| `strategy_response_correlations.csv` | 4 data rows | 609 | `d9bb4892761dc5c2520255f933ff7364c394922e3831c28aac03a916eeafba05` | lightweight Git candidate |
| `terminal_hit_comparison.csv` | 10 data rows | 1645 | `b828b8565353f656aa31607c189f5e17796a072d3f6bcdcc0e409f7c26e2e6cc` | lightweight Git candidate |
| `terminal_state_summary.csv` | 31 data rows | 5329 | `8bed2fd686cfd9297c12c95a300ea55a27066d3bef1002ea5d0d9df712c01ac8` | lightweight Git candidate |

## Protected accepted inputs

| source | bytes | SHA-256 |
|---|---:|---|
| `C:\Users\chaos\Desktop\biye\test\testH2_v2\results\task-002-stage2b-b3-smoke\65-oos-pathwise-saa-dro-performance-audit\run-002\pathwise_saa_dro_comparison.csv` | 5114286 | `58336879de53ea1d216315af7c813c02944b1a0e9746246184ffecb519e9914b` |
| `C:\Users\chaos\Desktop\biye\test\testH2_v2\output_h2\details\h2_OOS.csv` | 267384 | `6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85` |
| `C:\Users\chaos\Desktop\biye\test\testH2_v2\results\task-002-stage2b-b3-smoke\60-terminal-loh-required-extra-and-flow-audit\run-002\path_station_abcd_classification.csv` | 6417548 | `070dbe1c4af028f6f658bb31c4daa72e21eee465b8c02e4bb477fc23d22b94a7` |
| `C:\Users\chaos\Desktop\biye\test\testH2_v2\results\task-002-stage2b-b3-smoke\53-35state-saa-vs-eta003-terminal-loh\run-024\terminal_loh_saa_vs_eta003_comparison.csv` | 37577 | `956a9f3b69a7e26b8ca1abe7355bf59cc467279f9527f09bfda8102bbe7f88d9` |

No MATLAB, Gurobi, MSP training, OOS resampling, W-stage recourse, or new scenario generation was performed.
