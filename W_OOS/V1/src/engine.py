"""Deterministic six-vehicle event physics. No optimizer or demand evaluator."""
from dataclasses import dataclass
import json
from pathlib import Path
import numpy as np

EPS=1e-12


def nominal():
    return json.loads((Path(__file__).resolve().parents[1]/'config/b3_nominal.json').read_text())


@dataclass(frozen=True)
class Action:
    vehicle_id: int
    kind: str
    at_h: float = 0.0
    duration_h: float = 0.0
    target_node: int = None
    power_kW: float = 0.0
    H_kg: float = 0.0


@dataclass
class Vehicle:
    node: int
    hydrogen: float
    state: str = 'PARKED'
    status: str = 'IDLE'
    active: Action = None
    end: float = np.inf
    edge: int = None
    edge_from: int = None
    edge_to: int = None
    entry_state: int = None
    edge_start: float = 0.0
    edge_end: float = np.inf
    edge_weight: float = 0.0
    route_physical: float = 0.0
    route_equivalent: float = 0.0
    power: float = 0.0


class Simulator:
    def __init__(self,road,actual_inventory,initial_sites,initial_onboard,actions,config=None):
        self.cfg=nominal() if config is None else dict(config)
        # B3 is a single specified contract, not a configurable hardware experiment.
        if self.cfg!=nominal():raise ValueError('B3 nominal contract cannot be overridden')
        self.road=road
        self.t=0.0
        self.ledger=[]
        self.events=[]
        self.mass_checks=[]
        self.consumed=0.0
        inv=np.array(actual_inventory,float,copy=True)
        onboard=np.array(initial_onboard,float,copy=True)
        sites=np.asarray(initial_sites)
        if inv.shape!=(4,) or onboard.shape!=(6,) or sites.shape!=(6,):raise ValueError('Option A requires 4 inventories and 6 vehicles')
        if not np.isfinite(inv).all() or not np.isfinite(onboard).all() or np.any(inv<0) or np.any(onboard<0) or np.any(onboard>self.cfg['Hcap_kg']):
            raise ValueError('Invalid initial H2 inventory or tank capacity')
        if any(s not in [1,2,3,4] for s in sites):raise ValueError('Initial sites must be 1-based site IDs')
        self.original=inv.copy()
        self.initial_onboard=onboard.copy()
        self.initial_sites=sites.astype(int)
        self.station=inv.copy()
        for s in range(1,5):self.station[s-1]-=onboard[sites==s].sum()
        if np.any(self.station<0):raise ValueError('Option A onboard allocation exceeds shared site inventory')
        self.vehicles=[Vehicle(self.cfg['site_anchors'][int(s)-1],float(h)) for s,h in zip(sites,onboard)]
        self.queues=[[] for _ in range(6)]
        for a in actions:
            self._validate(a)
            self.queues[a.vehicle_id-1].append(a)
        self._mass('INITIAL_OPTION_A')

    def _validate(self,a):
        if a.vehicle_id not in range(1,7) or a.kind not in ['SERVICE','MOVE','REFUEL','WAIT']:raise ValueError('Unknown vehicle or action')
        if not all(np.isfinite(x) for x in [a.at_h,a.duration_h,a.power_kW,a.H_kg]):raise ValueError('Nonfinite action')
        if not 0<=a.at_h<self.cfg['horizon_h'] or a.duration_h<0 or a.H_kg<0 or not 0<=a.power_kW<=self.cfg['Pmax_kW']:raise ValueError('Action bounds violation')
        if a.kind=='MOVE' and (not isinstance(a.target_node,(int,np.integer)) or not 1<=a.target_node<=self.road.node_count):raise ValueError('Invalid move target')
        if a.kind in ['MOVE','REFUEL'] and a.duration_h!=0:raise ValueError('MOVE/REFUEL duration is determined by physics')
        if a.kind!='SERVICE' and a.power_kW!=0:raise ValueError('Only SERVICE can generate')
        if a.kind!='REFUEL' and a.H_kg!=0:raise ValueError('Only REFUEL can request H2 transfer')

    def state_index(self):
        return int(np.searchsorted(self.cfg['point_starts_h'],self.t,side='right')-1)

    def _mass(self,event):
        onboard=sum(v.hydrogen for v in self.vehicles)
        error=float(self.station.sum()+onboard+self.consumed-self.original.sum())
        if abs(error)>self.cfg['mass_tolerance_kg'] or np.any(self.station<0) or any(v.hydrogen<0 or v.hydrogen>self.cfg['Hcap_kg'] for v in self.vehicles):
            raise RuntimeError('Hydrogen mass/tank invariant failed')
        for v in self.vehicles:
            if (v.state=='MOVING')!=(v.edge is not None) or (v.edge is not None and v.node is not None):raise RuntimeError('Vehicle location invariant failed')
            if v.state!='SERVICE' and v.power!=0:raise RuntimeError('Non-service generation')
        self.mass_checks.append(dict(time_h=self.t,event=event,station_total_kg=float(self.station.sum()),onboard_total_kg=onboard,consumed_H2_kg=self.consumed,original_total_kg=float(self.original.sum()),mass_error_kg=error))

    def _event(self,i,event,**kwargs):
        self.events.append(dict(time_h=self.t,vehicle_id=i+1,event=event,road_state=self.cfg['point_names'][self.state_index()],**kwargs))

    def _row(self,i,end,state=None,status=None,station_before=None,h_before=None,energy=0.0,physical0=0.,physical1=0.,equivalent0=0.,equivalent1=0.,route0=None,route1=None):
        v=self.vehicles[i]
        before=self.station if station_before is None else station_before
        r=dict(time_start=self.t,time_end=end,vehicle_id=i+1,state=state or v.state,status=status or v.status,
               from_node=v.edge_from if v.edge is not None else v.node,to_node=v.edge_to if v.edge is not None else v.node,
               current_edge=v.edge+1 if v.edge is not None else None,road_state=self.cfg['point_names'][self.state_index()],
               edge_entry_road_state=self.cfg['point_names'][v.entry_state] if v.edge is not None else None,
               edge_entry_time_h=v.edge_start if v.edge is not None else None,edge_planned_arrival_h=v.edge_end if v.edge is not None else None,
               physical_progress_before_km=physical0,physical_progress_after_km=physical1,
               equivalent_progress_before_km=equivalent0,equivalent_progress_after_km=equivalent1,
               move_physical_before_km=v.route_physical if route0 is None else route0[0],move_physical_after_km=v.route_physical if route1 is None else route1[0],
               move_equivalent_before_km=v.route_equivalent if route0 is None else route0[1],move_equivalent_after_km=v.route_equivalent if route1 is None else route1[1],
               onboard_H2_before=v.hydrogen if h_before is None else h_before,onboard_H2_after=v.hydrogen,
               P_output=v.power,energy_served_kWh=energy,
               accounting_interval=int(np.floor(self.t/self.cfg['accounting_dt_h'])))
        for s in range(4):r['station_H2_before_%d'%(s+1)]=float(before[s]);r['station_H2_after_%d'%(s+1)]=float(self.station[s])
        self.ledger.append(r)

    def _enter(self,i):
        v=self.vehicles[i];k=self.state_index()
        route=self.road.route(k,v.node,v.active.target_node)
        if route is None:
            v.status='UNREACHABLE';v.active=None;v.state='PARKED'
            self._event(i,'UNREACHABLE',node=v.node)
            self._row(i,self.t)
            return
        if not route:
            v.active=None;v.state='PARKED';v.status='ARRIVED'
            self._event(i,'MOVE_COMPLETE',node=v.node)
            return
        e,u,w=route[0]
        if self.road.closed[k,e]:raise RuntimeError('Attempted closed-edge entry')
        v.edge=e;v.edge_from=u;v.edge_to=w;v.node=None
        v.entry_state=k;v.edge_start=self.t;v.edge_weight=float(self.road.weights(k)[e])
        v.edge_end=self.t+v.edge_weight/self.cfg['v0_kmh'];v.state='MOVING';v.status='IN_TRANSIT';v.power=0
        self._event(i,'EDGE_ENTER',edge_id=e+1,from_node=u,to_node=w,route_edges=[x[0]+1 for x in route],weight_km=v.edge_weight,arrival_h=v.edge_end)

    def _instant(self):
        # Global time is already on the new state boundary before any edge entry.
        for i,v in enumerate(self.vehicles):
            if v.edge is not None and v.edge_end<=self.t+EPS:
                v.node=v.edge_to
                self._event(i,'EDGE_ARRIVAL',edge_id=v.edge+1,node=v.node)
                v.edge=None;v.state='PARKED'
                self._enter(i)
            if v.active is not None and v.active.kind in ['SERVICE','WAIT']:
                if v.end<=self.t+EPS:
                    self._event(i,v.active.kind+'_COMPLETE',node=v.node)
                    v.active=None;v.state='PARKED';v.status='IDLE';v.power=0
                elif v.state=='SERVICE' and v.hydrogen<=EPS:
                    v.state='PARKED';v.status='FUEL_DEPLETED';v.power=0
                    self._event(i,'FUEL_DEPLETED',node=v.node)
            while v.active is None and self.queues[i] and self.queues[i][0].at_h<=self.t:
                a=self.queues[i].pop(0)
                self._event(i,'ACTION_START',kind=a.kind,requested_at_h=a.at_h)
                if a.kind=='REFUEL':
                    before=self.station.copy();h=v.hydrogen
                    if v.node not in self.cfg['site_anchors']:
                        status='REJECTED_NOT_AT_SITE'
                    else:
                        s=self.cfg['site_anchors'].index(v.node)
                        if h+a.H_kg>self.cfg['Hcap_kg']:status='REJECTED_TANK_CAPACITY'
                        elif a.H_kg>self.station[s]:status='REJECTED_STATION_INVENTORY'
                        else:
                            self.station[s]-=a.H_kg;v.hydrogen+=a.H_kg;status='TRANSFERRED'
                    self._row(i,self.t,state='REFUEL_EVENT',status=status,station_before=before,h_before=h)
                    self._event(i,status,requested_H2_kg=a.H_kg,transferred_H2_kg=v.hydrogen-h)
                    self._mass(status)
                elif a.kind=='MOVE':
                    v.active=a;v.route_physical=0;v.route_equivalent=0
                    self._enter(i)
                elif a.duration_h==0:
                    self._event(i,a.kind+'_COMPLETE',node=v.node)
                else:
                    v.active=a;v.end=self.t+a.duration_h
                    v.state='SERVICE' if a.kind=='SERVICE' and v.hydrogen>EPS else 'PARKED'
                    v.power=a.power_kW if v.state=='SERVICE' else 0
                    v.status='GENERATING' if v.state=='SERVICE' else 'FUEL_DEPLETED' if a.kind=='SERVICE' else 'WAIT'

    def run(self,until_h=None):
        stop=self.cfg['horizon_h'] if until_h is None else float(until_h)
        if self.t!=0 or not np.isfinite(stop) or not 0<stop<=self.cfg['horizon_h']:raise ValueError('run is one-shot inside the 3.5h horizon')
        boundaries=sorted(set(self.cfg['point_starts_h']+list(np.arange(0,self.cfg['horizon_h']+.25,.5))))
        while self.t<stop:
            self._instant();self._mass('INSTANT_COMPLETE')
            candidates=[stop]+[b for b in boundaries if b>self.t]
            for i,v in enumerate(self.vehicles):
                if v.edge is not None:candidates.append(v.edge_end)
                elif v.active is not None:
                    candidates.append(v.end)
                    if v.power>0:candidates.append(self.t+v.hydrogen*self.cfg['eta_FC']*self.cfg['LHV_kWh_per_kg']/v.power)
                elif self.queues[i]:candidates.append(self.queues[i][0].at_h)
            end=min(candidates)
            if end<=self.t:raise RuntimeError('Non-advancing event clock')
            dt=end-self.t
            for i,v in enumerate(self.vehicles):
                h=v.hydrogen;energy=v.power*dt
                p0=p1=q0=q1=0.;r0=(v.route_physical,v.route_equivalent)
                if v.edge is not None:
                    fraction0=(self.t-v.edge_start)/(v.edge_end-v.edge_start)
                    fraction1=(end-v.edge_start)/(v.edge_end-v.edge_start)
                    p0,p1=self.road.lengths_km[v.edge]*np.array([fraction0,fraction1])
                    q0,q1=v.edge_weight*np.array([fraction0,fraction1])
                    v.route_physical+=p1-p0;v.route_equivalent+=q1-q0
                used=energy/(self.cfg['eta_FC']*self.cfg['LHV_kWh_per_kg'])
                if used>h+EPS:raise RuntimeError('Service exceeds available hydrogen')
                v.hydrogen=max(0.,h-used);self.consumed+=h-v.hydrogen
                self._row(i,end,h_before=h,energy=energy,physical0=p0,physical1=p1,equivalent0=q0,equivalent1=q1,route0=r0,route1=(v.route_physical,v.route_equivalent))
            self.t=end;self._mass('INTERVAL_END')
        # Record arrivals/completions exactly at the stop; no new action/edge beyond stop.
        for i,v in enumerate(self.vehicles):
            if v.edge is not None and v.edge_end<=self.t+EPS:
                self._event(i,'EDGE_ARRIVAL',edge_id=v.edge+1,node=v.edge_to)
                v.node=v.edge_to;v.edge=None;v.state='PARKED';v.status='AT_STOP'
                if v.node==v.active.target_node:v.active=None;v.status='ARRIVED';self._event(i,'MOVE_COMPLETE',node=v.node)
            if v.active is not None and v.active.kind in ['SERVICE','WAIT'] and v.end<=self.t+EPS:
                self._event(i,v.active.kind+'_COMPLETE',node=v.node)
                v.active=None;v.state='PARKED';v.status='IDLE';v.power=0
        self._mass('FINAL')
        return self
