# -*- coding: utf-8 -*-
"""B3 regression gate, deterministic fixtures and one frozen-realization smoke."""
from pathlib import Path
from collections import Counter
import argparse
import ast
import hashlib
import json
import subprocess
import sys
import traceback
import numpy as np
import pandas as pd

V1=Path(__file__).resolve().parents[1]
ROOT=V1.parents[1]
sys.path.insert(0,str(V1/'src'))
from engine import Action,Simulator,nominal
from road import Road,geometry,load_frozen

BASE=ROOT/'results/task-002-stage2b-b3-smoke'
B2=BASE/'w-oos-v1-b2-audit/run-001'
PRE=BASE/'w-oos-v1-preflight/run-001'


def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
    return h.hexdigest()


def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT).decode('utf-8').strip()


def proc():
    text=subprocess.check_output(['powershell','-NoProfile','-Command',"@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match 'matlab|gurobi'} | Select-Object ProcessId,Name,CreationDate,CommandLine) | ConvertTo-Json -Compress"]).decode()
    return json.loads(text) if text.strip() else []


def fixture(edges,minutes,close_after=None,slow_after=None):
    # User-requested exact-time unit fixtures, never a replacement frozen W bank.
    p=np.zeros((6,len(edges)));closed=np.zeros_like(p,dtype=bool)
    for e,k in (close_after or {}).items():closed[k:,e]=True
    for e,(k,value) in (slow_after or {}).items():p[k:,e]=value
    return Road(np.asarray(edges),np.asarray(minutes)*40/60,p,closed,identity='ARTIFICIAL_UNIT_TEST_ONLY')


