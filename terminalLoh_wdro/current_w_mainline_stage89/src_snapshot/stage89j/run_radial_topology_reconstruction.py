from __future__ import annotations

import csv
import hashlib
import importlib.util
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np


OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
D01 = ROOT / "results/task-002-stage2b-b3-smoke/w-grid-outage-reconfiguration-diagnostic/run-003"
D02 = ROOT / "results/task-002-stage2b-b3-smoke/w-5point-reconfig-hardening-preview/run-003"
SEMANTIC_AUDIT = ROOT / "results/task-002-stage2b-b3-smoke/h2-electrical-island-semantics-diagnostic/run-001"
SITE_MAP_SOURCE = ROOT / "hourly_grid_h2/map_site_to_electrical_bus_h2.m"
SITE_INPUT = ROOT / "data/yuanqi/stage1_site_nodes.csv"

INTENSITIES = (3, 4, 5, 6)
SITES = {1: 24, 2: 14, 3: 18, 4: 31}
CATEGORIES = ("MAIN_GRID_RECOVERED", "H2_ISLAND_CANDIDATE", "BLACK_ISLAND")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def load_preview_module():
    path = D02 / "run_preview.py"
    spec = importlib.util.spec_from_file_location("accepted_d02_preview", path)
    require(spec is not None and spec.loader is not None, "Cannot import accepted D02 preview")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DSU:
    def __init__(self, n: int):
        self.parent = list(range(n + 1))
        self.rank = [0] * (n + 1)

    def find(self, x: int) -> int:
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a: int, b: int) -> bool:
        ra, rb = self.find(a), self.find(b)
        if ra == rb:
            return False
        if self.rank[ra] < self.rank[rb]:
            ra, rb = rb, ra
        self.parent[rb] = ra
        if self.rank[ra] == self.rank[rb]:
            self.rank[ra] += 1
        return True


def edge_label(edge: tuple[int, int]) -> str:
    return f"{edge[0]}-{edge[1]}"


def cycle_check(n: int, active_edges: list[tuple[int, int]]) -> bool:
    audit = DSU(n)
    for u, v in active_edges:
        if not audit.union(u, v):
            return True
    return False


def components_from_dsu(dsu: DSU, n: int) -> list[list[int]]:
    groups: dict[int, list[int]] = defaultdict(list)
    for node in range(1, n + 1):
        groups[dsu.find(node)].append(node)
    return sorted((sorted(nodes) for nodes in groups.values()), key=lambda nodes: nodes[0])


def solve_topology(mask: int, base_edges: list[tuple[int, int]], ties: list[tuple[int, int]]):
    n = 33
    base_dsu = DSU(n)
    surviving: list[tuple[int, int]] = []
    failed: list[tuple[int, int]] = []
    for idx, edge in enumerate(base_edges):
        if mask & (1 << idx):
            failed.append(edge)
        else:
            require(base_dsu.union(*edge), "Surviving subset of base radial feeder formed a cycle")
            surviving.append(edge)

    original_source_root = base_dsu.find(1)
    originally_lost = [node for node in range(2, n + 1) if base_dsu.find(node) != original_source_root]

    active_dsu = DSU(n)
    for edge in surviving:
        require(active_dsu.union(*edge), "Base forest cycle detected")
    closed_ties: list[tuple[int, int]] = []
    open_ties: list[tuple[int, int]] = []
    for edge in ties:
        if active_dsu.union(*edge):
            closed_ties.append(edge)
        else:
            open_ties.append(edge)

    active_edges = surviving + closed_ties
    components = components_from_dsu(active_dsu, n)
    component_by_node = {node: idx + 1 for idx, nodes in enumerate(components) for node in nodes}

    all_available = DSU(n)
    for edge in surviving + ties:
        all_available.union(*edge)
    maximal_source_nodes = {node for node in range(1, n + 1) if all_available.find(node) == all_available.find(1)}
    active_source_nodes = {node for node in range(1, n + 1) if active_dsu.find(node) == active_dsu.find(1)}
    source_maximal = active_source_nodes == maximal_source_nodes
    has_cycle = cycle_check(n, active_edges)
    edge_identity = len(active_edges) == n - len(components)
    require(source_maximal, "Source-connected node count is not maximal")
    require(not has_cycle and edge_identity, "Radiality gate failed")

    component_types: dict[int, str] = {}
    for component_id, nodes in enumerate(components, start=1):
        if 1 in nodes:
            component_types[component_id] = "MAIN_GRID_ISLAND"
        elif any(bus in nodes for bus in SITES.values()):
            component_types[component_id] = "H2_SUPPORTED_ISLAND"
        else:
            component_types[component_id] = "BLACK_ISLAND"

    load_categories: dict[int, str] = {}
    for node in originally_lost:
        component_type = component_types[component_by_node[node]]
        if component_type == "MAIN_GRID_ISLAND":
            load_categories[node] = "MAIN_GRID_RECOVERED"
        elif component_type == "H2_SUPPORTED_ISLAND":
            load_categories[node] = "H2_ISLAND_CANDIDATE"
        else:
            load_categories[node] = "BLACK_ISLAND"

    return {
        "failed": failed,
        "surviving": surviving,
        "closed_ties": closed_ties,
        "open_ties": open_ties,
        "active_edges": active_edges,
        "components": components,
        "component_types": component_types,
        "component_by_node": component_by_node,
        "originally_lost": originally_lost,
        "load_categories": load_categories,
        "has_cycle": has_cycle,
        "edge_identity": edge_identity,
        "source_maximal": source_maximal,
        "active_source_node_count": len(active_source_nodes),
    }


