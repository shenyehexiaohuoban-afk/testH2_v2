"""Atomic station/vehicle hydrogen transfers for B4D given actions."""
from dataclasses import dataclass
from typing import Dict, List, Optional

import numpy as np

from htt_state import HTT_CAPACITY_KG, HTTState


H2_STATION_BUSES = (24, 14, 18, 31)
MFCV_CAPACITY_KG = 66.6
ENABLE_HTT_TO_MFCV_REFUEL = False
TOL = 1e-9


@dataclass
class MFCVState:
    vehicle_id: int
    status: str
    current_node: int
    onboard_H2_kg: float

    def __post_init__(self):
        if self.status not in {"PARKED", "SERVICE", "MOVING"}:
            raise ValueError("Invalid MFCV state")
        if not np.isfinite(self.onboard_H2_kg) or not 0.0 <= self.onboard_H2_kg <= MFCV_CAPACITY_KG:
            raise ValueError("Invalid MFCV onboard H2")


@dataclass(frozen=True)
class TransferAction:
    action_id: str
    time_h: float
    kind: str
    quantity_kg: float
    htt_id: Optional[int] = None
    station_bus: Optional[int] = None
    mfcv_id: Optional[int] = None


@dataclass
class TransferBatchResult:
    feasible: bool
    reason: str
    records: List[dict]


def _system_total(station, cargo, onboard):
    return float(np.sum(station) + sum(cargo.values()) + sum(onboard.values()))


def _failure_records(actions, station, cargo, onboard, reason):
    total = _system_total(station, cargo, onboard)
    records = []
    for action in actions:
        site = "" if action.station_bus not in H2_STATION_BUSES else H2_STATION_BUSES.index(action.station_bus) + 1
        records.append(
            dict(
                action_id=action.action_id,
                batch_time_h=float(action.time_h),
                transfer_type=action.kind,
                requested_kg=float(action.quantity_kg),
                transferred_kg=0.0,
                status="INFEASIBLE_GIVEN_ACTION",
                reason=reason,
                htt_id="" if action.htt_id is None else action.htt_id,
                mfcv_id="" if action.mfcv_id is None else action.mfcv_id,
                station_site=site,
                station_bus="" if action.station_bus is None else action.station_bus,
                station_H2_before_kg="" if site == "" else float(station[site - 1]),
                station_H2_after_kg="" if site == "" else float(station[site - 1]),
                HTT_cargo_before_kg="" if action.htt_id is None else float(cargo[action.htt_id]),
                HTT_cargo_after_kg="" if action.htt_id is None else float(cargo[action.htt_id]),
                MFCV_onboard_before_kg="" if action.mfcv_id is None else float(onboard[action.mfcv_id]),
                MFCV_onboard_after_kg="" if action.mfcv_id is None else float(onboard[action.mfcv_id]),
                system_H2_before_kg=total,
                system_H2_after_kg=total,
                system_H2_transfer_error_kg=0.0,
            )
        )
    return records