def main(out):
    out.mkdir(parents=True,exist_ok=False)
    def write(name,data):
        (out/name).write_text(json.dumps(data,indent=2,ensure_ascii=False,allow_nan=False),encoding='utf-8')
    status=git('-c','core.quotepath=false','status','--porcelain=v1','--untracked-files=all').splitlines()
    preflight=dict(branch=git('branch','--show-current'),HEAD=git('rev-parse','HEAD'),upstream=git('rev-parse','--abbrev-ref','@{upstream}'),ahead_behind=git('rev-list','--left-right','--count','HEAD...@{upstream}'),worktree_counts=dict(Counter(s[:2] for s in status)),tracked_changes=[s for s in status if not s.startswith('??')],processes=proc(),fetch=False)
    write('preflight.json',preflight)
    assert preflight['branch']=='task/002-stage2b-b3-smoke'
    write('analysis_control_card.json',dict(task='W_OOS/V1-B3',RUN_MODE='A',MODE_SCOPE='RESTRICTED_SCOPE',evidence='ENGINEERING',training='NOT_APPLICABLE',required_cases=list(range(1,11)),regression_gate='B2 matrices and original formal source; 1e-10 km existing tolerance; stop on failure',test_fixture_policy='Explicit artificial unit cases requested by user; separate from one real W realization, not research data',source_scope='All B1/B2/preflight lightweight artifacts and all B2 source-manifest inputs rehashed; no protected model writes',deferred=['optimization','demand/grid rescue validation','training','OOS','final parameter adoption'],contract=nominal()))
    sourcepaths=set(ROOT/p for p in pd.read_csv(B2/'source_manifest.csv').path)
    for directory in [B2,PRE,BASE/'w-oos-v1-b1-scale/run-001']:
        sourcepaths.update(p for p in directory.rglob('*') if p.is_file())
    sourcepaths.update(p for folder in ['src','config','tests','docs'] for p in (V1/folder).rglob('*') if p.is_file() and '__pycache__' not in str(p))
    sources={p:sha(p) for p in sourcepaths}
    checks=[];cases=[];sims=[];case_inputs=[];regression=[]
    def check(name,condition,actual=None,expected=None):
        checks.append(dict(check=name,result='PASS' if bool(condition) else 'FAIL',actual=actual,expected=expected))
        if not condition:raise AssertionError(name)
    def add(name,road,actions,stop,inventory,sites,onboard,detail):
        sim=Simulator(road,inventory,sites,onboard,actions).run(stop)
        sims.append((name,sim))
        case_inputs.append(dict(case=name,road_identity=road.identity,edges=road.edges.tolist(),physical_lengths_km=road.lengths_km.tolist(),cumulative_consequence=road.consequence.tolist(),closed=road.closed.tolist(),initial_actual_inventory=list(map(float,inventory)),initial_sites=sites,initial_onboard=onboard,actions=[a.__dict__ for a in actions],stop_h=stop,description=detail))
        cases.append(dict(case=name,kind=road.identity,description=detail,event_rows=len(sim.ledger),result='PASS'))
        return sim
    def arrivals(sim,vid=1):return [e for e in sim.events if e['event']=='MOVE_COMPLETE' and e['vehicle_id']==vid]
    def expect_reject(name,fn):
        try:fn()
        except ValueError:check(name,True);return
        raise AssertionError(name+' was accepted')
    try:
        b2manifest=pd.read_csv(B2/'output_manifest.csv')
        for r in b2manifest.itertuples(index=False):check('B2_retained_hash_'+Path(r.path).name,sha(ROOT/r.path)==r.sha256)
        check('B2_closeout_PASS',json.loads((B2/'final_closeout.json').read_text())['C_IDENTITY_QA']=='PASS')
        edges,lengths=geometry(ROOT)
        # Execute just the existing formal function with scalar loops for a small independent reference.
        formalpath=ROOT/'terminalLoh_wdro/partial_temporal_refinement/src/run_temporal_refinement.py'
        tree=ast.parse(formalpath.read_text(encoding='utf-8'))
        fn=next(x for x in tree.body if isinstance(x,ast.FunctionDef) and x.name=='compute_road_states');fn.decorator_list=[]
        scope=dict(np=np,prange=range,I=33,N=33,N_ROADS=41)
        exec(compile(ast.Module(body=[fn],type_ignores=[]),str(formalpath),'exec'),scope)
        formal=scope['compute_road_states']
        for p in sorted(B2.glob('C_MFCV_example_state*.npz')):
            f=np.load(p);prob=np.asarray(f['cumulative_pClose']);closed=f['closed'].astype(bool)
            road=Road(edges,lengths,np.vstack([np.zeros(41),np.tile(prob,(5,1))]),np.vstack([np.zeros(41,bool),np.tile(closed,(5,1))]))
            c=road.matrix(1);old=f['C_MFCV'];finite=np.isfinite(old)
            check('B2_reach_'+p.stem,np.array_equal(np.isfinite(c),finite))
            diff=float(np.max(abs(c[finite]-old[finite])))
            check('B2_C_'+p.stem,diff<=1e-10,diff,1e-10)
            _,direct=formal(prob[None,:],np.where(closed,-1.,2.)[None,:],edges[:,0]-1,edges[:,1]-1,lengths,np.arange(33))
            check('formal_source_'+p.stem,np.allclose(c,direct[0],rtol=0,atol=1e-10))
            w=road.weights(1);tau=w/40
            check('edge_time_'+p.stem,np.array_equal(np.isinf(tau),closed) and np.allclose(tau[~closed],lengths[~closed]*(1+prob[~closed])/40,rtol=0,atol=1e-14))
            for start in [24,14,18,31]:
                for target in range(1,34):
                    route=road.route(1,start,target)
                    check('route_%s_%d_%d'%(p.stem,start,target),(route is None and not np.isfinite(c[start-1,target-1])) or (route is not None and abs(sum(w[e] for e,_,_ in route)-c[start-1,target-1])<=1e-10))
            regression.append(dict(example=p.name,matrix_entries=1089,site_entries=132,max_abs_diff_km=diff,unreachable_mismatches=0,edge_time_QA='PASS'))
        intact=Road(edges,lengths,np.zeros((6,41)),np.zeros((6,41),bool))
        check('B2_W0',np.allclose(intact.matrix(0),np.load(B2/'C_MFCV_W0_and_examples.npz')['W0'][0],rtol=0,atol=1e-10))
        pd.DataFrame(regression).to_csv(out/'B2_C_regression.csv',index=False)
        write('B2_C_regression_gate.json',dict(B2_C_REGRESSION_QA='PASS',examples=len(regression),max_abs_diff_km=max(r['max_abs_diff_km'] for r in regression)))
        print('B2 road regression PASS; starting physics cases',flush=True)

        inventoryfile=PRE/'recovered_msp_inventory.csv'
        old=pd.read_csv(PRE/'output_manifest.csv')
        check('actual_inventory_hash',sha(inventoryfile)==old[old.path.str.endswith('/recovered_msp_inventory.csv')].iloc[0].sha256)
        inv=pd.read_csv(inventoryfile)
        cols=['inventory_site%d'%s for s in range(1,5)]
        actual=inv[(inv.arm=='BASE2-DRO')&(inv[cols].min(axis=1)>=20)].sort_values('path_id').iloc[0]
        inventory=actual[cols].to_numpy(float)
        write('actual_inventory_source.json',dict(arm=actual.arm,path_id=int(actual.path_id),fields=cols,inventory_kg=inventory.tolist(),sha256=sha(inventoryfile),selection='first ordered DRO path with all 4 inventories >=20kg; mechanical test selection only'))
        sites=[1,1,2,3,4,4];onboard=[10.,5.,3.,2.,4.,4.]
        base=fixture([[24,1]],[13])
        sim=add('CASE-1',base,[Action(1,'MOVE',target_node=1)],.25,inventory,sites,onboard,'13分钟精确到达；同一道路状态')
        check('CASE1_13min',abs(arrivals(sim)[0]['time_h']*60-13)<1e-10,arrivals(sim)[0]['time_h']*60,13)
        sim=add('CASE-2',base,[Action(1,'MOVE',at_h=.3,target_node=1)],.6,inventory,sites,onboard,'第18分钟出发，第31分钟到达；跨0.5h进度不清零')
        moving=[r for r in sim.ledger if r['vehicle_id']==1 and r['state']=='MOVING']
        check('CASE2_31min',abs(arrivals(sim)[0]['time_h']*60-31)<1e-10)
        check('CASE2_12plus1min',len(moving)==2 and np.allclose([(r['time_end']-r['time_start'])*60 for r in moving],[12,1],atol=1e-10))
        check('CASE2_progress_carry',abs(moving[0]['physical_progress_after_km']-moving[1]['physical_progress_before_km'])<1e-12 and moving[1]['physical_progress_before_km']>0)
        road=fixture([[24,1],[1,2]],[13,6],slow_after={0:(2,.25),1:(2,.5)})
        sim=add('CASE-3',road,[Action(1,'MOVE',at_h=1.4,target_node=2)],1.9,inventory,sites,onboard,'跨W1→M12仍OPEN；当前边保留入边时长，下一边新后果值')
        check('CASE3_arrival',abs(arrivals(sim)[0]['time_h']-(1.4+13/60+9/60))<1e-12)
        entries=[e for e in sim.events if e['event']=='EDGE_ENTER']
        check('CASE3_next_state',entries[1]['road_state']=='M12' and abs(entries[1]['weight_km']/40*60-9)<1e-12)
        road=fixture([[24,1],[1,14],[14,24]],[13,9,9],close_after={0:2})
        sim=add('CASE-4',road,[Action(1,'MOVE',at_h=1.4,target_node=1),Action(1,'MOVE',target_node=24)],2.0,inventory,sites,onboard,'入边后关闭仍完成；返程重新规划，不再进入closed原边')
        entries=[e for e in sim.events if e['event']=='EDGE_ENTER']
        check('CASE4_complete_current_closed_edge',abs(arrivals(sim)[0]['time_h']-(1.4+13/60))<1e-12)
        check('CASE4_reroute',len(entries)==3 and [e['edge_id'] for e in entries]==[1,2,3] and len(arrivals(sim))==2)
        road=fixture([[24,1],[1,2]],[13,6],close_after={1:2})
        sim=add('CASE-5-unreachable',road,[Action(1,'MOVE',at_h=1.4,target_node=2)],1.9,inventory,sites,onboard,'下一边关闭，停在到达节点并标记UNREACHABLE')
        check('CASE5_unreachable',sim.vehicles[0].node==1 and sim.vehicles[0].status=='UNREACHABLE' and len([e for e in sim.events if e['event']=='EDGE_ENTER'])==1)
        road=fixture([[24,1],[1,2],[1,14],[14,2]],[13,6,9,9],close_after={1:2})
        sim=add('CASE-5-reroute',road,[Action(1,'MOVE',at_h=1.4,target_node=2)],2.0,inventory,sites,onboard,'下一边关闭，存在替代路径时重规划')
        check('CASE5_reroute',[e['edge_id'] for e in sim.events if e['event']=='EDGE_ENTER']==[1,3,4] and len(arrivals(sim))==1)
        sim=add('CASE-6',base,[],.1,inventory,sites,onboard,'真实DRO路径Option-A初始逐站分账')
        partition=[]
        for s in range(1,5):
            allocated=sum(h for si,h in zip(sites,onboard) if si==s)
            check('CASE6_site%d'%s,abs(sim.station[s-1]+allocated-inventory[s-1])<1e-12)
            partition.append(dict(site=s,actual_inventory_kg=inventory[s-1],station_initial_kg=sim.station[s-1],vehicle_initial_kg=allocated,error_kg=sim.station[s-1]+allocated-inventory[s-1]))
        pd.DataFrame(partition).to_csv(out/'option_A_initial_partition.csv',index=False)
        road=fixture([[24,14]],[13])
        sim=add('CASE-7',road,[Action(1,'MOVE',target_node=14),Action(1,'REFUEL',H_kg=10)],.3,inventory,sites,onboard,'到站后零时长转移10kg')
        row=next(r for r in sim.ledger if r['state']=='REFUEL_EVENT')
        check('CASE7_instant',row['time_start']==row['time_end'] and abs(row['time_start']-13/60)<1e-12)
        check('CASE7_transfer',row['onboard_H2_after']-row['onboard_H2_before']==10 and abs(row['station_H2_before_2']-row['station_H2_after_2']-10)<1e-12)
        scarce=[20.,20.,20.,20.]
        sim=add('CASE-8',base,[Action(1,'REFUEL',H_kg=60),Action(1,'REFUEL',H_kg=6)],.1,scarce,sites,onboard,'人工资源边界：分别拒绝超罐与共享站库存不足，原子性不变账')
        rows=[r for r in sim.ledger if r['state']=='REFUEL_EVENT']
        check('CASE8_atomic_reject',[r['status'] for r in rows]==['REJECTED_TANK_CAPACITY','REJECTED_STATION_INVENTORY'] and all(r['onboard_H2_after']==r['onboard_H2_before'] for r in rows))
        sim=add('CASE-9',base,[Action(1,'SERVICE',duration_h=.3,power_kW=220),Action(1,'MOVE',target_node=1)],.6,inventory,sites,onboard,'18分钟SERVICE后13分钟MOVE；220kW×0.3h=66kWh')
        energy=sum(r['energy_served_kWh'] for r in sim.ledger)
        check('CASE9_energy',abs(energy-66)<1e-10,energy,66)
        check('CASE9_hydrogen',abs(sim.consumed-66/(.55*33.33))<1e-12,sim.consumed,66/(.55*33.33))
        check('CASE9_no_moving_generation',all(r['P_output']==0 and r['energy_served_kWh']==0 for r in sim.ledger if r['state']=='MOVING'))
        sim=add('CASE-10',base,[Action(1,'REFUEL',H_kg=4),Action(2,'REFUEL',H_kg=4)],.1,scarce,sites,onboard,'同站两车共享初始分配；同一时刻按车辆ID处理补氢，第二车拒绝重复占用')
        rows=[r for r in sim.ledger if r['state']=='REFUEL_EVENT']
        check('CASE10_no_double_use',[r['status'] for r in rows]==['TRANSFERRED','REJECTED_STATION_INVENTORY'] and sim.station[0]==1 and sim.vehicles[0].hydrogen==14 and sim.vehicles[1].hydrogen==5)
        expect_reject('initial_shared_overallocation',lambda:Simulator(base,[14,20,20,20],sites,onboard,[]))
        expect_reject('initial_overcapacity',lambda:Simulator(base,inventory,sites,[67,0,0,0,0,0],[]))
        expect_reject('negative_inventory',lambda:Simulator(base,[-1,20,20,20],sites,[0]*6,[]))
        expect_reject('nonfinite_action',lambda:Simulator(base,inventory,sites,onboard,[Action(1,'WAIT',duration_h=np.nan)]))
        expect_reject('moving_power_request',lambda:Simulator(base,inventory,sites,onboard,[Action(1,'MOVE',target_node=1,power_kW=1)]))
        expect_reject('service_over_Pmax',lambda:Simulator(base,inventory,sites,onboard,[Action(1,'SERVICE',duration_h=.1,power_kW=221)]))
        sim=add('EXTRA-fuel-exhaustion',base,[Action(1,'SERVICE',duration_h=.5,power_kW=220)],.6,inventory,sites,[1,0,0,0,0,0],'1kg燃料精确耗尽后停止输出，保持原SERVICE请求结束时间')
        check('fuel_exact_energy',abs(sum(r['energy_served_kWh'] for r in sim.ledger)-18.3315)<1e-10 and sim.vehicles[0].hydrogen==0)
        sim=add('EXTRA-offsite-refuel',base,[Action(1,'MOVE',target_node=1),Action(1,'REFUEL',H_kg=1)],.4,inventory,sites,onboard,'非H2站禁止补氢；MOVE后动作顺序执行')
        check('offsite_reject',any(e['event']=='REJECTED_NOT_AT_SITE' for e in sim.events))
        sim=add('EXTRA-boundary-arrival',fixture([[24,1],[1,2]],[6,6],close_after={1:2}),[Action(1,'MOVE',at_h=1.4,target_node=2)],1.6,inventory,sites,onboard,'节点到达恰好等于1.5h；优先应用新closed状态')
        check('boundary_before_entry',sim.vehicles[0].node==1 and sim.vehicles[0].status=='UNREACHABLE')
        sim=add('EXTRA-horizon-in-transit',base,[Action(1,'MOVE',at_h=3.4,target_node=1)],3.5,inventory,sites,onboard,'horizon截断保留在途位置和已完成进度')
        check('horizon_preserves_transit',sim.vehicles[0].state=='MOVING' and sim.vehicles[0].node is None and abs(sim.vehicles[0].route_physical-4)<1e-10)
        sim=add('EXTRA-concurrent-service',base,[Action(1,'SERVICE',duration_h=.3,power_kW=220),Action(2,'SERVICE',duration_h=.3,power_kW=100)],.4,inventory,sites,onboard,'两车同时SERVICE，全局时钟与能量质量守恒')
        check('concurrent_service_energy',abs(sum(r['energy_served_kWh'] for r in sim.ledger)-96)<1e-10)

        road,ref,frozenfile=load_frozen(ROOT,1,1)
        anchors=np.array([24,14,18,31])-1
        for k in range(5):check('frozen_single_path_C_%d'%k,np.allclose(road.matrix(k+1)[anchors],ref[k],rtol=0,atol=1e-10))
        realactions=[Action(1,'SERVICE',duration_h=.3,power_kW=220),Action(1,'MOVE',target_node=14),Action(1,'REFUEL',H_kg=10),Action(1,'MOVE',target_node=24),Action(1,'SERVICE',duration_h=.2,power_kW=150),Action(2,'MOVE',at_h=1.4,target_node=31),Action(3,'SERVICE',at_h=1,duration_h=.15,power_kW=100),Action(4,'WAIT',duration_h=1.3),Action(4,'MOVE',target_node=24)]
        sim=add('FROZEN-INTEGRATION',road,realactions,3.5,inventory,sites,onboard,'真实frozen W state001/path00001 + 真实DRO库存；固定动作，不是联合概率样本或OOS')
        check('real_multiple_relocations',len(arrivals(sim))>=2)
        write('frozen_input_identity.json',dict(file=str(frozenfile.relative_to(ROOT)),sha256=sha(frozenfile),state_id=1,path_id=1,inventory_arm=actual.arm,inventory_path=int(actual.path_id),pairing='mechanical independent smoke selection, no probabilistic pairing claim'))
        for name,sim in sims:
            check(name+'_mass',max(abs(r['mass_error_kg']) for r in sim.mass_checks)<1e-9)
            ledger=pd.DataFrame(sim.ledger)
            for vid in range(1,7):
                timed=ledger[(ledger.vehicle_id==vid)&(ledger.time_end>ledger.time_start)]
                check(name+'_contiguous_%d'%vid,abs(timed.time_start.iloc[0])<1e-12 and abs(timed.time_end.iloc[-1]-sim.t)<1e-12 and np.allclose(timed.time_start.to_numpy()[1:],timed.time_end.to_numpy()[:-1],rtol=0,atol=1e-12))
            for row in sim.ledger:
                a,b=row['time_start'],row['time_end']
                check(name+'_split_%d'%len(checks),not any(a+1e-12<x<b-1e-12 for x in [.5,1,1.5,2,2.5,3,3.5]))
                check(name+'_energy_%d'%len(checks),abs(row['energy_served_kWh']-row['P_output']*(b-a))<1e-9)
                if row['state']=='MOVING':check(name+'_moving_%d'%len(checks),row['P_output']==0 and row['onboard_H2_before']==row['onboard_H2_after'] and row['current_edge'] is not None)
            for event in sim.events:
                if event['event']=='EDGE_ENTER':
                    k=nominal()['point_names'].index(event['road_state']);e=event['edge_id']-1
                    check(name+'_open_entry_%d'%len(checks),not sim.road.closed[k,e])
        pd.concat([pd.DataFrame(s.ledger).assign(case=n) for n,s in sims],ignore_index=True).to_csv(out/'event_ledger.csv',index=False)
        pd.concat([pd.DataFrame(s.events).assign(case=n) for n,s in sims],ignore_index=True).to_csv(out/'action_events.csv',index=False)
        pd.concat([pd.DataFrame(s.mass_checks).assign(case=n) for n,s in sims],ignore_index=True).to_csv(out/'mass_balance_ledger.csv',index=False)
        energy=pd.read_csv(out/'event_ledger.csv').groupby(['case','accounting_interval','vehicle_id']).energy_served_kWh.sum().reset_index()
        energy.to_csv(out/'accounting_energy_0p5h.csv',index=False)
        write('case_inputs.json',case_inputs)
        write('final_vehicle_states.json',[dict(case=n,vehicles=[dict(vehicle_id=i+1,node=v.node,state=v.state,status=v.status,onboard_H2_kg=v.hydrogen,current_edge=None if v.edge is None else v.edge+1,move_physical_km=v.route_physical,move_equivalent_km=v.route_equivalent) for i,v in enumerate(s.vehicles)],station_H2_kg=s.station.tolist(),consumed_H2_kg=s.consumed) for n,s in sims])
        pd.DataFrame(cases).to_csv(out/'smoke_cases.csv',index=False)
        for p,h in sources.items():check('source_preserved_'+str(p.relative_to(ROOT)),sha(p)==h)
        pd.DataFrame([dict(path=str(p.relative_to(ROOT)),bytes=p.stat().st_size,sha256_before=h,sha256_after=sha(p),unchanged=True) for p,h in sorted(sources.items())]).to_csv(out/'source_manifest.csv',index=False)
        pd.DataFrame(checks).to_csv(out/'checks.csv',index=False)
        flags=['CONTINUOUS_TIME_PROGRESS_QA','ROAD_STATE_BOUNDARY_QA','CURRENT_EDGE_CLOSURE_RULE_QA','REROUTE_QA','MOVING_NO_GENERATION_QA','H2_MASS_CONSERVATION_QA','OPTION_A_INITIAL_SPLIT_QA','NONBINDING_REFUEL_QA','TANK_CAPACITY_QA','SERVICE_ENERGY_IDENTITY_QA','B2_C_REGRESSION_QA']
        qa={k:'PASS' for k in flags}
        qa.update(B3_PHYSICS_ENGINE_SMOKE='PASS',ANALYSIS_QA='PASS',COMMUNICATION_QA='PENDING_REPORT_REVIEW',DATA_PRESERVATION_QA='PASS',OVERALL_DELIVERY='PENDING_CLOSEOUT',cases=len(cases),checks=len(checks),sources=len(sources),max_mass_error_kg=max(abs(r['mass_error_kg']) for _,s in sims for r in s.mass_checks),max_C_diff_km=max(r['max_abs_diff_km'] for r in regression),processes_after=proc(),HEAD=git('rev-parse','HEAD'),commit='NONE',push='NONE',run=out.name)
        check('HEAD_unchanged',qa['HEAD']==preflight['HEAD'])
        write('physics_QA.json',qa)
        print(json.dumps(qa,indent=2),flush=True)
    except Exception:
        pd.DataFrame(checks).to_csv(out/'checks.csv',index=False)
        write('physics_QA.json',dict(B3_PHYSICS_ENGINE_SMOKE='FAIL',error=traceback.format_exc(),next_step='Fix implementation or test defect; preserve failed run and use new run directory'))
        raise


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--run',required=True);args=parser.parse_args()
    if not args.run.startswith('run-') or not args.run[4:].isdigit():raise ValueError('Expected run-NNN')
    main(V1/'results/b3-physics-smoke'/args.run)
