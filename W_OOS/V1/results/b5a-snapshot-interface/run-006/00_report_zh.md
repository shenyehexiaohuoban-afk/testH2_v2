# W_OOS/V1-B5A Read-Only Electrical Snapshot Interface Smoke

本脚本只调用 B4C 的 `dispatch_snapshot`，没有实现 B5A dispatcher；snapshot 不推进时间、不扣 H2、不计算 EENS。

CASE-4 到站状态下，旧 interval 复现为 0.5h shed=0.0 kW，2.2833h shed=9.716058394159404 kW；snapshot bus23 当前 shed=0.0 kW。

nonbinding identity=PASS，no-mutation=PASS，idempotence=PASS（连续 10 次）。

最终门禁：
B5A_SNAPSHOT_INTERFACE_SMOKE=PASS；B3_REGRESSION=PASS；B4C_REGRESSION=PASS；B4D_REGRESSION=PASS；B4C_INTERVAL_SEMANTICS_CHANGED=NO；READY_TO_RESUME_B5A_MFCV_POLICY=YES。
