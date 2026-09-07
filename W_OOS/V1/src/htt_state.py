"""Explicit HTT state with a thin adapter to the accepted B3 motion engine."""
from dataclasses import dataclass, field
from typing import Dict, List, Optional

import numpy as np

from engine import Action as B3Action
from engine import Simulator as B3Simulator
from engine import nominal as b3_nominal


HTT_COUNT = 2
HTT_CAPACITY_KG = 80.0


@dataclass
class HTTState:
    vehicle_id: int
    status: str
    current_node: Optional[int]
    destination_node: Optional[int] = None
    route: List[int] = field(default_factory=list)
    edge_progress: float = 0.0
    departure_time: Optional[float] = None
    arrival_time: Optional[float] = None
    cargo_H2_kg: float = 0.0
    P_HTT_kW: float = 0.0
    Q_HTT_kvar: float = 0.0

    def __post_init__(self):
        if self.vehicle_id not in range(1, HTT_COUNT + 1):
            raise ValueError("B4D benchmark requires exactly HTT vehicle IDs 1 and 2")
        if self.status not in {"PARKED", "MOVING"}:
            raise ValueError("HTT status must be PARKED or MOVING")
        if not np.isfinite(self.cargo_H2_kg) or not 0.0 <= self.cargo_H2_kg <= HTT_CAPACITY_KG:
            raise ValueError("HTT cargo violates the 80 kg benchmark capacity")
        if self.P_HTT_kW != 0.0 or self.Q_HTT_kvar != 0.0:
            raise ValueError("HTT is a logistics vehicle and must have P=Q=0")


@dataclass(frozen=True)
class MovePlan:
    target_node: int
    earliest_departure_h: float = 0.0


@dataclass
class MotionResult:
    events: List[dict]
    movement_ledger: List[dict]
    arrivals: Dict[int, List[dict]]
    final_nodes: Dict[int, Optional[int]]
    final_status: Dict[int, str]


def simulate_with_b3_motion(
    road,
    initial_nodes: List[int],
    plans: Dict[int, List[MovePlan]],
    until_h: float,
) -> MotionResult:
    """Run two HTTs through the unchanged B3 Simulator movement semantics.

    Cargo is intentionally absent from the B3 propulsion engine. The B3
    simulator receives zero onboard H2 and is used only for continuous-time
    movement, edge-entry closure, rerouting, and exact-arrival events.
    """
    if len(initial_nodes) != HTT_COUNT:
        raise ValueError("B4D requires two explicit initial HTT nodes")
    cfg = b3_nominal()
    anchors = list(cfg["site_anchors"])
    if any(node not in anchors for node in initial_nodes):
        raise ValueError("B3 adapter initial HTT nodes must be verified H2 station anchors")
    if set(plans) - {1, 2}:
        raise ValueError("Move plans contain an unknown HTT vehicle")

    initial_sites = [anchors.index(node) + 1 for node in initial_nodes]
    initial_sites += [1] * (6 - len(initial_sites))
    actions = []
    for vehicle_id in range(1, HTT_COUNT + 1):
        for leg in plans.get(vehicle_id, []):
            actions.append(
                B3Action(
                    vehicle_id=vehicle_id,
                    kind="MOVE",
                    at_h=float(leg.earliest_departure_h),
                    target_node=int(leg.target_node),
                )
            )

    simulator = B3Simulator(
        road=road,
        actual_inventory=np.zeros(4),
        initial_sites=initial_sites,
        initial_onboard=np.zeros(6),
        actions=actions,
    ).run(until_h=float(until_h))

    events = [dict(row) for row in simulator.events if row["vehicle_id"] <= HTT_COUNT]
    movement = [
        dict(row)
        for row in simulator.ledger
        if row["vehicle_id"] <= HTT_COUNT and row["state"] == "MOVING"
    ]
    arrivals = {1: [], 2: []}
    for event in events:
        if event["event"] == "MOVE_COMPLETE":
            arrivals[event["vehicle_id"]].append(
                {
                    "time_h": float(event["time_h"]),
                    "node": int(event["node"]),
                    "stop_index": len(arrivals[event["vehicle_id"]]) + 1,
                }
            )
    for vehicle_id in range(1, HTT_COUNT + 1):
        expected = len(plans.get(vehicle_id, []))
        if len(arrivals[vehicle_id]) != expected:
            raise RuntimeError(
                "B3 motion did not complete all given HTT stops: vehicle %d, expected %d, got %d"
                % (vehicle_id, expected, len(arrivals[vehicle_id]))
            )

    return MotionResult(
        events=events,
        movement_ledger=movement,
        arrivals=arrivals,
        final_nodes={i + 1: simulator.vehicles[i].node for i in range(HTT_COUNT)},
        final_status={i + 1: simulator.vehicles[i].status for i in range(HTT_COUNT)},
    )
