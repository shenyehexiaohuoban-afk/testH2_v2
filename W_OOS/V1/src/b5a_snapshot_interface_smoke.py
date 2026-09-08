"""B5A read-only electrical snapshot interface smoke.

This runner exercises the B4C ``dispatch_snapshot`` API and keeps all
state-changing interval calls on private copies.  It is deliberately a
standalone audit: no dispatcher, policy, MATLAB job, or Git write is started.
"""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import inspect
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[2]
RESULT_ROOT = ROOT / "W_OOS/V1/results/b5a-snapshot-interface"
sys.path.insert(0, str(SRC))
import b4_event_driven_restoration_smoke as b4c  # noqa: E402


TOL = b4c.TOL
ARRIVAL = 1.2166666666667
CASE4_MASK = (1 << 21) | (1 << 22)
DEFAULT_DT_LONG = 2.2833333333333


def _json_default(value):
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, (np.floating, np.integer)):
        return value.item()
    raise TypeError(type(value).__name__)


def write_json(out: Path, name: str, value) -> None:
    (out / name).write_text(
        json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False,
                   default=_json_default) + "\n",
        encoding="utf-8",
    )


def write_csv(out: Path, name: str, rows) -> None:
    rows = list(rows)
    if not rows:
        raise ValueError("Cannot serialize empty snapshot artifact: " + name)
    fields = []
    for row in rows:
        for key in row:
            if key not in fields:
                fields.append(key)
    with (out / name).open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def process_status():
    command = (
        "@(Get-CimInstance Win32_Process | Where-Object "
        "{$_.Name -match 'matlab|gurobi'} | Select-Object ProcessId,Name) "
        "| ConvertTo-Json -Compress"
    )
    try:
        raw = subprocess.check_output(
            ["powershell", "-NoProfile", "-Command", command], text=True
        )
        return json.loads(raw) if raw.strip() else []
    except Exception as exc:  # pragma: no cover - diagnostics only
        return {"error": str(exc)}


def git_precheck():
    status_raw = subprocess.check_output(
        ["git", "status", "--porcelain=v1"], cwd=ROOT, text=True
    )
    status = status_raw.rstrip("\r\n").splitlines()
    staged = [line for line in status if line[:1] != " " and line[:2] != "??"]
    tracked_dirty = [line for line in status if line[:2] != "??"]
    untracked = [line for line in status if line[:2] == "??"]
    upstream = subprocess.check_output(
        ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
        cwd=ROOT, text=True,
    ).strip()
    ahead, behind = subprocess.check_output(
        ["git", "rev-list", "--left-right", "--count", "HEAD..." + upstream],
        cwd=ROOT, text=True,
    ).split()
    return {
        "branch": subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip(),
        "HEAD": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "upstream": upstream,
        "ahead": int(ahead),
        "behind": int(behind),
        "staged_files": staged,
        "tracked_dirty_files": tracked_dirty,
        "untracked_status_entries": untracked,
        "tracked_dirty_count": len(tracked_dirty),
        "untracked_status_entry_count": len(untracked),
        "processes": process_status(),
    }


def _canonical(value):
    """Stable representation for nested state before/after mutation checks."""
    if isinstance(value, np.ndarray):
        return {"__ndarray__": value.tolist(), "dtype": str(value.dtype), "shape": list(value.shape)}
    if isinstance(value, dict):
        return {str(k): _canonical(v) for k, v in sorted(value.items(), key=lambda pair: str(pair[0]))}
    if isinstance(value, (list, tuple)):
        return [_canonical(v) for v in value]
    if isinstance(value, (np.floating, np.integer)):
        return value.item()
    return value


def state_digest(station, vehicles, htt_vehicles):
    payload = _canonical({"station": station, "vehicles": vehicles, "htt": htt_vehicles})
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False, default=_json_default).encode()).hexdigest()


def _case4_vehicle(onboard=10.0, state="SERVICE", bus=23, moving=False):
    return {
        "vehicle_id": 1,
        "bus": bus,
        "arrival": ARRIVAL,
        "departure": 3.5,
        "onboard_H2_kg": float(onboard),
        "state": state,
        "moving": bool(moving),
        # Extra state fields ensure the no-mutation audit covers dispatcher inputs.
        "destination": 23,
        "route_progress": 0.0,
    }


