NearStageMSPInput_v1 临灾 MSP 输入说明
============================================================

主要文件：
1. near_stage_msp_input.mat：临灾 MSP 程序推荐读取的主输入结构 NearStageInput。
2. near_stage_msp_site_input.csv：每个氢站的初始 LOH、容量、设备能力、正常氢负荷与基础目标 LOH。
3. near_stage_msp_normal_h2_hourly.csv：站点级 24 小时正常氢负荷，临灾 MSP 中应作为真实出库消耗。
4. near_stage_msp_normal_h2_stage_template.csv：按默认 6.0 小时阶段聚合的正常氢负荷模板。
5. near_stage_msp_critical_node_input.csv：节点关键负荷、折算需氢量 H_n，以及节点到氢站的服务权重 A_i,n。
6. near_stage_msp_beta_template.csv：beta(a,loc,lf) 默认模板；beta 是调拨风险/摩擦系数，不是吸收状态。

核心建模口径：
- x0_h2_kg 是远期结束时的储氢量，应作为临灾 MSP 初始状态。
- 正常氢负荷是真实消耗，应进入库存平衡。
- 灾害支援需求应建成目标 LOH/储氢准备需求，即 x_i,t + s_i,t >= R_i(k)，不要在灾前直接从库存扣除。
- beta(k)=beta(a,loc,lf) 表示 HTT 调拨风险/摩擦；beta 高可以使调拨成本升高、可用运力下降，但 beta 高不等于吸收。
- 建议 lf=8 解释为最终登陆/影响确定的终端吸收；a=1 解释为消散/无风险吸收。

推荐公式：
H_n = P_critical_n * support_hours / (eta_FC * LHV_H2)
R_i(k) = sum_n A_i,n * hazard_n(k) * H_n
sum_ij f_ij,t <= (1 - beta(k)) * N_HTT * Q_HTT
c_ij(k) = c_ij_base * (1 + lambda_beta * beta(k))

Stage1 road CSV additions for offline wind_mc / roadSoft preview
============================================================

7. stage1_road_edges.csv:
   Stage1 road graph topology. The offline preview uses from_node / to_node
   together with windMC.layout.nodes to calculate road-edge coordinates,
   midpoints, edge lengths, close probabilities, and shortest-path distances.

8. stage1_site_nodes.csv:
   H2 site road anchors. The current offline preview only uses site_id and
   grid_node. If x_km / y_km columns exist, they are ignored; H2 site
   coordinates come from windMC.layout.sites.

9. site_node_shortest_path_distance.csv:
   This file is generated under output_h2/wind_terminal_loh_preview/road/.
   It records the site-node shortest-path distances recomputed on the full
   road graph during the preview run. It is an output table, not an input.

Additional modeling notes
============================================================

- The stage1 road CSV files are currently used mainly by the offline
  TerminalLOH wind_mc / roadSoft preview. They do not directly enter MSP
  training.
- Electric-grid node and road-node coordinates come from windMC.layout.nodes.
  H2 site coordinates come from windMC.layout.sites.
- roadSoft allocation is a pre-deployment soft allocation used to estimate
  station-level TerminalLOH. It is not a post-disaster hard node assignment
  and not a vehicle routing model.
- Road-edge wind impact is used to estimate road close probability and
  reachability. If a future version uses a detailed real road network or
  recovery model, that detailed network should replace the current stage1
  abstract road network.