def apply_transfer_batch(
    actions: List[TransferAction],
    station_inventory_kg: np.ndarray,
    htt_states: Dict[int, HTTState],
    mfcv_states: Dict[int, MFCVState],
    enable_direct_refuel: bool = ENABLE_HTT_TO_MFCV_REFUEL,
) -> TransferBatchResult:
    """Validate a timestamp batch on copies and commit it atomically."""
    if not actions:
        raise ValueError("Transfer batch must not be empty")
    if enable_direct_refuel:
        raise NotImplementedError("HTT-to-MFCV direct-refuel physics is reserved but not implemented in B4D")
    event_time = float(actions[0].time_h)
    if any(abs(float(action.time_h) - event_time) > TOL for action in actions):
        raise ValueError("All actions in a transfer batch must share one event timestamp")
    station = np.asarray(station_inventory_kg, dtype=float)
    if station.shape != (4,) or not np.isfinite(station).all() or np.any(station < -TOL):
        raise ValueError("Invalid four-station inventory")

    temp_station = station.copy()
    temp_cargo = {vehicle_id: float(state.cargo_H2_kg) for vehicle_id, state in htt_states.items()}
    temp_onboard = {vehicle_id: float(state.onboard_H2_kg) for vehicle_id, state in mfcv_states.items()}
    records = []
    allowed = {"STATION_TO_HTT", "HTT_TO_STATION", "STATION_TO_MFCV", "HTT_TO_MFCV"}

    try:
        for action in actions:
            if action.kind not in allowed:
                raise ValueError("UNKNOWN_TRANSFER_TYPE")
            if not np.isfinite(action.quantity_kg) or action.quantity_kg < 0.0:
                raise ValueError("INVALID_TRANSFER_QUANTITY")
            if action.htt_id is not None and action.htt_id not in htt_states:
                raise ValueError("UNKNOWN_HTT")
            if action.mfcv_id is not None and action.mfcv_id not in mfcv_states:
                raise ValueError("UNKNOWN_MFCV")

            htt = None if action.htt_id is None else htt_states[action.htt_id]
            mfcv = None if action.mfcv_id is None else mfcv_states[action.mfcv_id]
            site = None if action.station_bus not in H2_STATION_BUSES else H2_STATION_BUSES.index(action.station_bus)
            system_before = _system_total(temp_station, temp_cargo, temp_onboard)
            station_before = "" if site is None else float(temp_station[site])
            cargo_before = "" if htt is None else float(temp_cargo[action.htt_id])
            onboard_before = "" if mfcv is None else float(temp_onboard[action.mfcv_id])
            status = "TRANSFERRED"
            transferred = float(action.quantity_kg)

            if action.kind == "HTT_TO_MFCV":
                if htt is None or mfcv is None or htt.status != "PARKED" or mfcv.status != "PARKED":
                    raise ValueError("DIRECT_REFUEL_REQUIRES_PARKED_VEHICLES")
                if htt.current_node != mfcv.current_node:
                    raise ValueError("DIRECT_REFUEL_REQUIRES_COLOCATION")
                status = "DISABLED_DIRECT_REFUEL"
                transferred = 0.0
            elif action.kind in {"STATION_TO_HTT", "HTT_TO_STATION"}:
                if htt is None or site is None:
                    raise ValueError("HTT_TRANSFER_REQUIRES_H2_STATION")
                if htt.status != "PARKED" or htt.current_node != action.station_bus:
                    raise ValueError("HTT_TRANSFER_REQUIRES_PARKED_AT_STATION")
                if action.kind == "STATION_TO_HTT":
                    if action.quantity_kg > temp_station[site] + TOL:
                        raise ValueError("INSUFFICIENT_STATION_INVENTORY")
                    if temp_cargo[action.htt_id] + action.quantity_kg > HTT_CAPACITY_KG + TOL:
                        raise ValueError("HTT_CAPACITY_EXCEEDED")
                    temp_station[site] -= action.quantity_kg
                    temp_cargo[action.htt_id] += action.quantity_kg
                else:
                    if action.quantity_kg > temp_cargo[action.htt_id] + TOL:
                        raise ValueError("INSUFFICIENT_HTT_CARGO")
                    temp_cargo[action.htt_id] -= action.quantity_kg
                    temp_station[site] += action.quantity_kg
            else:
                if mfcv is None or site is None:
                    raise ValueError("MFCV_REFUEL_REQUIRES_H2_STATION")
                if mfcv.status != "PARKED" or mfcv.current_node != action.station_bus:
                    raise ValueError("MFCV_REFUEL_REQUIRES_PARKED_AT_STATION")
                if action.quantity_kg > temp_station[site] + TOL:
                    raise ValueError("INSUFFICIENT_STATION_INVENTORY")
                if temp_onboard[action.mfcv_id] + action.quantity_kg > MFCV_CAPACITY_KG + TOL:
                    raise ValueError("MFCV_CAPACITY_EXCEEDED")
                temp_station[site] -= action.quantity_kg
                temp_onboard[action.mfcv_id] += action.quantity_kg

            system_after = _system_total(temp_station, temp_cargo, temp_onboard)
            records.append(
                dict(
                    action_id=action.action_id,
                    batch_time_h=event_time,
                    transfer_type=action.kind,
                    requested_kg=float(action.quantity_kg),
                    transferred_kg=transferred,
                    status=status,
                    reason="DIRECT_INTERFACE_RESERVED_FLAG_OFF" if status == "DISABLED_DIRECT_REFUEL" else "",
                    htt_id="" if action.htt_id is None else action.htt_id,
                    mfcv_id="" if action.mfcv_id is None else action.mfcv_id,
                    station_site="" if site is None else site + 1,
                    station_bus="" if action.station_bus is None else action.station_bus,
                    station_H2_before_kg=station_before,
                    station_H2_after_kg="" if site is None else float(temp_station[site]),
                    HTT_cargo_before_kg=cargo_before,
                    HTT_cargo_after_kg="" if htt is None else float(temp_cargo[action.htt_id]),
                    MFCV_onboard_before_kg=onboard_before,
                    MFCV_onboard_after_kg="" if mfcv is None else float(temp_onboard[action.mfcv_id]),
                    system_H2_before_kg=system_before,
                    system_H2_after_kg=system_after,
                    system_H2_transfer_error_kg=system_after - system_before,
                )
            )
    except ValueError as exc:
        reason = str(exc)
        original_cargo = {key: state.cargo_H2_kg for key, state in htt_states.items()}
        original_onboard = {key: state.onboard_H2_kg for key, state in mfcv_states.items()}
        return TransferBatchResult(
            False,
            reason,
            _failure_records(actions, station, original_cargo, original_onboard, reason),
        )

    station_inventory_kg[:] = temp_station
    for vehicle_id, cargo in temp_cargo.items():
        htt_states[vehicle_id].cargo_H2_kg = cargo
    for vehicle_id, onboard in temp_onboard.items():
        mfcv_states[vehicle_id].onboard_H2_kg = onboard
    return TransferBatchResult(True, "", records)