def _all_case4_vehicles(primary):
    _, onboard, _ = b4c.initial_inventory()
    values = []
    for vehicle_id, bus in enumerate([23, 24, 14, 18, 31, 31], start=1):
        if vehicle_id == 1:
            values.append(copy.deepcopy(primary))
        else:
            values.append({
                "vehicle_id": vehicle_id, "bus": bus, "arrival": 0.0,
                "departure": 3.5, "onboard_H2_kg": float(onboard[vehicle_id - 1]),
                "state": "PARKED", "moving": False,
                "destination": bus, "route_progress": 0.0,
            })
    return values


def _bus23(result):
    return next(row for row in result["bus_rows"] if int(row["bus"]) == 23)


def _component23(result):
    component_id = _bus23(result)["component_id"]
    return next(row for row in result["component_rows"] if int(row["component_id"]) == int(component_id))


def _source(result, resource_id):
    return next(row for row in result["sources"] if row["resource_id"] == resource_id)


def _numeric_equal(a, b, tol=1e-8):
    try:
        return abs(float(a) - float(b)) <= tol
    except (TypeError, ValueError):
        return a == b


def _compare_results(left, right):
    """Compare the physical snapshot and interval fields relevant to identity."""
    if left.get("active") != right.get("active") or left.get("islands") != right.get("islands"):
        return False, "topology"
    fields = ["status", "from_bus", "to_bus", "P_flow_kW", "Q_flow_kvar"]
    branch_left = {int(row["branch_id"]): row for row in left["branch_rows"]}
    branch_right = {int(row["branch_id"]): row for row in right["branch_rows"]}
    if set(branch_left) != set(branch_right):
        return False, "branch_id_set"
    for branch_id in branch_left:
        for field in fields:
            if field == "status":
                if branch_left[branch_id].get(field) != branch_right[branch_id].get(field):
                    return False, "branch_%s" % field
            elif not _numeric_equal(branch_left[branch_id].get(field), branch_right[branch_id].get(field), 1e-7):
                return False, "branch_%s" % field
    for key in ("bus_rows", "component_rows", "roots"):
        if len(left.get(key, [])) != len(right.get(key, [])):
            return False, key + "_length"
    for a, b in zip(left["bus_rows"], right["bus_rows"]):
        if int(a["bus"]) != int(b["bus"]):
            return False, "bus_id"
        for field in ("P_served_kW", "Q_served_kvar", "P_shed_kW", "Q_shed_kvar", "voltage_pu"):
            if not _numeric_equal(a[field], b[field], 1e-7):
                return False, "bus_%s" % field
    # Snapshot ``sources`` deliberately includes unavailable FC/MFCV/HTT rows;
    # the shared solver rows are exposed as ``source_dispatch``.  Compare those
    # rows to the interval solver's complete source list by resource id.
    left_sources = left.get("source_dispatch", left.get("sources", []))
    right_sources = right.get("source_dispatch", right.get("sources", []))
    left_by_id = {row["resource_id"]: row for row in left_sources}
    right_by_id = {row["resource_id"]: row for row in right_sources}
    if set(left_by_id) != set(right_by_id):
        return False, "source_id_set"
    for resource_id in sorted(left_by_id):
        a = left_by_id[resource_id]
        b = right_by_id[resource_id]
        for field in ("actual_P_kW", "actual_Q_kvar"):
            if not _numeric_equal(a[field], b[field], 1e-7):
                return False, "source_%s" % field
    for a, b in zip(left["component_rows"], right["component_rows"]):
        for field in ("total_P_served_kW", "total_Q_served_kvar", "total_P_shed_kW", "total_Q_shed_kvar"):
            if not _numeric_equal(a[field], b[field], 1e-7):
                return False, "component_%s" % field
    return True, ""


def _contains_key(value, key):
    if isinstance(value, dict):
        return key in value or any(_contains_key(item, key) for item in value.values())
    if isinstance(value, (list, tuple)):
        return any(_contains_key(item, key) for item in value)
    return False