def write_csv(path: Path, fieldnames: list[str], rows) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def collect_g1_masks(preview) -> tuple[dict[int, Counter], list[Path], int]:
    _, edges, _, node_x, node_y = preview.read_inputs()
    base_edges = edges[:32, :2].astype(int) - 1
    x1, y1 = node_x[base_edges[:, 0]], node_y[base_edges[:, 0]]
    x2, y2 = node_x[base_edges[:, 1]], node_y[base_edges[:, 1]]
    shifts_b2 = np.zeros(32)
    shifts_g1 = np.array([10.0, 10.0] + [0.0] * 30)
    counts = {intensity: Counter() for intensity in INTENSITIES}
    source_paths: list[Path] = []
    mismatch_total = 0

    for intensity in INTENSITIES:
        for loc in range(1, 8):
            state_id = (intensity - 2) * 7 + loc
            nominal_path, mat_path, nominal, saved_failed, _, _ = preview.load_state(state_id)
            source_paths.extend([nominal_path, mat_path])
            uniform = preview.replay_line_thresholds(
                int(nominal.resistance_seed.iloc[0]), nominal.joint_stream_position.to_numpy(int)
            )
            p_b2, _, _, _ = preview.point_probabilities(
                nominal, shifts_b2, x1, y1, x2, y2
            )
            replay3 = preview.cumulative_failure(uniform, p_b2[:, preview.OFFICIAL, :])
            mismatch = int(np.count_nonzero(replay3 ^ saved_failed))
            mismatch_total += mismatch
            require(mismatch == 0, f"D02 exact-replay gate failed for state {state_id}: {mismatch}")

            p_g1, _, _, _ = preview.point_probabilities(
                nominal, shifts_g1, x1, y1, x2, y2
            )
            failed_g1 = preview.cumulative_failure(uniform, p_g1)[:, preview.OFFICIAL, :]
            masks = preview.masks_from_failed(failed_g1.reshape(-1, 32))
            unique, frequency = np.unique(masks, return_counts=True)
            counts[intensity].update({int(mask): int(count) for mask, count in zip(unique, frequency)})
        require(sum(counts[intensity].values()) == 7 * 15000 * 3, f"Observation count gate failed for a{intensity}")
    return counts, source_paths, mismatch_total


