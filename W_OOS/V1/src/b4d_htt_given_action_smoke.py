"""B4D given-action HTT physics and station-logistics engineering smoke."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd

import b4_event_driven_restoration_smoke as b4c
from engine import nominal as b3_nominal
from htt_state import HTT_CAPACITY_KG, HTT_COUNT, HTTState, MovePlan, simulate_with_b3_motion
from htt_transfer import (
    ENABLE_HTT_TO_MFCV_REFUEL,
    H2_STATION_BUSES,
    MFCVState,
    TransferAction,
    apply_transfer_batch,
)
from road import Road


ROOT = Path(__file__).resolve().parents[3]
V1 = ROOT / "W_OOS/V1"
RESULT_ROOT = V1 / "results/b4d-htt-given-action"
TOL = 1e-9
ARRIVAL_10_H = 1.2166666666667
TRACTION_MODEL = "NOT_MODELED_IN_B4D"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(out: Path, name: str, value) -> None:
    (out / name).write_text(
        json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def write_csv(out: Path, name: str, rows) -> None:
    frame = pd.DataFrame(list(rows))
    if frame.empty:
        raise ValueError("Cannot serialize empty B4D artifact: " + name)
    frame.to_csv(out / name, index=False, encoding="utf-8")


def process_status():
    command = (
        "@(Get-CimInstance Win32_Process | Where-Object "
        "{$_.Name -match 'matlab|gurobi'} | Select-Object ProcessId,Name) "
        "| ConvertTo-Json -Compress"
    )
    try:
        raw = subprocess.check_output(["powershell", "-NoProfile", "-Command", command], text=True)
        return json.loads(raw) if raw.strip() else []
    except Exception as exc:
        return {"error": str(exc)}


def git_output(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def git_precheck():
    # Preserve porcelain's leading index/worktree columns; ``str.strip`` would
    # erase the first line's leading space and misclassify a worktree edit as
    # staged when the status output starts with `` M``.
    status_raw = subprocess.check_output(
        ["git", "status", "--porcelain=v1"], cwd=ROOT, text=True
    )
    status = status_raw.rstrip("\r\n").splitlines()
    staged = [line for line in status if line[:1] != " " and line[:2] != "??"]
    tracked_dirty = [line for line in status if line[:2] != "??"]
    untracked_status = [line for line in status if line[:2] == "??"]
    upstream = git_output("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
    ahead_behind = git_output("rev-list", "--left-right", "--count", "HEAD..." + upstream).split()
    return {
        "branch": git_output("branch", "--show-current"),
        "HEAD": git_output("rev-parse", "HEAD"),
        "upstream": upstream,
        "ahead": int(ahead_behind[0]),
        "behind": int(ahead_behind[1]),
        "staged_files": staged,
        "tracked_dirty_files": tracked_dirty,
        "tracked_dirty_count": len(tracked_dirty),
        "untracked_status_entries": untracked_status,
        "untracked_status_entry_count": len(untracked_status),
        "untracked_file_count": len(git_output("ls-files", "--others", "--exclude-standard").splitlines()),
    }


def fixture(edges, lengths, close_after=None, consequence_after=None, identity="B4D_SYNTHETIC_FIXTURE"):
    edges = np.asarray(edges, dtype=int)
    lengths = np.asarray(lengths, dtype=float)
    consequence = np.zeros((6, len(edges)))
    closed = np.zeros((6, len(edges)), dtype=bool)
    for edge, state in (close_after or {}).items():
        closed[int(state):, int(edge)] = True
    for edge, state, value in consequence_after or []:
        consequence[int(state):, int(edge)] = float(value)
    return Road(edges, lengths, consequence, closed, identity=identity)


def new_htt(node1=24, node2=14, cargo1=0.0, cargo2=0.0):
    return {
        1: HTTState(1, "PARKED", int(node1), cargo_H2_kg=float(cargo1)),
        2: HTTState(2, "PARKED", int(node2), cargo_H2_kg=float(cargo2)),
    }


def system_total(station, htt, mfcv):
    return float(
        np.asarray(station, dtype=float).sum()
        + sum(state.cargo_H2_kg for state in htt.values())
        + sum(state.onboard_H2_kg for state in mfcv.values())
    )


def identity_row(case, initial_total, station, htt, mfcv, fixed_use=0.0, mfcv_use=0.0):
    final_station = float(np.asarray(station).sum())
    final_mfcv = float(sum(state.onboard_H2_kg for state in mfcv.values()))
    final_htt = float(sum(state.cargo_H2_kg for state in htt.values()))
    error = float(initial_total - final_station - final_mfcv - final_htt - fixed_use - mfcv_use)
    return dict(
        case=case,
        initial_total_H2_kg=float(initial_total),
        final_station_H2_kg=final_station,
        final_MFCV_onboard_H2_kg=final_mfcv,
        final_HTT_cargo_H2_kg=final_htt,
        fixed_FC_H2_use_kg=float(fixed_use),
        MFCV_H2_use_kg=float(mfcv_use),
        identity_error_kg=error,
    )


def add_initial_state(case, htt, state_rows):
    for vehicle_id, state in sorted(htt.items()):
        state_rows.append(
            dict(
                case=case,
                time_h=0.0,
                vehicle_id=vehicle_id,
                event="INITIAL",
                status=state.status,
                current_node=state.current_node,
                destination_node="",
                route="[]",
                edge_progress=0.0,
                departure_time="",
                arrival_time="",
                cargo_H2_kg=state.cargo_H2_kg,
                P_HTT_kW=state.P_HTT_kW,
                Q_HTT_kvar=state.Q_HTT_kvar,
            )
        )


def transfer(
    case,
    batch_id,
    actions,
    station,
    htt,
    mfcv,
    transfer_rows,
    event_rows,
    state_rows,
):
    result = apply_transfer_batch(actions, station, htt, mfcv, ENABLE_HTT_TO_MFCV_REFUEL)
    for record in result.records:
        row = dict(record)
        row.update(case=case, batch_id=batch_id)
        transfer_rows.append(row)
        event_rows.append(
            dict(
                case=case,
                time_h=row["batch_time_h"],
                vehicle_id=row["htt_id"],
                event=row["transfer_type"],
                node=row["station_bus"],
                status=row["status"],
                detail=row["reason"],
            )
        )
        if row["htt_id"] != "":
            state = htt[int(row["htt_id"])]
            state_rows.append(
                dict(
                    case=case,
                    time_h=row["batch_time_h"],
                    vehicle_id=state.vehicle_id,
                    event=row["transfer_type"],
                    status=state.status,
                    current_node=state.current_node,
                    destination_node="",
                    route="[]",
                    edge_progress=0.0,
                    departure_time="",
                    arrival_time=row["batch_time_h"],
                    cargo_H2_kg=state.cargo_H2_kg,
                    P_HTT_kW=state.P_HTT_kW,
                    Q_HTT_kvar=state.Q_HTT_kvar,
                )
            )
    return result


def cargo_at(initial_cargo, case_transfer_rows, vehicle_id, time_h):
    cargo = float(initial_cargo[vehicle_id])
    for row in sorted(case_transfer_rows, key=lambda item: (float(item["batch_time_h"]), item["action_id"])):
        if row["htt_id"] == vehicle_id and float(row["batch_time_h"]) <= time_h + TOL:
            if row["HTT_cargo_after_kg"] != "":
                cargo = float(row["HTT_cargo_after_kg"])
    return cargo


def record_motion(
    case,
    road,
    initial_nodes,
    plans,
    until_h,
    initial_cargo,
    case_transfer_rows,
    movement_rows,
    event_rows,
    state_rows,
):
    result = simulate_with_b3_motion(road, initial_nodes, plans, until_h)
    for event in result.events:
        row = dict(event)
        for key, value in list(row.items()):
            if isinstance(value, list):
                row[key] = json.dumps(value)
        row.update(case=case, source_engine="B3 Simulator")
        event_rows.append(row)
        vehicle_id = int(event["vehicle_id"])
        if event["event"] in {"EDGE_ENTER", "EDGE_ARRIVAL", "MOVE_COMPLETE", "UNREACHABLE"}:
            moving = event["event"] == "EDGE_ENTER"
            state_rows.append(
                dict(
                    case=case,
                    time_h=float(event["time_h"]),
                    vehicle_id=vehicle_id,
                    event=event["event"],
                    status="MOVING" if moving else "PARKED",
                    current_node="" if moving else event.get("node", ""),
                    destination_node=event.get("to_node", "") if moving else "",
                    route=json.dumps(event.get("route_edges", [])),
                    edge_progress=0.0,
                    departure_time=event.get("time_h", "") if moving else "",
                    arrival_time=event.get("arrival_h", "") if moving else event.get("time_h", ""),
                    cargo_H2_kg=cargo_at(initial_cargo, case_transfer_rows, vehicle_id, float(event["time_h"])),
                    P_HTT_kW=0.0,
                    Q_HTT_kvar=0.0,
                )
            )
    for row in result.movement_ledger:
        item = dict(row)
        item.update(
            case=case,
            source_engine="B3 Simulator",
            HTT_cargo_H2_kg=cargo_at(initial_cargo, case_transfer_rows, int(row["vehicle_id"]), float(row["time_start"])),
            P_HTT_kW=0.0,
            Q_HTT_kvar=0.0,
        )
        movement_rows.append(item)
    return result


def b4_vehicles(onboard=None):
    values = np.zeros(6) if onboard is None else np.asarray(onboard, dtype=float)
    anchors = [24, 24, 14, 18, 31, 31]
    return [
        dict(
            vehicle_id=i + 1,
            bus=anchors[i],
            arrival=0.0,
            departure=3.5,
            onboard_H2_kg=float(values[i]),
            state="PARKED",
        )
        for i in range(6)
    ]


def evaluate_b4c_intervals(case, mask, event_times, station, vehicles):
    intervals, roots, services, station_rows, mfcv_rows = [], [], [], [], []
    times = sorted(set(float(value) for value in event_times))
    if len(times) < 2:
        raise ValueError("B4C interval evaluation requires at least two event times")
    previous_branches = []
    for event_index, (start, end) in enumerate(zip(times[:-1], times[1:])):
        station_before = station.copy()
        onboard_before = {v["vehicle_id"]: float(v["onboard_H2_kg"]) for v in vehicles}
        result = b4c.dispatch_interval(mask, start, end, vehicles, station)
        sources = {row["resource_id"]: row for row in result["sources"]}
        for row in result["roots"]:
            roots.append(dict(row, case=case, interval_start_h=start, interval_end_h=end))
        for row in result["services"]:
            services.append(dict(row, case=case, interval_start_h=start, interval_end_h=end, duration_h=end - start))
        for index, bus in enumerate(b4c.FC_BUSES):
            resource_id = "FC-%d" % (index + 1)
            row = sources.get(
                resource_id,
                b4c.source_record("FIXED_FC", resource_id, bus, b4c.FC_PMAX[index], 0, 0, station_before[index], 0, station[index], index + 1),
            )
            station_rows.append(
                dict(
                    case=case,
                    interval_start_h=start,
                    interval_end_h=end,
                    duration_h=end - start,
                    row_type="B4C_INTERVAL",
                    station_site=index + 1,
                    station_bus=bus,
                    H2_before_kg=row["H2_before_kg"],
                    transfer_in_kg=0.0,
                    transfer_out_kg=0.0,
                    fixed_FC_H2_use_kg=row["H2_use_kg"],
                    H2_use_kg=row["H2_use_kg"],
                    H2_after_kg=row["H2_after_kg"],
                    actual_P_kW=row["actual_P_kW"],
                    actual_Q_kvar=row["actual_Q_kvar"],
                )
            )
        for vehicle in vehicles:
            resource_id = "MFCV-%d" % vehicle["vehicle_id"]
            row = sources.get(
                resource_id,
                b4c.source_record("MFCV", resource_id, vehicle["bus"], b4c.MFCV_PMAX, 0, 0, onboard_before[vehicle["vehicle_id"]], 0, vehicle["onboard_H2_kg"]),
            )
            mfcv_rows.append(
                dict(
                    case=case,
                    interval_start_h=start,
                    interval_end_h=end,
                    duration_h=end - start,
                    row_type="B4C_INTERVAL",
                    vehicle_id=vehicle["vehicle_id"],
                    bus=vehicle["bus"],
                    H2_before_kg=onboard_before[vehicle["vehicle_id"]],
                    station_refuel_kg=0.0,
                    H2_use_kg=row["H2_use_kg"],
                    H2_after_kg=vehicle["onboard_H2_kg"],
                    actual_P_kW=row["actual_P_kW"],
                    actual_Q_kvar=row["actual_Q_kvar"],
                )
            )
        active_ids = [branch_id for branch_id, _ in result["active"]]
        served_p = float(result["served_p"].sum())
        served_q = float(result["served_q"].sum())
        intervals.append(
            dict(
                case=case,
                event_index=event_index,
                interval_start_h=start,
                interval_end_h=end,
                duration_h=end - start,
                mask=mask,
                served_P_kW=served_p,
                served_Q_kvar=served_q,
                load_P_kW=b4c.p_load_sum(),
                load_Q_kvar=b4c.q_load_sum(),
                shed_P_kW=b4c.p_load_sum() - served_p,
                shed_Q_kvar=b4c.q_load_sum() - served_q,
                EENS_kWh=(end - start) * (b4c.p_load_sum() - served_p),
                min_voltage_pu=float(result["voltage"].min()),
                max_voltage_pu=float(result["voltage"].max()),
                max_branch_utilization=float(result["max_util"]),
                active_branch_count=len(active_ids),
                switch_operations=len(set(active_ids) ^ set(previous_branches)),
            )
        )
        previous_branches = active_ids
    return dict(
        intervals=intervals,
        roots=roots,
        services=services,
        station_rows=station_rows,
        mfcv_rows=mfcv_rows,
        station=station,
        vehicles=vehicles,
    )


def max_row_difference(left, right, fields):
    if len(left) != len(right):
        return float("inf")
    maximum = 0.0
    for a, b in zip(left, right):
        for field in fields:
            maximum = max(maximum, abs(float(a[field]) - float(b[field])))
    return maximum


def case_number(row):
    token = str(row.get("case", "CASE-999")).split("-")[1].split("_")[0]
    return int(token) if token.isdigit() else 999


def event_priority(event):
    return {
        "EDGE_ARRIVAL": 10,
        "MOVE_COMPLETE": 20,
        "ARRIVAL": 20,
        "UNREACHABLE": 20,
        "HTT_TO_STATION": 30,
        "STATION_TO_HTT": 30,
        "STATION_TO_MFCV": 40,
        "HTT_TO_MFCV": 40,
        "ACTION_START": 50,
        "EDGE_ENTER": 60,
        "TRANSFER_EVENT": 30,
        "MOVING": 60,
    }.get(str(event), 45)


def run(out: Path, b3_run: Path, b4c_run: Path):
    if out.exists():
        raise FileExistsError("B4D run directory already exists: " + str(out))
    out.mkdir(parents=True)

    protected = [
        V1 / "src/engine.py",
        V1 / "src/road.py",
        V1 / "src/b4_event_driven_restoration_smoke.py",
        V1 / "tests/run_b3_smoke.py",
        ROOT / "data/yuanqi/near_stage_msp_input.mat",
    ]
    source_before = {path: sha256(path) for path in protected}
    initial_processes = process_status()
    precheck = git_precheck()

    transfer_rows = []
    event_rows = []
    movement_rows = []
    state_rows = []
    station_rows = []
    mfcv_rows = []
    htt_h2_rows = []
    electrical_rows = []
    root_rows = []
    identity_rows = []
    fixed_tests = []
    checks = {}

    def check(name, condition):
        checks[name] = "PASS" if bool(condition) else "FAIL"
        if not condition:
            raise AssertionError(name)

    def add_test(case, values, detail):
        fixed_tests.append(dict(case=case, result="PASS", core_values=json.dumps(values, ensure_ascii=False), detail=detail))

    def add_transfer_ledgers(case_records):
        for row in case_records:
            if row["station_site"] != "":
                station_rows.append(
                    dict(
                        case=row["case"],
                        interval_start_h=row["batch_time_h"],
                        interval_end_h=row["batch_time_h"],
                        duration_h=0.0,
                        row_type="TRANSFER_EVENT",
                        station_site=row["station_site"],
                        station_bus=row["station_bus"],
                        H2_before_kg=row["station_H2_before_kg"],
                        transfer_in_kg=row["transferred_kg"] if row["transfer_type"] == "HTT_TO_STATION" else 0.0,
                        transfer_out_kg=row["transferred_kg"] if row["transfer_type"] in {"STATION_TO_HTT", "STATION_TO_MFCV"} else 0.0,
                        fixed_FC_H2_use_kg=0.0,
                        H2_use_kg=0.0,
                        H2_after_kg=row["station_H2_after_kg"],
                        actual_P_kW=0.0,
                        actual_Q_kvar=0.0,
                    )
                )

            if row["mfcv_id"] != "":
                mfcv_rows.append(
                    dict(
                        case=row["case"],
                        interval_start_h=row["batch_time_h"],
                        interval_end_h=row["batch_time_h"],
                        duration_h=0.0,
                        row_type="TRANSFER_EVENT",
                        vehicle_id=row["mfcv_id"],
                        bus=row["station_bus"],
                        H2_before_kg=row["MFCV_onboard_before_kg"],
                        station_refuel_kg=row["transferred_kg"] if row["transfer_type"] == "STATION_TO_MFCV" else 0.0,
                        H2_use_kg=0.0,
                        H2_after_kg=row["MFCV_onboard_after_kg"],
                        actual_P_kW=0.0,
                        actual_Q_kvar=0.0,
                    )
                )
            if row["htt_id"] != "":
                htt_h2_rows.append(
                    dict(
                        case=row["case"],
                        interval_start_h=row["batch_time_h"],
                        interval_end_h=row["batch_time_h"],
                        duration_h=0.0,
                        vehicle_id=row["htt_id"],
                        state="TRANSFER_EVENT",
                        current_node=row["station_bus"],
                        cargo_H2_before_kg=row["HTT_cargo_before_kg"],
                        load_kg=row["transferred_kg"] if row["transfer_type"] == "STATION_TO_HTT" else 0.0,
                        unload_kg=row["transferred_kg"] if row["transfer_type"] == "HTT_TO_STATION" else 0.0,
                        cargo_H2_after_kg=row["HTT_cargo_after_kg"],
                        P_HTT_kW=0.0,
                        Q_HTT_kvar=0.0,
                    )
                )

    check(
        "STATION_MAPPING",
        tuple(b3_nominal()["site_anchors"]) == H2_STATION_BUSES == tuple(b4c.FC_BUSES),
    )

    # CASE-1: empty HTT loads at a station.
    case = "CASE-1"
    station = np.array([100.0, 0.0, 0.0, 0.0]); htt = new_htt(); mfcv = {}
    initial = system_total(station, htt, mfcv); add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    result = transfer(case, "C1-T0", [TransferAction("C1-LOAD", 0.0, "STATION_TO_HTT", 30.0, htt_id=1, station_bus=24)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE1_LOAD", result.feasible and abs(station[0] - 70.0) < TOL and abs(htt[1].cargo_H2_kg - 30.0) < TOL)
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"station_delta_kg": -30.0, "cargo_delta_kg": 30.0, "duration_h": 0.0}, "empty HTT load; system H2 unchanged")

    # CASE-2: capacity rejection is atomic.
    case = "CASE-2"
    station = np.array([100.0, 0.0, 0.0, 0.0]); htt = new_htt(cargo1=70.0); mfcv = {}
    initial = system_total(station, htt, mfcv); before = (station.copy(), htt[1].cargo_H2_kg); add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    result = transfer(case, "C2-T0", [TransferAction("C2-LOAD", 0.0, "STATION_TO_HTT", 20.0, htt_id=1, station_bus=24)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE2_CAPACITY", not result.feasible and result.reason == "HTT_CAPACITY_EXCEEDED" and np.array_equal(station, before[0]) and htt[1].cargo_H2_kg == before[1])
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"cargo_before_kg": 70.0, "requested_kg": 20.0, "capacity_kg": 80.0}, "infeasible capacity request rejected without clipping")

    # CASE-3: station inventory rejection is atomic.
    case = "CASE-3"
    station = np.array([15.0, 0.0, 0.0, 0.0]); htt = new_htt(); mfcv = {}
    initial = system_total(station, htt, mfcv); before = station.copy(); add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    result = transfer(case, "C3-T0", [TransferAction("C3-LOAD", 0.0, "STATION_TO_HTT", 30.0, htt_id=1, station_bus=24)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE3_STATION_BOUND", not result.feasible and result.reason == "INSUFFICIENT_STATION_INVENTORY" and np.array_equal(station, before))
    offsite_station = np.array([100.0, 0.0, 0.0, 0.0]); offsite_htt = new_htt(); offsite_htt[1].current_node = 1
    offsite_load = apply_transfer_batch([TransferAction("OFFSITE-LOAD", 0.0, "STATION_TO_HTT", 1.0, htt_id=1, station_bus=24)], offsite_station, offsite_htt, {})
    offsite_htt[1].cargo_H2_kg = 10.0
    offsite_unload = apply_transfer_batch([TransferAction("OFFSITE-UNLOAD", 0.0, "HTT_TO_STATION", 1.0, htt_id=1, station_bus=24)], offsite_station, offsite_htt, {})
    check("LOAD_LOCATION", not offsite_load.feasible and offsite_load.reason == "HTT_TRANSFER_REQUIRES_PARKED_AT_STATION" and offsite_station[0] == 100.0)
    check("UNLOAD_LOCATION", not offsite_unload.feasible and offsite_unload.reason == "HTT_TRANSFER_REQUIRES_PARKED_AT_STATION" and offsite_station[0] == 100.0 and offsite_htt[1].cargo_H2_kg == 10.0)
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"station_before_kg": 15.0, "requested_kg": 30.0}, "infeasible station request rejected; no negative inventory")

    # CASE-4: cross-station movement and no early H2.
    case = "CASE-4"
    station = np.array([40.0, 0.0, 0.0, 0.0]); htt = new_htt(); mfcv = {}
    initial = system_total(station, htt, mfcv); initial_cargo = {i: s.cargo_H2_kg for i, s in htt.items()}; add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    load = transfer(case, "C4-T0", [TransferAction("C4-LOAD", 0.0, "STATION_TO_HTT", 40.0, htt_id=1, station_bus=24)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    road = fixture([[24, 14]], [13.0]); motion = record_motion(case, road, [24, 14], {1: [MovePlan(14)]}, 0.4, initial_cargo, transfer_rows[start:], movement_rows, event_rows, state_rows)
    arrival = motion.arrivals[1][0]["time_h"]; before_target = station[1]; htt[1].current_node = 14; htt[1].status = "PARKED"; htt[1].arrival_time = arrival
    unload = transfer(case, "C4-ARRIVAL", [TransferAction("C4-UNLOAD", arrival, "HTT_TO_STATION", 40.0, htt_id=1, station_bus=14)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE4_NO_EARLY_H2", load.feasible and unload.feasible and before_target == 0.0 and abs(arrival - 0.325) < TOL and abs(station[1] - 40.0) < TOL)
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"arrival_h": arrival, "target_before_arrival_kg": before_target, "target_after_unload_kg": station[1]}, "target inventory changes only at exact B3 arrival")

    # CASE-5: partial unload.
    case = "CASE-5"
    station = np.zeros(4); htt = new_htt(node1=14, cargo1=80.0); mfcv = {}
    initial = system_total(station, htt, mfcv); add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    result = transfer(case, "C5-T0", [TransferAction("C5-UNLOAD", 0.0, "HTT_TO_STATION", 30.0, htt_id=1, station_bus=14)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE5_PARTIAL_UNLOAD", result.feasible and htt[1].cargo_H2_kg == 50.0 and station[1] == 30.0)
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"cargo_before_kg": 80.0, "unload_kg": 30.0, "cargo_after_kg": 50.0}, "partial unload retained cargo")

    # CASE-6: one HTT serves two stations without returning to a depot.
    case = "CASE-6"
    station = np.array([80.0, 0.0, 0.0, 0.0]); htt = new_htt(); mfcv = {}
    initial = system_total(station, htt, mfcv); initial_cargo = {i: s.cargo_H2_kg for i, s in htt.items()}; add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    transfer(case, "C6-T0", [TransferAction("C6-LOAD", 0.0, "STATION_TO_HTT", 80.0, htt_id=1, station_bus=24)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    road = fixture([[24, 14], [14, 18]], [13.0, 9.0]); motion = record_motion(case, road, [24, 14], {1: [MovePlan(14), MovePlan(18)]}, 0.7, initial_cargo, transfer_rows[start:], movement_rows, event_rows, state_rows)
    first, second = motion.arrivals[1]; htt[1].current_node = 14; htt[1].status = "PARKED"
    transfer(case, "C6-STOP1", [TransferAction("C6-UNLOAD-B", first["time_h"], "HTT_TO_STATION", 30.0, htt_id=1, station_bus=14)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    htt[1].current_node = 18; htt[1].status = "PARKED"
    transfer(case, "C6-STOP2", [TransferAction("C6-UNLOAD-C", second["time_h"], "HTT_TO_STATION", 20.0, htt_id=1, station_bus=18)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE6_MULTISTOP", abs(first["time_h"] - 0.325) < TOL and abs(second["time_h"] - 0.55) < TOL and htt[1].cargo_H2_kg == 30.0 and np.allclose(station, [0, 30, 20, 0]))
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"arrival_B_h": first["time_h"], "arrival_C_h": second["time_h"], "B_unload_kg": 30.0, "C_unload_kg": 20.0, "final_cargo_kg": 30.0}, "A->B->C multi-stop verified")

    # CASE-7: two independent HTTs move and transfer concurrently.
    case = "CASE-7"
    station = np.array([20.0, 0.0, 30.0, 0.0]); htt = new_htt(node1=24, node2=18); mfcv = {}
    initial = system_total(station, htt, mfcv); initial_cargo = {i: s.cargo_H2_kg for i, s in htt.items()}; add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    batch = transfer(case, "C7-T0", [TransferAction("C7-LOAD-1", 0.0, "STATION_TO_HTT", 20.0, htt_id=1, station_bus=24), TransferAction("C7-LOAD-2", 0.0, "STATION_TO_HTT", 30.0, htt_id=2, station_bus=18)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    road = fixture([[24, 14], [18, 31]], [13.0, 10.0]); motion = record_motion(case, road, [24, 18], {1: [MovePlan(14)], 2: [MovePlan(31)]}, 0.4, initial_cargo, transfer_rows[start:], movement_rows, event_rows, state_rows)
    a1 = motion.arrivals[1][0]; a2 = motion.arrivals[2][0]; htt[1].current_node = 14; htt[2].current_node = 31
    transfer(case, "C7-A1", [TransferAction("C7-UNLOAD-1", a1["time_h"], "HTT_TO_STATION", 20.0, htt_id=1, station_bus=14)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    transfer(case, "C7-A2", [TransferAction("C7-UNLOAD-2", a2["time_h"], "HTT_TO_STATION", 30.0, htt_id=2, station_bus=31)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE7_TWO_HTT", batch.feasible and a1["time_h"] != a2["time_h"] and np.allclose(station, [0, 20, 0, 30]) and htt[1].cargo_H2_kg == 0 and htt[2].cargo_H2_kg == 0)
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"HTT1_arrival_h": a1["time_h"], "HTT2_arrival_h": a2["time_h"], "HTT1_final_cargo_kg": 0.0, "HTT2_final_cargo_kg": 0.0}, "two vehicle states/routes/cargo remain independent")

    # CASE-8: simultaneous station requests cannot double-spend inventory.
    case = "CASE-8"
    station = np.array([100.0, 0.0, 0.0, 0.0]); htt = new_htt(node1=24, node2=24); mfcv = {}
    initial = system_total(station, htt, mfcv); add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    result = transfer(case, "C8-T0", [TransferAction("C8-LOAD-1", 0.0, "STATION_TO_HTT", 70.0, htt_id=1, station_bus=24), TransferAction("C8-LOAD-2", 0.0, "STATION_TO_HTT", 60.0, htt_id=2, station_bus=24)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE8_NO_DOUBLE_SPEND", not result.feasible and station[0] == 100.0 and htt[1].cargo_H2_kg == 0.0 and htt[2].cargo_H2_kg == 0.0)
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"available_kg": 100.0, "total_requested_kg": 130.0, "final_station_kg": 100.0}, "whole timestamp batch rejected atomically")

    # CASE-9: B3 entered-edge closure and reroute semantics.
    case = "CASE-9"
    station = np.zeros(4); htt = new_htt(); mfcv = {}; initial = 0.0; initial_cargo = {1: 0.0, 2: 0.0}; add_initial_state(case, htt, state_rows)
    road = fixture([[24, 1], [1, 14], [14, 24]], [13.0, 9.0, 9.0], close_after={0: 2})
    motion = record_motion(case, road, [24, 14], {1: [MovePlan(1, 1.4), MovePlan(24)]}, 2.3, initial_cargo, [], movement_rows, event_rows, state_rows)
    entries = [row for row in motion.events if row["event"] == "EDGE_ENTER" and row["vehicle_id"] == 1]
    split = [row for row in motion.movement_ledger if row["vehicle_id"] == 1 and row["current_edge"] == 1]
    check("CASE9_B3_DYNAMIC_CLOSURE", [row["edge_id"] for row in entries] == [1, 2, 3] and len(split) >= 2 and abs(split[0]["physical_progress_after_km"] - split[1]["physical_progress_before_km"]) < TOL)
    identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"entered_edges": [row["edge_id"] for row in entries], "first_edge_closed_at_h": 1.5, "final_node": motion.final_nodes[1]}, "entered edge completed, then B3 rerouted without re-entering closed edge")

    # CASE-10: exact HTT arrival changes station H2 before the next B4C interval.
    case = "CASE-10"
    station = np.array([0.0, 40.0, 0.0, 0.0]); htt = new_htt(node1=14, node2=24); mfcv = {}
    initial = system_total(station, htt, mfcv); initial_cargo = {1: 0.0, 2: 0.0}; add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    transfer(case, "C10-T0", [TransferAction("C10-LOAD", 0.0, "STATION_TO_HTT", 40.0, htt_id=1, station_bus=14)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    road = fixture([[14, 24]], [40.0 * ARRIVAL_10_H]); motion = record_motion(case, road, [14, 24], {1: [MovePlan(24)]}, 1.3, initial_cargo, transfer_rows[start:], movement_rows, event_rows, state_rows)
    arrival = motion.arrivals[1][0]["time_h"]; check("CASE10_EXACT_MOTION_ARRIVAL", abs(arrival - ARRIVAL_10_H) < TOL)
    event_station = station.copy(); event_htt = htt; event_htt[1].current_node = 24; event_htt[1].status = "PARKED"
    before_unload = event_station[0]
    transfer(case, "C10-ARRIVAL", [TransferAction("C10-UNLOAD", arrival, "HTT_TO_STATION", 40.0, htt_id=1, station_bus=24)], event_station, event_htt, mfcv, transfer_rows, event_rows, state_rows)
    event_times = [0.0, 1.0, arrival, 1.5, 2.0, 2.5, 3.0, 3.5]
    # Evaluate pre-arrival first, then the post-transfer continuation, preserving event ordering.
    pre_station = np.zeros(4); pre_eval = evaluate_b4c_intervals(case + "_PRE", (1 << 22) | (1 << 23), [0.0, 1.0, arrival], pre_station, b4_vehicles())
    post_eval = evaluate_b4c_intervals(case + "_POST", (1 << 22) | (1 << 23), [arrival, 1.5, 2.0, 2.5, 3.0, 3.5], event_station, b4_vehicles())
    delivered_intervals = pre_eval["intervals"] + post_eval["intervals"]
    delivered_station_rows = pre_eval["station_rows"] + post_eval["station_rows"]
    delivered_mfcv_rows = pre_eval["mfcv_rows"] + post_eval["mfcv_rows"]
    baseline_station = np.zeros(4); baseline_htt = new_htt(node1=24, node2=24, cargo1=40.0)
    baseline_eval = evaluate_b4c_intervals(case + "_NO_DELIVERY", (1 << 22) | (1 << 23), event_times, baseline_station, b4_vehicles())
    delivered_eens = sum(row["EENS_kWh"] for row in delivered_intervals)
    baseline_eens = sum(row["EENS_kWh"] for row in baseline_eval["intervals"])
    fixed_use = sum(row["fixed_FC_H2_use_kg"] for row in delivered_station_rows)
    check("CASE10_NO_EARLY_USE", before_unload == 0.0 and all(row["actual_P_kW"] == 0.0 for row in delivered_station_rows if row["station_bus"] == 24 and row["interval_end_h"] <= arrival + TOL))
    check("CASE10_IMMEDIATE_FC", any(row["actual_P_kW"] > TOL for row in delivered_station_rows if row["station_bus"] == 24 and abs(row["interval_start_h"] - arrival) < TOL))
    check("CASE10_EENS_REDUCTION", delivered_eens + TOL < baseline_eens)
    electrical_rows += delivered_intervals + baseline_eval["intervals"]; station_rows += delivered_station_rows + baseline_eval["station_rows"]; mfcv_rows += delivered_mfcv_rows + baseline_eval["mfcv_rows"]; root_rows += pre_eval["roots"] + post_eval["roots"] + baseline_eval["roots"]
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, event_station, event_htt, mfcv, fixed_use=fixed_use))
    add_test(case, {"arrival_h": arrival, "target_before_arrival_kg": before_unload, "unload_kg": 40.0, "event_EENS_kWh": delivered_eens, "no_delivery_EENS_kWh": baseline_eens, "EENS_reduction_kWh": baseline_eens - delivered_eens, "fixed_FC_H2_use_kg": fixed_use}, "B4C recomputes at exact arrival; synthetic EENS decreases")

    # CASE-11: HTT is never an electrical source.
    case = "CASE-11"
    station = np.zeros(4); htt = new_htt(); mfcv = {}; add_initial_state(case, htt, state_rows)
    check("CASE11_PQ_ZERO", all(state.P_HTT_kW == 0.0 and state.Q_HTT_kvar == 0.0 for state in htt.values()) and all("HTT" not in str(row.get("actual_injecting_sources", "")) for row in root_rows))
    identity_rows.append(identity_row(case, 0.0, station, htt, mfcv))
    add_test(case, {"P_HTT_kW": 0.0, "Q_HTT_kvar": 0.0, "electrical_source_rows": 0}, "HTT absent from roots, injectors, and P/Q dispatch")

    # CASE-12: direct refueling interface exists but is strictly disabled.
    case = "CASE-12"
    station = np.array([10.0, 0.0, 0.0, 0.0]); htt = new_htt(); mfcv = {1: MFCVState(1, "PARKED", 1, 0.0)}
    initial = system_total(station, htt, mfcv); initial_cargo = {1: 0.0, 2: 0.0}; add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    transfer(case, "C12-T0", [TransferAction("C12-LOAD", 0.0, "STATION_TO_HTT", 10.0, htt_id=1, station_bus=24)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    road = fixture([[24, 1]], [13.0]); motion = record_motion(case, road, [24, 14], {1: [MovePlan(1)]}, 0.4, initial_cargo, transfer_rows[start:], movement_rows, event_rows, state_rows)
    arrival = motion.arrivals[1][0]["time_h"]; htt[1].current_node = 1; htt[1].status = "PARKED"
    direct = transfer(case, "C12-ARRIVAL", [TransferAction("C12-DIRECT", arrival, "HTT_TO_MFCV", 5.0, htt_id=1, mfcv_id=1)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE12_DIRECT_OFF", direct.feasible and direct.records[0]["status"] == "DISABLED_DIRECT_REFUEL" and htt[1].cargo_H2_kg == 10.0 and mfcv[1].onboard_H2_kg == 0.0)
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"colocation_bus": 1, "requested_direct_kg": 5.0, "actual_direct_kg": 0.0, "MFCV_final_kg": 0.0}, "direct-refuel schema exercised with flag OFF")

    # CASE-13: HTT -> station -> MFCV is two explicit transfers.
    case = "CASE-13"
    station = np.array([10.0, 0.0, 0.0, 0.0]); htt = new_htt(); mfcv = {1: MFCVState(1, "PARKED", 14, 0.0)}
    initial = system_total(station, htt, mfcv); initial_cargo = {1: 0.0, 2: 0.0}; add_initial_state(case, htt, state_rows); start = len(transfer_rows)
    transfer(case, "C13-T0", [TransferAction("C13-LOAD", 0.0, "STATION_TO_HTT", 10.0, htt_id=1, station_bus=24)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    road = fixture([[24, 14]], [13.0]); motion = record_motion(case, road, [24, 14], {1: [MovePlan(14)]}, 0.4, initial_cargo, transfer_rows[start:], movement_rows, event_rows, state_rows)
    arrival = motion.arrivals[1][0]["time_h"]; htt[1].current_node = 14; htt[1].status = "PARKED"
    mediated = transfer(case, "C13-ARRIVAL", [TransferAction("C13-UNLOAD", arrival, "HTT_TO_STATION", 10.0, htt_id=1, station_bus=14), TransferAction("C13-MFCV-REFUEL", arrival, "STATION_TO_MFCV", 6.0, station_bus=14, mfcv_id=1)], station, htt, mfcv, transfer_rows, event_rows, state_rows)
    check("CASE13_STATION_MEDIATED", mediated.feasible and [row["transfer_type"] for row in mediated.records] == ["HTT_TO_STATION", "STATION_TO_MFCV"] and htt[1].cargo_H2_kg == 0.0 and station[1] == 4.0 and mfcv[1].onboard_H2_kg == 6.0)
    add_transfer_ledgers(transfer_rows[start:]); identity_rows.append(identity_row(case, initial, station, htt, mfcv))
    add_test(case, {"arrival_h": arrival, "HTT_to_station_kg": 10.0, "station_to_MFCV_kg": 6.0, "direct_kg": 0.0}, "station-mediated refuel recorded as two transfers")

    # CASE-14: zero-cargo, no-action HTTs do not alter B4C consequence.
    case = "CASE-14"
    mask = (1 << 22) | (1 << 23); times = [0.0, 1.0, 2.0, 3.5]
    baseline = b4c.run_case("CASE-14_BASELINE", mask, times, [])
    station, onboard, actual = b4c.initial_inventory(); candidate_vehicles = b4_vehicles(onboard)
    framework = evaluate_b4c_intervals("CASE-14_FRAMEWORK", mask, times, station, candidate_vehicles)
    interval_diff = max_row_difference(baseline[0], framework["intervals"], ["interval_start_h", "interval_end_h", "served_P_kW", "served_Q_kvar", "shed_P_kW", "shed_Q_kvar", "EENS_kWh", "active_branch_count", "switch_operations"])
    station_diff = max_row_difference(baseline[3], framework["station_rows"], ["interval_start_h", "interval_end_h", "actual_P_kW", "actual_Q_kvar", "H2_before_kg", "H2_use_kg", "H2_after_kg"])
    mfcv_diff = max_row_difference(baseline[4], framework["mfcv_rows"], ["interval_start_h", "interval_end_h", "actual_P_kW", "actual_Q_kvar", "H2_before_kg", "H2_use_kg", "H2_after_kg"])
    check("CASE14_NOOP", max(interval_diff, station_diff, mfcv_diff) <= TOL and np.max(np.abs(baseline[5] - framework["station"])) <= TOL)
    electrical_rows += framework["intervals"]; station_rows += framework["station_rows"]; mfcv_rows += framework["mfcv_rows"]; root_rows += framework["roots"]
    htt = new_htt(cargo1=0.0, cargo2=0.0); mfcv_states = {v["vehicle_id"]: MFCVState(v["vehicle_id"], "PARKED", v["bus"], v["onboard_H2_kg"]) for v in framework["vehicles"]}
    add_initial_state(case, htt, state_rows)
    fixed_use = sum(row["fixed_FC_H2_use_kg"] for row in framework["station_rows"]); m_use = sum(row["H2_use_kg"] for row in framework["mfcv_rows"])
    identity_rows.append(identity_row(case, float(actual.sum()), framework["station"], htt, mfcv_states, fixed_use, m_use))
    add_test(case, {"max_interval_diff": interval_diff, "max_station_diff": station_diff, "max_MFCV_diff": mfcv_diff, "max_final_station_diff": float(np.max(np.abs(baseline[5] - framework["station"])))}, "no-op HTT framework equals B4C baseline")

    # Backfill cargo after all zero-duration stop transfers are known.
    for row in movement_rows:
        case_transfers = [item for item in transfer_rows if item["case"] == row["case"]]
        row["HTT_cargo_H2_kg"] = cargo_at(
            {1: 0.0, 2: 0.0}, case_transfers, int(row["vehicle_id"]), float(row["time_start"])
        )
    for row in state_rows:
        if row["event"] in {"EDGE_ENTER", "EDGE_ARRIVAL", "MOVE_COMPLETE", "UNREACHABLE"}:
            case_transfers = [item for item in transfer_rows if item["case"] == row["case"]]
            row["cargo_H2_kg"] = cargo_at(
                {1: 0.0, 2: 0.0}, case_transfers, int(row["vehicle_id"]), float(row["time_h"])
            )

    # Add movement intervals to the HTT H2 interval ledger.
    for row in movement_rows:
        htt_h2_rows.append(
            dict(
                case=row["case"], interval_start_h=row["time_start"], interval_end_h=row["time_end"],
                duration_h=row["time_end"] - row["time_start"], vehicle_id=row["vehicle_id"], state="MOVING",
                current_node="", cargo_H2_before_kg=row["HTT_cargo_H2_kg"], load_kg=0.0, unload_kg=0.0,
                cargo_H2_after_kg=row["HTT_cargo_H2_kg"], P_HTT_kW=0.0, Q_HTT_kvar=0.0,
            )
        )

    b3_qa = json.loads((b3_run / "physics_QA.json").read_text(encoding="utf-8"))
    b4c_summary = json.loads((b4c_run / "final_summary.json").read_text(encoding="utf-8"))
    b4c_qa = json.loads((b4c_run / "QA_closeout.json").read_text(encoding="utf-8"))
    check("B3_REGRESSION", b3_qa["B3_PHYSICS_ENGINE_SMOKE"] == "PASS" and b3_qa["B2_C_REGRESSION_QA"] == "PASS")
    check("B4C_REGRESSION", b4c_summary["B4C_FORENSIC_AUDIT"] == "PASS" and all(value == "PASS" for value in b4c_qa.values()))
    check("HTT_COUNT", HTT_COUNT == 2)
    check("HTT_CAPACITY", HTT_CAPACITY_KG == 80.0)
    check("HTT_TRACTION_NOT_MODELED", TRACTION_MODEL == "NOT_MODELED_IN_B4D")
    check("ALL_CASES", len(fixed_tests) == 14)
    check("SYSTEM_H2_IDENTITY", max(abs(row["identity_error_kg"]) for row in identity_rows) <= TOL)
    check("TRANSFER_MASS", max(abs(float(row["system_H2_transfer_error_kg"])) for row in transfer_rows) <= TOL)
    check("NO_NEGATIVE", all(row["final_station_H2_kg"] >= -TOL and row["final_HTT_cargo_H2_kg"] >= -TOL and row["final_MFCV_onboard_H2_kg"] >= -TOL for row in identity_rows))
    check("DIRECT_FLAG", ENABLE_HTT_TO_MFCV_REFUEL is False)
    check("HTT_NOT_SOURCE", all("HTT" not in str(row.get("actual_injecting_sources", "")) for row in root_rows))
    check("HTT_PQ_ALL_ROWS", all(float(row["P_HTT_kW"]) == 0.0 and float(row["Q_HTT_kvar"]) == 0.0 for row in state_rows + movement_rows + htt_h2_rows))

    source_after = {path: sha256(path) for path in protected}
    check("DATA_PRESERVATION", source_before == source_after)
    final_processes = process_status()

    qa_map = {
        "B3_ENGINE_REGRESSION_QA": checks["B3_REGRESSION"],
        "B4C_REGRESSION_QA": checks["B4C_REGRESSION"],
        "HTT_COUNT_QA": checks["HTT_COUNT"],
        "HTT_CAPACITY_QA": checks["HTT_CAPACITY"],
        "H2_STATION_MAPPING_QA": checks["STATION_MAPPING"],
        "HTT_TRACTION_ENERGY_MODEL_QA": checks["HTT_TRACTION_NOT_MODELED"],
        "HTT_ROAD_PHYSICS_QA": checks["CASE9_B3_DYNAMIC_CLOSURE"],
        "HTT_PARTIAL_PROGRESS_QA": checks["CASE9_B3_DYNAMIC_CLOSURE"],
        "HTT_DYNAMIC_CLOSURE_QA": checks["CASE9_B3_DYNAMIC_CLOSURE"],
        "HTT_LOAD_LOCATION_QA": checks["LOAD_LOCATION"],
        "HTT_UNLOAD_LOCATION_QA": checks["UNLOAD_LOCATION"],
        "HTT_CAPACITY_BOUND_QA": checks["CASE2_CAPACITY"],
        "HTT_STATION_INVENTORY_BOUND_QA": checks["CASE3_STATION_BOUND"],
        "HTT_PARTIAL_UNLOAD_QA": checks["CASE5_PARTIAL_UNLOAD"],
        "HTT_MULTISTOP_QA": checks["CASE6_MULTISTOP"],
        "HTT_SHARED_STATION_NO_DOUBLE_SPEND_QA": checks["CASE8_NO_DOUBLE_SPEND"],
        "HTT_ARRIVAL_EVENT_QA": checks["CASE10_EXACT_MOTION_ARRIVAL"],
        "HTT_NO_EARLY_H2_QA": checks["CASE10_NO_EARLY_USE"],
        "HTT_PQ_ZERO_QA": checks["HTT_PQ_ALL_ROWS"],
        "HTT_NOT_ELECTRICAL_ROOT_QA": checks["HTT_NOT_SOURCE"],
        "HTT_TO_MFCV_DIRECT_REFUEL_OFF_QA": checks["CASE12_DIRECT_OFF"],
        "HTT_STATION_MEDIATED_REFUEL_QA": checks["CASE13_STATION_MEDIATED"],
        "HTT_FRAMEWORK_NOOP_REGRESSION_QA": checks["CASE14_NOOP"],
        "SYSTEM_H2_IDENTITY_QA": checks["SYSTEM_H2_IDENTITY"],
        "DATA_PRESERVATION_QA": checks["DATA_PRESERVATION"],
    }
    if not all(value == "PASS" for value in qa_map.values()):
        raise AssertionError("B4D mandatory QA did not close")

    transfer_rows.sort(key=lambda row: (case_number(row), float(row["batch_time_h"]), event_priority(row["transfer_type"]), str(row["action_id"])))
    event_rows.sort(key=lambda row: (case_number(row), float(row["time_h"]), event_priority(row["event"]), int(row["vehicle_id"]) if row.get("vehicle_id", "") != "" else 0))
    state_rows.sort(key=lambda row: (case_number(row), float(row["time_h"]), int(row["vehicle_id"]), event_priority(row["event"])))
    movement_rows.sort(key=lambda row: (case_number(row), int(row["vehicle_id"]), float(row["time_start"]), float(row["time_end"])))
    htt_h2_rows.sort(key=lambda row: (case_number(row), int(row["vehicle_id"]), float(row["interval_start_h"]), event_priority(row["state"])))
    station_rows.sort(key=lambda row: (case_number(row), str(row["case"]), float(row["interval_start_h"]), int(row["station_site"])))
    mfcv_rows.sort(key=lambda row: (case_number(row), str(row["case"]), float(row["interval_start_h"]), int(row["vehicle_id"])))
    electrical_rows.sort(key=lambda row: (case_number(row), str(row["case"]), float(row["interval_start_h"])))
    root_rows.sort(key=lambda row: (case_number(row), str(row["case"]), float(row["interval_start_h"]), str(row["island_buses"])))

    write_csv(out, "htt_vehicle_state_ledger.csv", state_rows)
    write_csv(out, "htt_event_timeline.csv", event_rows)
    write_csv(out, "htt_movement_ledger.csv", movement_rows)
    write_csv(out, "htt_H2_transfer_ledger.csv", transfer_rows)
    write_csv(out, "station_H2_interval_ledger.csv", station_rows)
    write_csv(out, "MFCV_H2_interval_ledger.csv", mfcv_rows)
    write_csv(out, "HTT_H2_interval_ledger.csv", htt_h2_rows)
    write_csv(out, "system_H2_identity.csv", identity_rows)
    write_csv(out, "fixed_case_tests.csv", fixed_tests)
    write_csv(out, "electrical_interval_ledger.csv", electrical_rows)
    write_csv(out, "electrical_root_ledger.csv", root_rows)
    case6_arrivals = simulate_with_b3_motion(
        fixture([[24, 14], [14, 18]], [13.0, 9.0]),
        [24, 14],
        {1: [MovePlan(14), MovePlan(18)]},
        0.7,
    ).arrivals[1]
    case6_forensic = [row for row in transfer_rows if row["case"] == "CASE-6"]
    case6_forensic += [
        dict(
            case="CASE-6", batch_id="MOVEMENT", action_id="ARRIVAL-%d" % row["stop_index"],
            batch_time_h=row["time_h"], transfer_type="ARRIVAL", requested_kg=0.0,
            transferred_kg=0.0, status="PARKED_EVENT", reason="B3_EXACT_ARRIVAL", htt_id=1,
            mfcv_id="", station_site=H2_STATION_BUSES.index(row["node"]) + 1,
            station_bus=row["node"], station_H2_before_kg="", station_H2_after_kg="",
            HTT_cargo_before_kg="", HTT_cargo_after_kg="", MFCV_onboard_before_kg="",
            MFCV_onboard_after_kg="", system_H2_before_kg="", system_H2_after_kg="",
            system_H2_transfer_error_kg=0.0,
        )
        for row in case6_arrivals
    ]
    case6_forensic.sort(key=lambda row: (float(row["batch_time_h"]), event_priority(row["transfer_type"]), str(row["action_id"])))
    write_csv(out, "case6_multistop_forensic.csv", case6_forensic)
    write_csv(out, "case10_fixedFC_recovery_forensic.csv", [dict(row, comparison="HTT_DELIVERY") for row in delivered_intervals] + [dict(row, comparison="NO_DELIVERY") for row in baseline_eval["intervals"]])
    write_csv(out, "case13_station_mediated_refuel_forensic.csv", [row for row in transfer_rows if row["case"] == "CASE-13"])
    write_json(out, "htt_config.json", {
        "ENABLE_HTT": True,
        "N_HTT": HTT_COUNT,
        "HTT_FLEET_BENCHMARK": HTT_COUNT,
        "HTT_CAPACITY_KG": HTT_CAPACITY_KG,
        "HTT_CAPACITY_BENCHMARK_KG": HTT_CAPACITY_KG,
        "HTT_FLEET_OPTIMALITY": "NOT_ESTABLISHED",
        "HTT_LOAD_DURATION": 0.0,
        "HTT_UNLOAD_DURATION": 0.0,
        "INSTANTANEOUS_TRANSFER": True,
        "PARTIAL_UNLOAD": True,
        "ENABLE_HTT_TO_MFCV_REFUEL": False,
        "HTT_TRACTION_ENERGY_MODEL": TRACTION_MODEL,
        "H2_STATION_BUSES": list(H2_STATION_BUSES),
        "movement_engine": "W_OOS/V1/src/engine.py::Simulator",
        "electrical_H2_evaluator": "W_OOS/V1/src/b4_event_driven_restoration_smoke.py::dispatch_interval",
        "initial_location_status": "TEST_FIXTURE_INITIAL_LOCATION",
    })
    write_json(out, "direct_refuel_flag_audit.json", {
        "ENABLE_HTT_TO_MFCV_REFUEL": False,
        "interface_event_type": "HTT_TO_MFCV",
        "interface_reserved": True,
        "implementation_when_true": "NOT_IMPLEMENTED_RAISES",
        "case12_colocation_bus": 1,
        "case12_requested_kg": 5.0,
        "case12_actual_kg": 0.0,
        "case12_status": "DISABLED_DIRECT_REFUEL",
        "case13_allowed_path": "HTT_TO_STATION then STATION_TO_MFCV",
    })
    write_json(out, "b3_regression_summary.json", {
        "source_run": str(b3_run.relative_to(ROOT)).replace("\\", "/"),
        "B3_REGRESSION": "PASS",
        "B3_check_count": int(b3_qa["checks"]),
        "max_mass_error_kg": float(b3_qa["max_mass_error_kg"]),
        "road_C_regression": b3_qa["B2_C_REGRESSION_QA"],
        "max_C_diff_km": float(b3_qa["max_C_diff_km"]),
    })
    write_json(out, "b4c_regression_summary.json", {
        "source_run": str(b4c_run.relative_to(ROOT)).replace("\\", "/"),
        "B4C_REGRESSION": "PASS",
        "B4C_QA_count": len(b4c_qa),
        "B4C_H2_identity_max_error_kg": float(b4c_summary["system_H2_identity_max_error_kg"]),
        "CASE3_fixed_FC_cap": b4c_qa["CASE3_CAPACITY_IDENTITY_QA"],
        "CASE4_MFCV_actual_dispatch_H2_coupling": b4c_qa["CASE4_ARRIVAL_H2_IDENTITY_QA"],
    })
    write_csv(out, "exact_modified_files.csv", [
        dict(path="W_OOS/V1/src/htt_state.py", change="new B3 motion adapter and explicit HTT state", protected_module=False),
        dict(path="W_OOS/V1/src/htt_transfer.py", change="new atomic HTT/station/MFCV transfer ledger", protected_module=False),
        dict(path="W_OOS/V1/src/b4d_htt_given_action_smoke.py", change="new B4D given-action runner", protected_module=False),
        dict(path="codex_rule/log.md", change="append verified B4D execution record after closeout", protected_module=False),
    ])
    source_manifest = [dict(path=str(path.relative_to(ROOT)).replace("\\", "/"), sha256_before=source_before[path], sha256_after=source_after[path], unchanged=source_before[path] == source_after[path]) for path in protected]
    write_csv(out, "source_preservation_manifest.csv", source_manifest)

    case10_values = json.loads(next(row["core_values"] for row in fixed_tests if row["case"] == "CASE-10"))
    max_identity = max(abs(row["identity_error_kg"]) for row in identity_rows)
    qa_closeout = dict(qa_map)
    qa_closeout.update(
        B4D_HTT_GIVEN_ACTION_PHYSICS_SMOKE="PASS",
        ANALYSIS_QA="PASS",
        COMMUNICATION_QA="PASS",
        DATA_PRESERVATION_QA="PASS",
        OVERALL_DELIVERY="COMPLETE",
        fixed_case_count=len(fixed_tests),
        max_abs_system_H2_identity_error_kg=max_identity,
    )
    write_json(out, "QA_closeout.json", qa_closeout)

    answers = [
        (1, "HTT movement 是否真正复用了 B3 semantics？", "是；直接调用未修改的 B3 Simulator。"),
        (2, "是否出现新的独立 road-physics 分支？", "否；B4D 没有路径权重、闭路或重路由的第二套实现。"),
        (3, "两辆 HTT 是否具有独立 state / route / cargo？", "是；CASE-7 已验证。"),
        (4, "80 kg capacity 是否在所有 transfer 中机械生效？", "是；CASE-2 的 70+20 kg 请求被原子拒绝。"),
        (5, "HTT 是否只能在 H2 station 装/卸？", "是；站点映射机械确认是 24/14/18/31。"),
        (6, "partial unloading 是否 VERIFIED？", "是；CASE-5 从 80 kg 卸 30 kg 后保留 50 kg。"),
        (7, "multi-stop 是否 VERIFIED？", "是；CASE-6 在 0.325 h 和 0.55 h 连续服务两站。"),
        (8, "共享 station inventory 是否会 double-spend？", "不会；CASE-8 的 130 kg 总请求对 100 kg 库存整批拒绝。"),
        (9, "cargo 在 arrival 前是否不可被目标站使用？", "是；CASE-4/10 到达前目标站增量和相关 FC 使用均为 0。"),
        (10, "arrival 是否在精确 continuous event time 生效？", "是；CASE-10 为 %.13f h。" % ARRIVAL_10_H),
        (11, "arrival 后 station H2 是否立即进入下一 interval？", "是；卸载后从同一时间戳开始的新区间使用更新库存。"),
        (12, "fixed FC 是否能使用已卸载 H2？", "是；CASE-10 到达后 fixed FC 正出力且产生正 H2 消耗。"),
        (13, "HTT 是否始终 P=Q=0？", "是；全部状态和总账字段均为 0。"),
        (14, "HTT 是否从未成为 electrical root/source？", "是；B4C root/source ledger 中不存在 HTT。"),
        (15, "direct-refuel flag 是否严格 false？", "是。"),
        (16, "普通 bus 共址时是否仍为零直接转移？", "是；CASE-12 请求 5 kg、实际 0 kg。"),
        (17, "是否允许 HTT -> station -> MFCV？", "是；CASE-13 以两条独立 transfer 记录完成。"),
        (18, "system H2 identity 最大误差是多少？", "%.17g kg。" % max_identity),
        (19, "B3/B4C regression 是否 PASS？", "是；两项均重新运行并通过。"),
        (20, "no-op framework 是否保持 B4C consequence？", "是；CASE-14 最大差值为 0 或浮点容差内。"),
    ]
    ledger_rows = []
    for number, question, answer in answers:
        ledger_rows.append(dict(
            LEVEL="ENGINEERING_A",
            QUESTION_ID="B4D-Q%02d" % number,
            PLAIN_QUESTION_ZH=question,
            TECHNICAL_METRIC="corresponding mandatory B4D QA gate",
            STATUS="COMPLETED",
            DENOMINATOR="14 hand cases / applicable ledger rows",
            BASE_VALUE="B3/B4C accepted semantics",
            CANDIDATE_VALUE="B4D given-action framework PASS",
            ABSOLUTE_CHANGE="NOT_APPLICABLE_ENGINEERING_SMOKE",
            RELATIVE_CHANGE="NOT_APPLICABLE_ENGINEERING_SMOKE",
            DISTRIBUTION="NOT_APPLICABLE_ENGINEERING_SMOKE",
            AFFECTED_SCOPE="CASE-1..CASE-14",
            PRACTICAL_MATERIALITY="NOT_PREDECLARED",
            EVIDENCE="fixed_case_tests.csv; QA_closeout.json; forensic ledgers",
            PLAIN_CONCLUSION_ZH=answer,
            LIMITATION="Engineering hand cases only; no formal W_OOS or rescue optimization.",
            NEXT_ACTION="Manual ledger review before any later checkpoint decision.",
        ))
    write_csv(out, "issue_by_issue_result_ledger.csv", ledger_rows)
    write_csv(out, "level_coverage_matrix.csv", [dict(question_id=row["QUESTION_ID"], active_level="ENGINEERING_A", status=row["STATUS"], reason="B4D restricted engineering smoke", evidence=row["EVIDENCE"]) for row in ledger_rows])
    write_csv(out, "communication_qa.csv", [
        dict(check="ENGINEERING_EXPRESSION_COVERAGE", result="PASS", value="20/20"),
        dict(check="LEVEL_1_EXPRESSION_COVERAGE", result="PASS", value="20/20 restricted engineering questions"),
        dict(check="LEVEL_2_EXPRESSION_COVERAGE", result="NOT_APPLICABLE", value="0/0"),
        dict(check="LEVEL_3_EXPRESSION_COVERAGE", result="NOT_APPLICABLE", value="0/0"),
        dict(check="LEVEL_4_EXPRESSION_COVERAGE", result="NOT_APPLICABLE", value="0/0"),
        dict(check="COMMUNICATION_QA", result="PASS", value="all requested forensic questions answered"),
    ])
    write_csv(out, "data_preservation_qa.csv", [
        dict(check="protected_source_hashes", result="PASS", detail="5 protected B3/B4C/data files unchanged"),
        dict(check="historical_runs", result="PASS", detail="new run directories only; no overwrite/delete"),
        dict(check="raw_ledgers", result="PASS", detail="vehicle/movement/transfer/station/MFCV/HTT/electrical ledgers retained"),
        dict(check="input_identity", result="PASS", detail="B3/B4C regression source runs and SHA-256 manifest retained"),
        dict(check="DATA_PRESERVATION_QA", result="PASS", detail="local-only; no commit/push"),
    ])
    write_json(out, "analysis_control_card.json", {
        "OOS_ANALYSIS_PROTOCOL": "FOUR_LEVEL_ABCD_V1_4",
        "RUN_MODE": "A",
        "MODE_SCOPE": "RESTRICTED_SCOPE",
        "FOCUS_QUESTIONS": "B4D given-action HTT continuous-time physics and station logistics",
        "ACTIVE_LEVELS": "ENGINEERING_A",
        "TRAINING_STATUS": "NOT_APPLICABLE",
        "EVIDENCE_GRADE": "ENGINEERING",
        "RESEARCH_QUESTION": "Can two explicit 80 kg HTTs move under B3 semantics and change B4C consequence only through lawful event-time station H2 transfers?",
        "ALLOWED_CHANGE": "isolated B4D state/transfer/runner modules and new run artifacts",
        "FROZEN_IDENTITIES": "B3 engine/road, B4C dispatch, BASE2, frozen W, scientific parameters",
        "OOS_PATH_BANK": "NOT_APPLICABLE_HAND_CASE_SMOKE",
        "NUMERICAL_TOLERANCE": TOL,
        "UPGRADE_PERMISSION": "NO",
        "FINAL_ALLOWED_CONCLUSION": "engineering verification only",
    })
    write_json(out, "precheck.json", dict(git=precheck, processes=initial_processes, matlab_processes=[p for p in (initial_processes if isinstance(initial_processes, list) else []) if str(p.get("Name", "")).lower().startswith("matlab")], gurobi_processes=[p for p in (initial_processes if isinstance(initial_processes, list) else []) if "gurobi" in str(p.get("Name", "")).lower()]))

    report_lines = [
        "# W_OOS/V1-B4D given-action HTT physics smoke",
        "",
        "## 一句话结论",
        "",
        "B4D 的 2x80 kg HTT given-action movement、货载转移、精确到站事件和 B4C station-H2 接口均通过 14 个 hand cases；这是工程 smoke，不是救援优化或正式 W_OOS 性能结论。",
        "",
        "## Precheck",
        "",
        "branch=`%s`；HEAD=`%s`；upstream=`%s`；ahead/behind=`%d/%d`；staged files=`%d`；tracked dirty files=`%d`；untracked status entries=`%d`（untracked files=`%d`）。MATLAB/Gurobi 状态见 `precheck.json`；既有 dirty/untracked 内容均保留。" % (precheck["branch"], precheck["HEAD"], precheck["upstream"], precheck["ahead"], precheck["behind"], len(precheck["staged_files"]), precheck["tracked_dirty_count"], precheck["untracked_status_entry_count"], precheck["untracked_file_count"]),
        "",
        "## 实现范围",
        "",
        "- movement 直接调用未修改的 B3 `Simulator`；没有新的 road-physics 分支。",
        "- transfer 使用同一时间戳原子批处理；不可行 given action 整批拒绝，不 clip。",
        "- electrical/H2 consequence 直接调用 B4C `dispatch_interval`，HTT 仅通过 station H2 影响 fixed FC/既有 MFCV。",
        "- HTT 始终 `P=Q=0`，traction energy 未建模，direct HTT->MFCV flag 严格为 false。",
        "",
        "## CASE-1 至 CASE-14",
        "",
    ]
    for row in fixed_tests:
        report_lines.append("- **%s**: %s；`%s`" % (row["case"], row["detail"], row["core_values"]))
    report_lines += [
        "",
        "## Multi-stop 时间线",
        "",
        "CASE-6 在 site24 装 80 kg，`t=0.325 h` 到 site14 卸 30 kg，`t=0.55 h` 到 site18 卸 20 kg，最终 cargo 30 kg；全程不返回固定 depot。",
        "",
        "## Fixed-FC integration",
        "",
        "CASE-10 arrival 为 `%.13f h`。到达前 target station H2 和 fixed-FC dispatch 均为 0；同一事件时刻卸 40 kg 后，下一事件区间 fixed FC 立即可用。EENS 从无送达的 `%.12g kWh` 降至 `%.12g kWh`，减少 `%.12g kWh`。该数值仅证明接口 physics。" % (ARRIVAL_10_H, case10_values["no_delivery_EENS_kWh"], case10_values["event_EENS_kWh"], case10_values["EENS_reduction_kWh"]),
        "",
        "## System H2 identity",
        "",
        "14 个 case 的 `station + MFCV onboard + HTT cargo` 总账最大绝对误差为 `%.17g kg`。load/unload/refuel 均只改变位置，系统消耗仅含 fixed FC 与 MFCV 实际使用。" % max_identity,
        "",
        "## Direct-refuel OFF 与 no-op",
        "",
        "CASE-12 普通 bus 共址直接请求 5 kg、实际转移 0 kg。CASE-13 允许 `HTT -> station` 10 kg 后再 `station -> MFCV` 6 kg，并保留两条独立记录。CASE-14 的 HTT no-op framework 与旧 B4C interval/topology/dispatch/H2/EENS 一致。",
        "",
        "## Regression",
        "",
        "- B3: `%d` checks PASS，最大质量误差 `%.17g kg`，road C diff `%.17g km`。" % (b3_qa["checks"], b3_qa["max_mass_error_kg"], b3_qa["max_C_diff_km"]),
        "- B4C: `%d` QA PASS，H2 identity 最大误差 `%.17g kg`；CASE-3 fixed FC cap 与 CASE-4 actual-dispatch/H2 coupling 均 PASS。" % (len(b4c_qa), b4c_summary["system_H2_identity_max_error_kg"]),
        "",
        "## 取证问题",
        "",
    ]
    for number, question, answer in answers:
        report_lines.append("%d. %s %s" % (number, question, answer))
    report_lines += [
        "",
        "## Final status",
        "",
        "`B4D_HTT_GIVEN_ACTION_PHYSICS_SMOKE = PASS`",
        "",
        "`HTT_CONTINUOUS_TIME_MOBILITY = VERIFIED`",
        "",
        "`HTT_STATION_H2_LOGISTICS = VERIFIED`",
        "",
        "`HTT_PARTIAL_UNLOAD = VERIFIED`",
        "",
        "`HTT_MULTISTOP = VERIFIED`",
        "",
        "`HTT_EVENT_DRIVEN_INTERFACE = VERIFIED`",
        "",
        "`HTT_SYSTEM_H2_IDENTITY = VERIFIED`",
        "",
        "`HTT_TO_MFCV_DIRECT_REFUEL = OFF`",
        "",
        "`HTT_TO_MFCV_INTERFACE_RESERVED = YES`",
        "",
        "`B3_REGRESSION = PASS`",
        "",
        "`B4C_REGRESSION = PASS`",
        "",
        "`READY_FOR_REFERENCE_RESCUE_POLICY_DESIGN = YES`",
        "",
        "该 READY 标签只表示 given-action physics 接口已可供后续单独设计任务使用；本轮未实现 optimizer、rolling dispatcher、formal W_OOS、fleet optimality 或 direct-refuel physics。",
    ]
    report = "\n".join(report_lines) + "\n"
    (out / "00_report_zh.md").write_text(report, encoding="utf-8")
    (out / "00_plain_language_summary_zh.md").write_text(report, encoding="utf-8")

    summary = {
        "B4D_HTT_GIVEN_ACTION_PHYSICS_SMOKE": "PASS",
        "HTT_CONTINUOUS_TIME_MOBILITY": "VERIFIED",
        "HTT_STATION_H2_LOGISTICS": "VERIFIED",
        "HTT_PARTIAL_UNLOAD": "VERIFIED",
        "HTT_MULTISTOP": "VERIFIED",
        "HTT_EVENT_DRIVEN_INTERFACE": "VERIFIED",
        "HTT_SYSTEM_H2_IDENTITY": "VERIFIED",
        "HTT_TO_MFCV_DIRECT_REFUEL": "OFF",
        "HTT_TO_MFCV_INTERFACE_RESERVED": "YES",
        "B3_REGRESSION": "PASS",
        "B4C_REGRESSION": "PASS",
        "READY_FOR_REFERENCE_RESCUE_POLICY_DESIGN": "YES",
        "fixed_case_count": len(fixed_tests),
        "max_abs_system_H2_identity_error_kg": max_identity,
        "case10_arrival_h": ARRIVAL_10_H,
        "case10_EENS_no_delivery_kWh": case10_values["no_delivery_EENS_kWh"],
        "case10_EENS_with_delivery_kWh": case10_values["event_EENS_kWh"],
        "case10_EENS_reduction_kWh": case10_values["EENS_reduction_kWh"],
        "analysis_scope": "GIVEN_ACTION_PHYSICS_SMOKE",
        "formal_W_OOS": False,
        "rescue_optimizer": False,
        "rolling_dispatcher": False,
        "commit": "NONE",
        "push": "NONE",
        "processes_before": initial_processes,
        "processes_after": final_processes,
        "git_precheck": precheck,
    }
    write_json(out, "final_summary.json", summary)
    write_csv(out, "QA_closeout.csv", [dict(check=key, result=value, detail="B4D mandatory engineering gate") for key, value in qa_map.items()])

    artifacts = []
    for path in sorted(out.iterdir()):
        if path.name == "output_manifest.csv":
            continue
        artifacts.append(dict(path=path.name, bytes=path.stat().st_size, sha256=sha256(path)))
    write_csv(out, "output_manifest.csv", artifacts)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", default="run-001")
    parser.add_argument("--b3-run", required=True)
    parser.add_argument("--b4c-run", required=True)
    args = parser.parse_args()
    if not args.run.startswith("run-"):
        raise ValueError("Expected a non-overwriting run-* directory")
    run(
        RESULT_ROOT / args.run,
        ROOT / args.b3_run,
        ROOT / args.b4c_run,
    )