def _run_interval_copy(mask, start, end, vehicles, station):
    local_station = np.asarray(station, dtype=float).copy()
    local_vehicles = copy.deepcopy(vehicles)
    result = b4c.dispatch_interval(mask, start, end, local_vehicles, local_station)
    return result, local_station, local_vehicles


def _snapshot_copy(mask, current_time, vehicles, station, htt=None):
    local_station = np.asarray(station, dtype=float).copy()
    local_vehicles = copy.deepcopy(vehicles)
    local_htt = copy.deepcopy(htt or [])
    result = b4c.dispatch_snapshot(mask, current_time, local_vehicles, local_station, local_htt)
    return result, local_station, local_vehicles, local_htt


def _regression_summary(args):
    entries = {}
    for name, path, key in (
        ("B3", args.b3_run, "B3_PHYSICS_ENGINE_SMOKE"),
        ("B4C", args.b4c_run, "B4C_FORENSIC_AUDIT"),
        ("B4D", args.b4d_run, "B4D_HTT_GIVEN_ACTION_PHYSICS_SMOKE"),
    ):
        if not path:
            entries[name] = {"status": "NOT_SUPPLIED", "current_rerun": "NOT_RUN"}
            continue
        root = ROOT / path
        candidates = [root / "physics_QA.json", root / "final_summary.json"]
        source = next((candidate for candidate in candidates if candidate.is_file()), None)
        if source is None:
            entries[name] = {"status": "MISSING", "source": str(path)}
            continue
        data = json.loads(source.read_text(encoding="utf-8"))
        status = data.get(key)
        entries[name] = {
            "status": status if status is not None else "KEY_NOT_FOUND",
            "source": str(source.relative_to(ROOT)).replace("\\", "/"),
            "sha256": sha256(source),
            "current_rerun": "NOT_RUN_BY_SNAPSHOT_SMOKE",
        }
    baseline = ROOT / args.b4c_baseline_run
    candidate = ROOT / args.b4c_run if args.b4c_run else None
    names = sorted(
        {path.name for path in baseline.iterdir() if path.is_file()}
        | ({path.name for path in candidate.iterdir() if path.is_file()}
           if candidate is not None and candidate.is_dir() else set())
    ) if baseline.is_dir() else []
    file_identity = []
    for name in names:
        baseline_file = baseline / name
        candidate_file = candidate / name if candidate is not None else None
        baseline_hash = sha256(baseline_file) if baseline_file.is_file() else ""
        candidate_hash = (
            sha256(candidate_file)
            if candidate_file is not None and candidate_file.is_file() else ""
        )
        if not baseline_hash:
            status = "MISSING_BASELINE"
        elif not candidate_hash:
            status = "MISSING_CANDIDATE"
        else:
            status = "IDENTICAL" if baseline_hash == candidate_hash else "DIFFERENT"
        file_identity.append({
            "file": name,
            "baseline_sha256": baseline_hash,
            "candidate_sha256": candidate_hash,
            "status": status,
        })
    identity_pass = bool(file_identity) and all(
        row["status"] == "IDENTICAL" for row in file_identity
    )
    entries["B4C"]["historical_artifact_identity"] = {
        "status": "PASS" if identity_pass else "FAIL",
        "baseline": str(baseline.relative_to(ROOT)).replace("\\", "/"),
        "candidate": (
            str(candidate.relative_to(ROOT)).replace("\\", "/")
            if candidate is not None else "NOT_SUPPLIED"
        ),
        "checked_file_count": len(file_identity),
        "identical_file_count": sum(
            row["status"] == "IDENTICAL" for row in file_identity
        ),
        "files": file_identity,
    }
    return entries