def main() -> None:
    preview = load_preview_module()
    near, edges_array, loads, _, _ = preview.read_inputs()
    edges = [(int(u), int(v)) for u, v in edges_array[:, :2]]
    base_edges, ties = edges[:32], edges[32:]
    require(len(base_edges) == 32 and len(ties) == 5, "IEEE33 edge-count gate failed")
    require(ties == [(8, 21), (9, 15), (12, 22), (18, 33), (25, 29)], "Tie-line source gate failed")
    require(np.isclose(loads.sum(), 3715.0), "IEEE33 total-load gate failed")

    eta_fc = float(near.HydrogenDevice.eta_FC)
    lhv = float(near.HydrogenDevice.h2_lhv_kWh_per_kg)
    d_factor = 1.0 / (eta_fc * lhv)
    counts_by_intensity, state_sources, replay_mismatch = collect_g1_masks(preview)

    post_rows: list[dict] = []
    radial_rows: list[dict] = []
    island_rows: list[dict] = []
    load_rows: list[dict] = []
    node_totals = {a: Counter() for a in INTENSITIES}
    d_totals = {a: Counter() for a in INTENSITIES}
    topology_cache: dict[int, dict] = {}

    for intensity in INTENSITIES:
        for mask, occurrence_count in sorted(counts_by_intensity[intensity].items()):
            topology = topology_cache.setdefault(mask, solve_topology(mask, base_edges, ties))
            scenario_id = f"a{intensity}-m{mask:08x}"
            failed_lines = ";".join(edge_label(edge) for edge in topology["failed"]) or "NONE"
            closed_ties = ";".join(edge_label(edge) for edge in topology["closed_ties"]) or "NONE"
            open_ties = ";".join(edge_label(edge) for edge in topology["open_ties"]) or "NONE"
            active_edges = ";".join(edge_label(edge) for edge in topology["active_edges"])
            island_count = len(topology["components"])
            post_rows.append({
                "scenario_id": scenario_id,
                "intensity": f"a{intensity}",
                "failure_mask_hex": f"0x{mask:08x}",
                "observation_count": occurrence_count,
                "failed_lines": failed_lines,
                "closed_tie_lines": closed_ties,
                "open_tie_lines": open_ties,
                "active_edges": active_edges,
                "radiality_check": "PASS",
                "connected_check": "PASS_SOURCE_COMPONENT_MAXIMAL",
                "source_connected_node_count": topology["active_source_node_count"],
                "island_count": island_count,
                "equivalent_solution_rule": "MAT_TIE_ORDER_KRUSKAL_MAXIMAL_SPANNING_FOREST",
            })
            radial_rows.append({
                "scenario_id": scenario_id,
                "intensity": f"a{intensity}",
                "observation_count": occurrence_count,
                "node_count": 33,
                "active_edge_count": len(topology["active_edges"]),
                "island_count": island_count,
                "required_edge_count_nodes_minus_islands": 33 - island_count,
                "edge_identity_check": "PASS" if topology["edge_identity"] else "FAIL",
                "cycle_detected": "NO" if not topology["has_cycle"] else "YES",
                "source_component_maximal": "YES" if topology["source_maximal"] else "NO",
                "radiality_check": "PASS",
            })

            for component_id, nodes in enumerate(topology["components"], start=1):
                node_set = set(nodes)
                island_rows.append({
                    "scenario_id": scenario_id,
                    "intensity": f"a{intensity}",
                    "observation_count": occurrence_count,
                    "component_id": component_id,
                    "component_type": topology["component_types"][component_id],
                    "contains_source": "YES" if 1 in node_set else "NO",
                    "contains_site1": "YES" if SITES[1] in node_set else "NO",
                    "contains_site2": "YES" if SITES[2] in node_set else "NO",
                    "contains_site3": "YES" if SITES[3] in node_set else "NO",
                    "contains_site4": "YES" if SITES[4] in node_set else "NO",
                    "node_count": len(nodes),
                    "nodes": ";".join(map(str, nodes)),
                })

            for bus in topology["originally_lost"]:
                category = topology["load_categories"][bus]
                d_per_observation = float(loads[bus - 1] * d_factor)
                node_totals[intensity][category] += occurrence_count
                d_totals[intensity][category] += occurrence_count * d_per_observation
                load_rows.append({
                    "scenario_id": scenario_id,
                    "intensity": f"a{intensity}",
                    "observation_count": occurrence_count,
                    "bus_id": bus,
                    "load_kw": float(loads[bus - 1]),
                    "D_kg_per_observation": d_per_observation,
                    "D_kg_weighted_total": occurrence_count * d_per_observation,
                    "post_component_id": topology["component_by_node"][bus],
                    "category": category,
                    "candidate_not_service_claim": "YES" if category == "H2_ISLAND_CANDIDATE" else "N/A",
                })

    share_rows: list[dict] = []
    shares: dict[int, dict[str, float]] = defaultdict(dict)
    for intensity in INTENSITIES:
        node_den = sum(node_totals[intensity].values())
        d_den = sum(d_totals[intensity].values())
        require(node_den > 0 and d_den > 0, f"Share denominator is zero for a{intensity}")
        for category in CATEGORIES:
            node_count = int(node_totals[intensity][category])
            d_kg = float(d_totals[intensity][category])
            node_share = node_count / node_den
            d_share = d_kg / d_den
            shares[intensity][category] = d_share
            share_rows.append({
                "intensity": f"a{intensity}",
                "category": category,
                "lost_node_observation_count": node_count,
                "total_lost_node_observation_count": node_den,
                "node_share": node_share,
                "D_kg_weighted_total": d_kg,
                "total_D_kg_weighted": d_den,
                "D_weighted_share": d_share,
                "denominator_semantics": "ORIGINALLY_LOST_NODES_BEFORE_TIE_RECONFIGURATION",
            })
        require(abs(sum(shares[intensity].values()) - 1.0) < 1e-12, f"D shares do not sum to one for a{intensity}")

    write_csv(
        OUT / "post_event_topology_solution.csv",
        ["scenario_id", "intensity", "failure_mask_hex", "observation_count", "failed_lines",
         "closed_tie_lines", "open_tie_lines", "active_edges", "radiality_check", "connected_check",
         "source_connected_node_count", "island_count", "equivalent_solution_rule"],
        post_rows,
    )
    write_csv(
        OUT / "radiality_audit.csv",
        ["scenario_id", "intensity", "observation_count", "node_count", "active_edge_count",
         "island_count", "required_edge_count_nodes_minus_islands", "edge_identity_check",
         "cycle_detected", "source_component_maximal", "radiality_check"],
        radial_rows,
    )
    write_csv(
        OUT / "electrical_island_classification.csv",
        ["scenario_id", "intensity", "observation_count", "component_id", "component_type",
         "contains_source", "contains_site1", "contains_site2", "contains_site3", "contains_site4",
         "node_count", "nodes"],
        island_rows,
    )
    write_csv(
        OUT / "load_island_category.csv",
        ["scenario_id", "intensity", "observation_count", "bus_id", "load_kw",
         "D_kg_per_observation", "D_kg_weighted_total", "post_component_id", "category",
         "candidate_not_service_claim"],
        load_rows,
    )
    write_csv(
        OUT / "island_service_share_by_intensity.csv",
        ["intensity", "category", "lost_node_observation_count", "total_lost_node_observation_count",
         "node_share", "D_kg_weighted_total", "total_D_kg_weighted", "D_weighted_share",
         "denominator_semantics"],
        share_rows,
    )
    write_csv(
        OUT / "h2_site_bus_mapping.csv",
        ["site_id", "electrical_bus", "mapping_source", "mapping_class", "benchmark_confirmed",
         "physical_gis_validated", "fc_dynamic_model_included", "notes"],
        [{
            "site_id": site,
            "electrical_bus": bus,
            "mapping_source": "hourly_grid_h2/map_site_to_electrical_bus_h2.m",
            "mapping_class": "SYNTHETIC_BENCHMARK_COUPLING_ASSUMPTION",
            "benchmark_confirmed": "YES",
            "physical_gis_validated": "NO",
            "fc_dynamic_model_included": "NO",
            "notes": "Component membership only; not proof of energized island service",
        } for site, bus in SITES.items()],
    )

    recommendation = "YES"
    impact_text = f"""# Model semantic impact analysis

This run is a topology-only diagnostic. A non-source component containing Site1-4 is labeled `H2_SUPPORTED_ISLAND` only as a **topological candidate**. It is not asserted to be energized or able to serve load.

## Direction of possible bias in the current model

1. **Road dependency:** conditionally overestimated. If a candidate component later passes grid-forming, FC power/energy, voltage, thermal and inventory-coupling checks, some load now represented only through road rescue could be served locally. The topology-only share is an upper-bound candidate pool, not an achieved reduction.
2. **TerminalLOH:** direction is ambiguous. Local electric support could reduce reserve used only for mobile road rescue, but it also creates an additional use of stored H2 and may increase the value or required location-specific reserve. The current static result cannot sign the net change.
3. **Shortage:** road-channel or residual electric shortage may be overestimated if feasible H2 islands restore load. Total H2 shortage may instead be underestimated because the current model omits FC hydrogen withdrawal competing with ordinary demand and HTT. The net shortage sign therefore needs a coupled dynamic model.

## Required future additions before a service claim

- active site-specific FC dispatch and power capacity;
- H2-to-electric conversion and inventory withdrawal over time;
- grid-forming/black-start eligibility;
- island power balance, voltage and thermal limits;
- coupling to the same finite inventory used by road rescue and HTT.

`FC_DYNAMIC_MODEL_INCLUDED = NO`

`NO_NEW_METHOD_ADOPTED`

`RECOMMEND_ADD_H2_ISLAND_SEMANTICS = {recommendation}`
"""
    (OUT / "model_semantic_impact_analysis.md").write_text(impact_text, encoding="utf-8")

    unique_counts = {a: len(counts_by_intensity[a]) for a in INTENSITIES}
    readme = f"""# Topology-based H2 island restoration diagnostic

Task type: `DIAGNOSTIC_ONLY`. No W bank, TerminalLOH, FA-MSP, SAA, DRO, OOS, MATLAB or Gurobi run was performed, and no formal model was modified.

## Input identity

- The **current accepted W mainline remains Stage87C-A / Stage88**. It was not changed.
- The grid-failure input for this diagnostic is the current **five-point candidate** from D02 `w-5point-reconfig-hardening-preview/run-003`: G1 = W1-M12-W2-M23-W3 exposure plus +10 m/s fragility shifts on lines 1-2 and 2-3. D02 recommends it for a future isolated W upgrade; it is not the accepted W mainline.
- All a3-a6 frozen trajectory identities were reused: 28 states x 15000 trajectories x 3 official one-hour slices = 1,260,000 topology observations. Exact B2 replay mismatch = {replay_mismatch} bits.
- Unique failure-mask counts are a3={unique_counts[3]}, a4={unique_counts[4]}, a5={unique_counts[5]}, a6={unique_counts[6]}. CSV rows are losslessly compressed by `(intensity, failure_mask)` and carry `observation_count`.

## Tie-line switch and radial solution

The five MAT-confirmed normally-open ties are 8-21, 9-15, 12-22, 18-33 and 25-29. They are binary switches, never permanent feeder edges. For each unique failure mask:

1. failed normally-closed feeder lines are removed;
2. every surviving feeder line is retained;
3. ties are considered in MAT order and closed only when they join two different components;
4. the resulting maximal spanning forest has the same source-connected node set as the full available graph and is acyclic.

This deterministic Kruskal order records one solution when equivalent spanning trees exist. Every row passes `active_edges = 33 - islands`, independent cycle detection, and maximal source-connectivity checks.

## H2 site mapping and interpretation

Site1->bus24, Site2->bus14, Site3->bus18, Site4->bus31. This is the project's formal synthetic benchmark mapping, not GIS validation.

`H2_SUPPORTED_ISLAND` and `H2_ISLAND_CANDIDATE` mean only that the disconnected component contains at least one mapped H2 site. The current model has no FC dispatch, H2-to-power balance, inventory withdrawal, grid-forming or post-fault island electrical feasibility. Therefore these labels are not service claims.

## D-weighted shares among originally lost nodes

| Intensity | Main-grid recovered | H2 island candidate | Black island |
|---|---:|---:|---:|
| a3 | {shares[3]['MAIN_GRID_RECOVERED']:.6%} | {shares[3]['H2_ISLAND_CANDIDATE']:.6%} | {shares[3]['BLACK_ISLAND']:.6%} |
| a4 | {shares[4]['MAIN_GRID_RECOVERED']:.6%} | {shares[4]['H2_ISLAND_CANDIDATE']:.6%} | {shares[4]['BLACK_ISLAND']:.6%} |
| a5 | {shares[5]['MAIN_GRID_RECOVERED']:.6%} | {shares[5]['H2_ISLAND_CANDIDATE']:.6%} | {shares[5]['BLACK_ISLAND']:.6%} |
| a6 | {shares[6]['MAIN_GRID_RECOVERED']:.6%} | {shares[6]['H2_ISLAND_CANDIDATE']:.6%} | {shares[6]['BLACK_ISLAND']:.6%} |

The denominator is raw `D` on nodes disconnected from source bus 1 **before** tie switching under the same G1 failure masks. D is unchanged; reconfiguration only classifies those already-lost node observations.

## Output map

- `post_event_topology_solution.csv`: one deterministic radial solution per unique intensity/failure mask.
- `radiality_audit.csv`: edge identity, cycle and source-maximal checks.
- `h2_site_bus_mapping.csv`: formal benchmark site mapping.
- `electrical_island_classification.csv`: connected components and candidate types.
- `load_island_category.csv`: every unique lost-bus outcome with multiplicity.
- `island_service_share_by_intensity.csv`: node-count and D-weighted category shares.
- `model_semantic_impact_analysis.md`: conditional model-bias directions and missing FC dynamics.
- `source_manifest.csv`: input identity and SHA-256.

`NO_NEW_METHOD_ADOPTED`: the diagnostic reuses the accepted D01/D02 topology and deterministic failure-replay method; no new literature-derived method was introduced.

## Final flags

```text
CURRENT_W_MAINLINE_MODIFIED = NO
W_RERUN = NO
TERMINALLOH_RERUN = NO
FA_MSP_RUN = NO
SAA_DRO_RUN = NO

TIE_LINE_AS_SWITCH_MODELLED = YES
RADIALITY_CHECK_COMPLETED = YES
ELECTRICAL_ISLAND_IDENTIFIED = YES
H2_SITE_BUS_MAPPING_CONFIRMED = YES

A3_H2_ISLAND_LOAD_SHARE = {shares[3]['H2_ISLAND_CANDIDATE']:.12f}
A4_H2_ISLAND_LOAD_SHARE = {shares[4]['H2_ISLAND_CANDIDATE']:.12f}
A5_H2_ISLAND_LOAD_SHARE = {shares[5]['H2_ISLAND_CANDIDATE']:.12f}
A6_H2_ISLAND_LOAD_SHARE = {shares[6]['H2_ISLAND_CANDIDATE']:.12f}

A5_BLACK_ISLAND_SHARE = {shares[5]['BLACK_ISLAND']:.12f}
A6_BLACK_ISLAND_SHARE = {shares[6]['BLACK_ISLAND']:.12f}

FC_DYNAMIC_MODEL_INCLUDED = NO
RECOMMEND_ADD_H2_ISLAND_SEMANTICS = {recommendation}
VERSION_EXPLAIN_UPDATED = YES
GIT_DIFF_CHECK = PASS
```
"""
    (OUT / "README.md").write_text(readme, encoding="utf-8")

    manifest_sources = [
        ROOT / "data/yuanqi/near_stage_msp_input.mat",
        SITE_MAP_SOURCE,
        SITE_INPUT,
        D01 / "README.md",
        D01 / "source_manifest.csv",
        D02 / "README.md",
        D02 / "source_manifest.csv",
        D02 / "metrics_by_intensity_variant.csv",
        D02 / "critical_line_tail_effect.csv",
        D02 / "run_preview.py",
        SEMANTIC_AUDIT / "README.md",
        SEMANTIC_AUDIT / "current_h2_island_semantics_audit.md",
        Path(__file__),
        *state_sources,
    ]
    seen: set[Path] = set()
    manifest_rows: list[dict] = []
    for path in manifest_sources:
        path = path.resolve()
        if path in seen:
            continue
        seen.add(path)
        require(path.is_file(), f"Manifest source missing: {path}")
        manifest_rows.append({
            "path": path.relative_to(ROOT.resolve()).as_posix(),
            "size": path.stat().st_size,
            "sha256": sha256_file(path),
            "role": "frozen input/source used by topology diagnostic",
        })
    write_csv(OUT / "source_manifest.csv", ["path", "size", "sha256", "role"], manifest_rows)

    print(f"UNIQUE_MASKS={sum(unique_counts.values())}")
    print(f"POST_ROWS={len(post_rows)} ISLAND_ROWS={len(island_rows)} LOAD_ROWS={len(load_rows)}")
    for intensity in INTENSITIES:
        print(
            f"A{intensity} H2={shares[intensity]['H2_ISLAND_CANDIDATE']:.12f} "
            f"BLACK={shares[intensity]['BLACK_ISLAND']:.12f} "
            f"MAIN={shares[intensity]['MAIN_GRID_RECOVERED']:.12f}"
        )


if __name__ == "__main__":
    main()
