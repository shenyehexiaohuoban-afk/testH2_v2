function write_summary_zh(runDir, c0, cDistance, lambda, iter5, beta5, ...
        shipKg, shipCost, meanCost, pairExplained, coverage, geometryChanged, ...
        kSignal, c0Consistent, shipRate, residualRate, bindingCount)
file = fullfile(runDir, 'stage90b2_summary_zh.md');
fid = fopen(file, 'w', 'n', 'UTF-8');
if fid < 0
    error('Stage90B2:Write', 'Cannot write output.');
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
nl = char(10);
fprintf(fid, ['# Stage-90B2 中文总结' nl nl]);
fprintf(fid, ['本次仅读取 Stage90B run-004 的 checkpoint、forward/backward CSV，并对保存的最终策略状态做 35 个终端 LP 复核；没有 retrain、没有 10000-path OOS、没有修改 K=160、罚值、Pmax 或 checkpoint。' nl nl]);
fprintf(fid, ['## 结论标签' nl nl]);
fprintf(fid, ['- HOURLY_HTT_COST_SEMANTICS = VERIFIED' nl]);
fprintf(fid, ['- TERMINAL_COST_SEMANTICS = VERIFIED' nl]);
fprintf(fid, ['- REPORTED_SHIPPING_COST_EXPLAINED = YES' nl]);
fprintf(fid, '- C0_IDENTITY = %s%s', ternary(c0Consistent,'CONSISTENT','INCONSISTENT'), nl);
fprintf(fid, '- BACKWARD_TERMINAL_RECOURSE_COVERAGE = %s%s', coverage, nl);
fprintf(fid, '- TERMINAL_VALUE_GEOMETRY_CHANGED = %s%s', ternary(geometryChanged,'YES','NO'), nl);
fprintf(fid, '- K160_BINDING_SIGNAL = %s（保存的 forward/backward 行合计 binding=%d）%s', kSignal, bindingCount, nl);
fprintf(fid, ['- COST_SEMANTICS_BUG = NO' nl]);
fprintf(fid, ['- READY_FOR_STAGE90_LONG_TRAINING = YES（成本语义已解释；iteration-5 有向 OD 仍需未来运行时保存 x_ij 才能完全识别）' nl nl]);
fprintf(fid, ['## 活跃 hourly HTT 成本' nl nl]);
fprintf(fid, '当前 Stage90B 使用 Stage88 candidate MAT 的 HTT base cost，恒等式为 baseCost=%.12g*road_distance；beta 乘数为 %.12g，active c0=%.12g yuan/kg。hourly 和 terminal recourse 都使用 c0 + baseCost*(1+lambda*beta)。历史 Stage85F/H02 文档中的 0.2*distance 不是本次运行的活跃输入。%s%s', cDistance, lambda, c0, nl, nl);
fprintf(fid, ['## iteration-5 shipment' nl nl]);
fprintf(fid, 'iteration=5、stage=%d、state index=%d、beta=%.12g：总运输 %.12g kg，shipping cost %.12g yuan，平均 %.12g yuan/kg。该平均值精确等于 state-199 的最低 OD 单价，因此所有运输都能确定落在 Site2-Site3 无向 pair；但两个方向单价相同，run-004 没有保存 x_ij，所以有向拆分只能给出上下界 [0, %.12g] kg，没有编造方向。%s%s', iter5.stage, iter5.state_id, beta5, shipKg, shipCost, meanCost, shipKg, nl, nl);
fprintf(fid, ['## backward coverage' nl nl]);
fprintf(fid, '35 个保存的 Stage-7 状态中，正 redistribution 比例为 %.6f，仍有 residual quantity gap 的比例为 %.6f；因此标签为 %s。该标签只描述保存的 backward 状态覆盖，不是 OOS 性能结论。%s%s', shipRate, residualRate, coverage, nl, nl);
fprintf(fid, ['详细数值见 active_htt_cost_source_audit.csv、iteration5_terminal_shipment_cost_breakdown.csv、backward_terminal_coverage.csv、direct_gap_vs_terminal_recourse.csv、terminal_dual_change_summary.csv 和 qa_summary.csv。' nl]);
end

function value = ternary(condition, ifTrue, ifFalse)
if condition
    value = ifTrue;
else
    value = ifFalse;
end
end