def run(args):
    out = RESULT_ROOT / args.run
    if out.exists():
        raise FileExistsError("Refusing to overwrite existing snapshot run: " + str(out))
    precheck = git_precheck()
    out.mkdir(parents=True, exist_ok=False)
    # Persist the mechanical starting point before any solver call.  The final
    # summary repeats the HEAD; this file is intentionally an early snapshot.
    write_json(out, "precheck.json", precheck)

    station, onboard, actual = b4c.initial_inventory()
    primary = _case4_vehicle()
    vehicles = _all_case4_vehicles(primary)
    htt = [{
        "vehicle_id": 1, "status": "PARKED", "current_node": 23,
        "destination_node": 24, "route": [23, 24], "edge_progress": 0.25,
        "cargo_H2_kg": 40.0, "P_HTT_kW": 0.0, "Q_HTT_kvar": 0.0,
    }]

    # Reproduce the duration dependence using independent mutable copies.
    interval_rows = []
    for label, duration in (("DT_0.5H", 0.5), ("DT_2.2833H", DEFAULT_DT_LONG)):
        result, station_after, vehicles_after = _run_interval_copy(
            CASE4_MASK, ARRIVAL, ARRIVAL + duration, [copy.deepcopy(primary)], station
        )
        row = _bus23(result)
        interval_rows.append({
            "case": "CASE-4",
            "probe": label,
            "start_h": ARRIVAL,
            "duration_h": duration,
            "served_P_kW": row["P_served_kW"],
            "shed_P_kW": row["P_shed_kW"],
            "served_Q_kvar": row["Q_served_kvar"],
            "shed_Q_kvar": row["Q_shed_kvar"],
            "MFCV_H2_after_kg": vehicles_after[0]["onboard_H2_kg"],
            "station_H2_after_kg": station_after.tolist(),
            "error": "",
        })
    try:
        _run_interval_copy(CASE4_MASK, ARRIVAL, ARRIVAL, [copy.deepcopy(primary)], station)
        dt_zero_error = "NONE"
    except Exception as exc:  # expected historical behavior
        dt_zero_error = type(exc).__name__ + ": " + str(exc)
    interval_rows.append({
        "case": "CASE-4", "probe": "DT_0H", "start_h": ARRIVAL,
        "duration_h": 0.0, "served_P_kW": "", "shed_P_kW": "",
        "served_Q_kvar": "", "shed_Q_kvar": "", "MFCV_H2_after_kg": "",
        "station_H2_after_kg": "", "error": dt_zero_error,
    })
    write_csv(out, "interface_reproduction.csv", interval_rows)

    # The same state is evaluated ten consecutive times through the
    # duration-free API.  Calls use the original fixture deliberately: a
    # mutating implementation must be visible in the state digests below.
    direct_before_digest = state_digest(station, vehicles, htt)
    snapshot_results = []
    snapshot_state_digests = []
    for _ in range(10):
        snapshot_results.append(
            b4c.dispatch_snapshot(CASE4_MASK, ARRIVAL, vehicles, station, htt)
        )
        snapshot_state_digests.append(state_digest(station, vehicles, htt))
    snap = snapshot_results[0]
    snap_repeat = snapshot_results[-1]
    direct_after_digest = snapshot_state_digests[0]
    repeat_after_digest = snapshot_state_digests[-1]
    snap_station, snap_vehicles, snap_htt = station, vehicles, htt
    repeat_station, repeat_vehicles, repeat_htt = station, vehicles, htt
    snap_bus = _bus23(snap)
    snap_component = _component23(snap)
    write_csv(out, "snapshot_case_summary.csv", [{
        "case": "CASE-4", "mask": CASE4_MASK, "snapshot_time_h": ARRIVAL,
        "snapshot_semantics": snap["snapshot_semantics"],
        "bus23_P_load_kW": snap_bus["P_load_kW"],
        "bus23_P_served_kW": snap_bus["P_served_kW"],
        "bus23_P_shed_kW": snap_bus["P_shed_kW"],
        "bus23_Q_load_kvar": snap_bus["Q_load_kvar"],
        "bus23_Q_served_kvar": snap_bus["Q_served_kvar"],
        "bus23_voltage_pu": snap_bus["voltage_pu"],
        "component_id": snap_component["component_id"],
        "component_buses": json.dumps(snap_component["buses"]),
        "component_total_P_shed_kW": snap_component["total_P_shed_kW"],
        "total_P_load_kW": snap["totals"]["total_P_load_kW"],
        "total_P_served_kW": snap["totals"]["total_P_served_kW"],
        "total_P_shed_kW": snap["totals"]["total_P_shed_kW"],
    }])
    write_csv(out, "snapshot_bus_detail.csv", snap["bus_rows"])
    write_csv(out, "snapshot_branch_detail.csv", snap["branch_rows"])
    write_csv(out, "snapshot_source_detail.csv", snap["sources"])
    write_csv(out, "snapshot_component_detail.csv", snap["component_rows"])

    # H2 nonbinding identity: use a positive short interval where all source
    # energy bounds exceed their hardware caps, then compare to snapshot.
    rich_station = np.full(4, 100.0)
    rich_primary = _case4_vehicle(onboard=20.0)
    rich_vehicles = _all_case4_vehicles(rich_primary)
    identity_snap, *_ = _snapshot_copy(CASE4_MASK, ARRIVAL, rich_vehicles, rich_station)
    identity_interval, _, _ = _run_interval_copy(
        CASE4_MASK, ARRIVAL, ARRIVAL + 0.1, rich_vehicles, rich_station
    )
    identity_ok, identity_reason = _compare_results(identity_snap, identity_interval)
    write_csv(out, "snapshot_interval_identity.csv", [{
        "fixture": "H2_ENERGY_NONBINDING", "interval_dt_h": 0.1,
        "snapshot_P_served_kW": identity_snap["totals"]["total_P_served_kW"],
        "interval_P_served_kW": identity_interval["totals"]["total_P_served_kW"],
        "snapshot_P_shed_kW": identity_snap["totals"]["total_P_shed_kW"],
        "interval_P_shed_kW": identity_interval["totals"]["total_P_shed_kW"],
        "snapshot_Q_served_kvar": identity_snap["totals"]["total_Q_served_kvar"],
        "interval_Q_served_kvar": identity_interval["totals"]["total_Q_served_kvar"],
        "max_P_abs_diff_kW": abs(identity_snap["totals"]["total_P_served_kW"] - identity_interval["totals"]["total_P_served_kW"]),
        "max_Q_abs_diff_kvar": abs(identity_snap["totals"]["total_Q_served_kvar"] - identity_interval["totals"]["total_Q_served_kvar"]),
        "identity_result": "PASS" if identity_ok else "FAIL",
        "difference_reason": identity_reason,
    }])

    # Availability gates S1-S5, retaining all six vehicle rows in each probe.
    availability_rows = []
    case3_mask = (1 << 22) | (1 << 23)
    s1_station = station.copy(); s1_station[0] = 0.0
    s1_vehicles = _all_case4_vehicles(_case4_vehicle(onboard=0.0))
    s1, *_ = _snapshot_copy(case3_mask, ARRIVAL, s1_vehicles, s1_station)
    fc1 = _source(s1, "FC-1")
    availability_rows.append({"test": "S1_FIXED_FC_H2_ZERO", "resource_id": "FC-1", "availability": fc1["availability"], "P": fc1["actual_P_kW"], "Q": fc1["actual_Q_kvar"], "result": "PASS" if not fc1["availability"] and fc1["actual_P_kW"] == 0 and fc1["actual_Q_kvar"] == 0 else "FAIL"})
    s2_station = station.copy(); s2_station[0] = 1.0
    s2, *_ = _snapshot_copy(case3_mask, ARRIVAL, _all_case4_vehicles(_case4_vehicle(onboard=0.0)), s2_station)
    fc2 = _source(s2, "FC-1")
    availability_rows.append({"test": "S2_FIXED_FC_H2_POSITIVE", "resource_id": "FC-1", "availability": fc2["availability"], "P": fc2["actual_P_kW"], "Q": fc2["actual_Q_kvar"], "result": "PASS" if fc2["availability"] and fc2["actual_P_kW"] > TOL and fc2["actual_P_kW"] <= b4c.FC_PMAX[0] + TOL else "FAIL"})
    moving, *_ = _snapshot_copy(CASE4_MASK, ARRIVAL, _all_case4_vehicles(_case4_vehicle(onboard=10.0, state="MOVING", moving=True)), station)
    m1 = _source(moving, "MFCV-1")
    availability_rows.append({"test": "S3_MFCV_MOVING_H2_POSITIVE", "resource_id": "MFCV-1", "availability": m1["availability"], "P": m1["actual_P_kW"], "Q": m1["actual_Q_kvar"], "result": "PASS" if not m1["availability"] and m1["actual_P_kW"] == 0 and m1["actual_Q_kvar"] == 0 else "FAIL"})
    empty, *_ = _snapshot_copy(CASE4_MASK, ARRIVAL, _all_case4_vehicles(_case4_vehicle(onboard=0.0)), station)
    m2 = _source(empty, "MFCV-1")
    availability_rows.append({"test": "S4_MFCV_SERVICE_H2_ZERO", "resource_id": "MFCV-1", "availability": m2["availability"], "P": m2["actual_P_kW"], "Q": m2["actual_Q_kvar"], "result": "PASS" if not m2["availability"] and m2["actual_P_kW"] == 0 and m2["actual_Q_kvar"] == 0 else "FAIL"})
    service, *_ = _snapshot_copy(CASE4_MASK, ARRIVAL, _all_case4_vehicles(_case4_vehicle(onboard=10.0)), station)
    m3 = _source(service, "MFCV-1")
    availability_rows.append({"test": "S5_MFCV_SERVICE_H2_POSITIVE", "resource_id": "MFCV-1", "availability": m3["availability"], "P": m3["actual_P_kW"], "Q": m3["actual_Q_kvar"], "result": "PASS" if m3["availability"] and m3["actual_P_kW"] > TOL and m3["actual_P_kW"] <= b4c.MFCV_PMAX + TOL else "FAIL"})
    write_csv(out, "snapshot_availability_tests.csv", availability_rows)

    # No-mutation and deterministic replay include HTT cargo/PQ fields.
    before_digest = direct_before_digest
    after_digest = direct_after_digest
    repeat_digest = repeat_after_digest
    no_mutation = all(digest == before_digest for digest in snapshot_state_digests)
    idempotence = (
        all(_compare_results(snap, result)[0] for result in snapshot_results[1:])
        and len(snapshot_results) == 10
    )
    htt_rows = [row for row in snap["sources"] if row["resource_type"] == "HTT"]
    htt_ids = {row["resource_id"] for row in htt_rows}
    htt_root_ids = {
        resource_id
        for component in snap["component_rows"]
        for resource_id in (
            component["real_sources"] + component["actual_injecting_sources"]
        )
        if resource_id in htt_ids
    }
    htt_zero = (
        len(htt_rows) == len(htt)
        and all(
            float(row["actual_P_kW"]) == 0
            and float(row["actual_Q_kvar"]) == 0
            and not row["availability"]
            for row in htt_rows
        )
        and not any(
            row["resource_id"] in htt_ids for row in snap["source_dispatch"]
        )
        and not htt_root_ids
    )
    write_json(out, "snapshot_no_mutation_audit.json", {
        "before_state_sha256": before_digest,
        "after_state_sha256": after_digest,
        "repeat_state_sha256": repeat_digest,
        "SNAPSHOT_NO_STATE_MUTATION_QA": "PASS" if no_mutation else "FAIL",
        "SNAPSHOT_IDEMPOTENCE_QA": "PASS" if idempotence else "FAIL",
        "SNAPSHOT_NO_EENS_ACCOUNTING_QA": "PASS" if not _contains_key(snap, "EENS_kWh") and all(float(row.get("H2_use_kg", 0.0)) == 0.0 for row in snap["sources"]) else "FAIL",
        "SNAPSHOT_NO_DT_PARAMETER_QA": "PASS" if not any(name in {"dt", "duration_h", "start", "end"} for name in inspect.signature(b4c.dispatch_snapshot).parameters) else "FAIL",
        "HTT_PQ_ZERO_QA": "PASS" if htt_zero else "FAIL",
        "HTT_ELECTRICAL_SOURCE_EXCLUSION_QA": "PASS" if not htt_root_ids else "FAIL",
        "snapshot_calls": len(snapshot_results),
    })

    regression = _regression_summary(args)
    write_json(out, "regression_summary.json", regression)
    write_csv(
        out, "b4c_historical_artifact_identity.csv",
        regression["B4C"]["historical_artifact_identity"]["files"],
    )
    b4c_interval_identity = (
        regression["B4C"]["historical_artifact_identity"]["status"] == "PASS"
    )
    qa = {
        "INTERVAL_DURATION_DEPENDENCE_REPRODUCED": "PASS" if interval_rows[0]["shed_P_kW"] < interval_rows[1]["shed_P_kW"] else "FAIL",
        "SNAPSHOT_CURRENT_STATE_RESULT": "PASS" if _numeric_equal(snap_bus["P_shed_kW"], _bus23(snap_repeat)["P_shed_kW"]) else "FAIL",
        "SNAPSHOT_INTERVAL_NONBINDING_IDENTITY_QA": "PASS" if identity_ok else "FAIL",
        "S1_FIXED_FC_H2_GATING": availability_rows[0]["result"],
        "S2_FIXED_FC_H2_POSITIVE": availability_rows[1]["result"],
        "S3_MFCV_MOVING_H2_GATING": availability_rows[2]["result"],
        "S4_MFCV_SERVICE_H2_ZERO": availability_rows[3]["result"],
        "S5_MFCV_SERVICE_H2_POSITIVE": availability_rows[4]["result"],
        "SNAPSHOT_NO_STATE_MUTATION": "PASS" if no_mutation else "FAIL",
        "SNAPSHOT_IDEMPOTENCE": "PASS" if idempotence else "FAIL",
        "SNAPSHOT_NO_EENS_ACCOUNTING": "PASS" if not _contains_key(snap, "EENS_kWh") else "FAIL",
        "SNAPSHOT_NO_DT_PARAMETER": "PASS" if not any(name in {"dt", "duration_h", "start", "end"} for name in inspect.signature(b4c.dispatch_snapshot).parameters) else "FAIL",
        "FIXED_FC_H2_GATING": "VERIFIED" if availability_rows[0]["result"] == "PASS" and availability_rows[1]["result"] == "PASS" else "NOT_VERIFIED",
        "MFCV_H2_SERVICE_GATING": "VERIFIED" if availability_rows[2]["result"] == "PASS" and availability_rows[3]["result"] == "PASS" and availability_rows[4]["result"] == "PASS" else "NOT_VERIFIED",
        "HTT_PQ_ZERO": "VERIFIED" if htt_zero else "NOT_VERIFIED",
        "B3_REGRESSION": regression["B3"]["status"],
        "B4C_REGRESSION": regression["B4C"]["status"],
        "B4D_REGRESSION": regression["B4D"]["status"],
        "B4C_HISTORICAL_ARTIFACT_IDENTITY": (
            "PASS" if b4c_interval_identity else "FAIL"
        ),
    }
    write_json(out, "QA_closeout.json", qa)

    summary = {
        "B5A_SNAPSHOT_INTERFACE_SMOKE": "PASS" if all(value in ("PASS", "VERIFIED") for value in qa.values()) else "FAIL",
        "INTERVAL_DURATION_DEPENDENCE_REPRODUCED": "YES" if qa["INTERVAL_DURATION_DEPENDENCE_REPRODUCED"] == "PASS" else "NO",
        "SNAPSHOT_CURRENT_STATE_RESULT": "UNIQUE" if qa["SNAPSHOT_CURRENT_STATE_RESULT"] == "PASS" else "NOT_UNIQUE",
        "SNAPSHOT_INTERVAL_NONBINDING_IDENTITY": qa["SNAPSHOT_INTERVAL_NONBINDING_IDENTITY_QA"],
        "SNAPSHOT_NO_STATE_MUTATION": qa["SNAPSHOT_NO_STATE_MUTATION"],
        "SNAPSHOT_IDEMPOTENCE": qa["SNAPSHOT_IDEMPOTENCE"],
        "SNAPSHOT_NO_EENS_ACCOUNTING": qa["SNAPSHOT_NO_EENS_ACCOUNTING"],
        "SNAPSHOT_NO_DT_PARAMETER": qa["SNAPSHOT_NO_DT_PARAMETER"],
        "FIXED_FC_H2_GATING": qa["FIXED_FC_H2_GATING"],
        "MFCV_H2_SERVICE_GATING": qa["MFCV_H2_SERVICE_GATING"],
        "HTT_PQ_ZERO": qa["HTT_PQ_ZERO"],
        "snapshot_current_bus23_shed_P_kW": snap_bus["P_shed_kW"],
        "snapshot_total_P_shed_kW": snap["totals"]["total_P_shed_kW"],
        "B3_REGRESSION": regression["B3"]["status"],
        "B4C_REGRESSION": regression["B4C"]["status"],
        "B4D_REGRESSION": regression["B4D"]["status"],
        "B4C_INTERVAL_SEMANTICS_CHANGED": (
            "NO" if b4c_interval_identity else "YES"
        ),
        "READY_TO_RESUME_B5A_MFCV_POLICY": (
            "YES" if b4c_interval_identity else "NO"
        ),
        "B5A_DISPATCHER_IMPLEMENTED": "NO",
        "commit": "NONE",
        "push": "NONE",
        "precheck_HEAD": precheck["HEAD"],
    }
    write_json(out, "final_summary.json", summary)
    write_json(out, "precheck.json", precheck)
    write_json(out, "snapshot_interface_result.json", {
        "snapshot": snap,
        "interval_reproduction": interval_rows,
        "availability_tests": availability_rows,
    })
    write_csv(out, "exact_modified_files.csv", [
        {
            "path": "W_OOS/V1/src/b4_event_driven_restoration_smoke.py",
            "change": "shared pure LinDistFlow core and duration-free dispatch_snapshot API",
            "protected_modules_modified": "NO",
        },
        {
            "path": "W_OOS/V1/src/b5a_snapshot_interface_smoke.py",
            "change": "standalone B5A read-only snapshot smoke runner and QA artifacts",
            "protected_modules_modified": "NO",
        },
        {
            "path": "codex_rule/log.md",
            "change": "append verified B5A snapshot-interface task record",
            "protected_modules_modified": "NO",
        },
    ])
    (out / "00_report_zh.md").write_text(
        "# W_OOS/V1-B5A Read-Only Electrical Snapshot Interface Smoke\n\n"
        "本脚本只调用 B4C 的 `dispatch_snapshot`，没有实现 B5A dispatcher；"
        "snapshot 不推进时间、不扣 H2、不计算 EENS。\n\n"
        f"CASE-4 到站状态下，旧 interval 复现为 0.5h shed="
        f"{interval_rows[0]['shed_P_kW']} kW，2.2833h shed="
        f"{interval_rows[1]['shed_P_kW']} kW；snapshot bus23 当前 shed="
        f"{snap_bus['P_shed_kW']} kW。\n\n"
        f"nonbinding identity={qa['SNAPSHOT_INTERVAL_NONBINDING_IDENTITY_QA']}，"
        f"no-mutation={qa['SNAPSHOT_NO_STATE_MUTATION']}，"
        f"idempotence={qa['SNAPSHOT_IDEMPOTENCE']}（连续 {len(snapshot_results)} 次）。\n\n"
        "最终门禁：\n"
        f"B5A_SNAPSHOT_INTERFACE_SMOKE={summary['B5A_SNAPSHOT_INTERFACE_SMOKE']}；"
        f"B3_REGRESSION={summary['B3_REGRESSION']}；"
        f"B4C_REGRESSION={summary['B4C_REGRESSION']}；"
        f"B4D_REGRESSION={summary['B4D_REGRESSION']}；"
        f"B4C_INTERVAL_SEMANTICS_CHANGED={summary['B4C_INTERVAL_SEMANTICS_CHANGED']}；"
        f"READY_TO_RESUME_B5A_MFCV_POLICY={summary['READY_TO_RESUME_B5A_MFCV_POLICY']}。\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print("OUTPUT=" + str(out))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", default="run-001")
    parser.add_argument("--b3-run", default=None)
    parser.add_argument("--b4c-run", default=None)
    parser.add_argument(
        "--b4c-baseline-run",
        default="W_OOS/V1/results/b4-event-driven-restoration/run-008-b4d-regression",
    )
    parser.add_argument("--b4d-run", default=None)
    args = parser.parse_args()
    if not args.run.startswith("run-"):
        raise ValueError("Expected a non-overwriting run-* directory")
    run(args)


if __name__ == "__main__":
    main()
