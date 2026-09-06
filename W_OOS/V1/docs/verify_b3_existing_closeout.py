"""Read existing B3 artifacts only; never import or execute the physics engine."""
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'W_OOS/V1/results/b3-physics-smoke/run-001'
OUT = ROOT / 'results/task-002-stage2b-b3-smoke/w-oos-v1-b3-final-closeout/run-002'
SELF = Path(__file__).resolve().relative_to(ROOT).as_posix()


def git(*args):
    return subprocess.check_output(['git', '-c', 'core.quotepath=false', *args], cwd=ROOT).decode('utf-8')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(8*1024*1024), b''):
            h.update(block)
    return h.hexdigest()


def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def write_json(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')


def write_csv(name, rows):
    with (OUT / name).open('w', encoding='utf-8', newline='') as stream:
        writer = csv.DictWriter(stream, list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def snapshot():
    tracked = git('status', '--porcelain=v1', '-uno').splitlines()
    untracked = git('ls-files', '--others', '--exclude-standard', '-z').split('\0')
    prefix = OUT.relative_to(ROOT).as_posix() + '/'
    untracked = sorted(p for p in untracked if p and p != SELF and not p.startswith(prefix))
    metadata = []
    for p in untracked:
        s = Path('\\\\?\\' + str(ROOT / p)).stat()
        metadata.append([p, s.st_size, s.st_mtime_ns])
    tracked_hashes = {row[3:]: digest(ROOT / row[3:]) if (ROOT / row[3:]).is_file() else 'DELETED' for row in tracked}
    return dict(tracked=tracked, tracked_hashes=tracked_hashes, untracked_count=len(untracked),
                untracked_metadata_sha256=hashlib.sha256(json.dumps(metadata, ensure_ascii=False).encode()).hexdigest())


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    before = snapshot()
    pre = dict(branch=git('branch', '--show-current').strip(), HEAD=git('rev-parse', 'HEAD').strip(),
               upstream=git('rev-parse', '--abbrev-ref', '@{upstream}').strip(),
               ahead_behind=git('rev-list', '--left-right', '--count', 'HEAD...@{upstream}').strip(), **before)
    write_json('repo_precheck.json', pre)
    write_json('analysis_control_card.json', dict(RUN_MODE='A', MODE_SCOPE='RESTRICTED_SCOPE',
        TRAINING_STATUS='NOT_APPLICABLE', EVIDENCE_GRADE='ENGINEERING', ANALYSIS_NATURE='RETROSPECTIVE_DIAGNOSTIC',
        source=SOURCE.relative_to(ROOT).as_posix(), cases=[2, 4, 6, 7, 9, 10],
        numerical_tolerance=dict(time_h=1e-12, mass_kg=1e-9, C_km=1e-10),
        allowed_changes='New closeout artifacts and explicit B3 checkpoint only',
        deferred=['B3 rerun', 'B4', 'training', 'optimizer', 'MSP_OOS', 'W_OOS', 'ALL_OOS', 'parameter adoption'],
        rule_exception='Existing dirty codex_rule/log.md must remain byte-identical under explicit user instruction; new execution_log.md substitutes for its append.',
        stop='Any audit failure blocks staging, commit and push'))
    checks = []

    def check(name, ok, detail=''):
        checks.append(dict(check=name, result='PASS' if ok else 'FAIL', detail=str(detail)))

    def close(a, b, tol=1e-12):
        return abs(float(a) - float(b)) <= tol

    summary = json.loads((SOURCE / 'summary.json').read_text())
    ledger = read_csv(SOURCE / 'event_ledger.csv')
    events = read_csv(SOURCE / 'action_events.csv')
    masses = read_csv(SOURCE / 'mass_balance_ledger.csv')
    cases = read_csv(SOURCE / 'smoke_cases.csv')
    old_checks = read_csv(SOURCE / 'checks.csv')
    inputs = {c['case']: c for c in json.loads((SOURCE / 'case_inputs.json').read_text(encoding='utf-8'))}
    cfg = json.loads((ROOT / 'W_OOS/V1/config/b3_nominal.json').read_text())
    check('branch', pre['branch'] == 'task/002-stage2b-b3-smoke')
    check('index_initially_empty', not git('diff', '--cached', '--name-only').strip())
    check('existing_cases', len(cases) == summary['cases'] == 17 and all(c['result'] == 'PASS' for c in cases))
    check('existing_checks', len(old_checks) == summary['checks'] == 3875 and all(c['result'] == 'PASS' for c in old_checks))
    check('summary_QA', all(summary[k] == 'PASS' for k in ['B3_PHYSICS_ENGINE_SMOKE', 'ANALYSIS_QA', 'COMMUNICATION_QA', 'DATA_PRESERVATION_QA']))
    check('nominal_contract', [cfg[k] for k in ['fleet_size','Pmax_kW','Hcap_kg','v0_kmh','eta_FC','LHV_kWh_per_kg']] == [6,220,66.6,40,.55,33.33] and cfg['parameter_status'] == 'PROVISIONAL_PARAMETER')
    check('time_contract', cfg['point_names'] == ['W0','W1','M12','W2','M23','W3'] and cfg['point_starts_h'] == [0,1,1.5,2,2.5,3] and cfg['horizon_h'] == 3.5)
    sources = {}
    for name in ['source_manifest.csv', 'output_manifest.csv', 'closeout_source_manifest.csv']:
        for row in read_csv(SOURCE / name):
            p = ROOT / row['path']
            expected = row.get('sha256', row.get('sha256_after'))
            current = digest(p)
            # The old run explicitly appended its log after calculating its source manifest.
            prefix_ok = False
            if p == ROOT / 'codex_rule/log.md' and current != expected:
                with p.open('rb') as stream:
                    prefix_ok = hashlib.sha256(stream.read(int(row['bytes']))).hexdigest() == expected
            check('historical_hash:' + row['path'], current == expected or prefix_ok,
                  'historical log prefix preserved; later append retained' if prefix_ok else '')
            sources[p] = current
    print('Historical source/output hashes verified', flush=True)
    for row in ledger:
        a, b = float(row['time_start']), float(row['time_end'])
        check('ledger_numeric', all(math.isfinite(float(row[k])) for k in ['time_start','time_end','onboard_H2_before','onboard_H2_after','P_output','energy_served_kWh']))
        check('ledger_energy', close(row['energy_served_kWh'], float(row['P_output'])*(b-a), 1e-9))
        check('ledger_tank', 0 <= float(row['onboard_H2_after']) <= cfg['Hcap_kg'])
        check('ledger_station', all(float(row['station_H2_after_'+str(s)]) >= 0 for s in range(1,5)))
        if row['state'] == 'MOVING':
            check('moving_zero', float(row['P_output']) == 0 and float(row['energy_served_kWh']) == 0 and row['onboard_H2_before'] == row['onboard_H2_after'])
    for row in events:
        if row['event'] == 'EDGE_ENTER':
            k = cfg['point_names'].index(row['road_state'])
            check('open_edge_entry', not inputs[row['case']]['closed'][k][int(float(row['edge_id']))-1])
    for case in cases:
        check('case_row_count:' + case['case'], sum(r['case'] == case['case'] for r in ledger) == int(case['event_rows']))
    max_mass = max(abs(float(r['mass_error_kg'])) for r in masses)
    check('mass_summary', close(max_mass, summary['max_mass_error_kg'], 1e-20))
    for r in masses:
        check('mass_identity', close(float(r['station_total_kg'])+float(r['onboard_total_kg'])+float(r['consumed_H2_kg']), r['original_total_kg'], 1e-9))
    selected = []
    for line, row in enumerate(ledger, 2):
        if row['case'] in ['CASE-2','CASE-4','CASE-6','CASE-7','CASE-9','CASE-10'] and (row['vehicle_id']=='1' or row['state']=='REFUEL_EVENT' or row['case']=='CASE-6'):
            selected.append(dict(source_csv_line=line, **row))
    write_csv('key_event_ledger_rows.csv', selected)
    write_csv('key_action_event_rows.csv', [dict(source_csv_line=i, **r) for i,r in enumerate(events,2) if r['case'] in ['CASE-2','CASE-4','CASE-7','CASE-9','CASE-10']])
    c2 = [r for r in ledger if r['case']=='CASE-2' and r['state']=='MOVING']
    check('CASE2_12_plus_1', len(c2)==2 and close((float(c2[0]['time_end'])-float(c2[0]['time_start']))*60,12) and close((float(c2[1]['time_end'])-float(c2[1]['time_start']))*60,1))
    check('CASE2_progress', close(c2[0]['physical_progress_after_km'],8) and c2[0]['physical_progress_after_km']==c2[1]['physical_progress_before_km'])
    check('CASE2_arrival', any(r['case']=='CASE-2' and r['event']=='MOVE_COMPLETE' and close(float(r['time_h'])*60,31) for r in events))
    c4 = [r for r in events if r['case']=='CASE-4' and r['event']=='EDGE_ENTER']
    check('CASE4_closure', inputs['CASE-4']['closed'][1][0] is False and inputs['CASE-4']['closed'][2][0] is True)
    check('CASE4_route', [int(float(r['edge_id'])) for r in c4]==[1,2,3] and close(c4[0]['time_h'],1.4) and close(c4[1]['time_h'],1.4+13/60) and c4[1]['road_state']=='M12')
    check('CASE4_progress', any(r['case']=='CASE-4' and r['road_state']=='M12' and r['edge_entry_road_state']=='W1' and close(r['physical_progress_before_km'],4) for r in ledger))
    partition = read_csv(SOURCE / 'option_A_initial_partition.csv')
    inv_source = json.loads((SOURCE / 'actual_inventory_source.json').read_text())
    inv_file = ROOT/'results/task-002-stage2b-b3-smoke/w-oos-v1-preflight/run-001/recovered_msp_inventory.csv'
    check('actual_inventory_source_hash', digest(inv_file)==inv_source['sha256'])
    recovered = next(r for r in read_csv(inv_file) if r['arm']==inv_source['arm'] and int(r['path_id'])==inv_source['path_id'])
    for s,row in enumerate(partition,1):
        c = inputs['CASE-6']
        alloc = sum(h for site,h in zip(c['initial_sites'],c['initial_onboard']) if site==s)
        check('CASE6_site_'+str(s), close(recovered['inventory_site'+str(s)], row['actual_inventory_kg']) and close(row['vehicle_initial_kg'],alloc) and close(float(row['station_initial_kg'])+alloc,row['actual_inventory_kg']))
        check('CASE6_ledger_'+str(s), all(close(r['station_H2_before_'+str(s)],row['station_initial_kg']) for r in ledger if r['case']=='CASE-6'))
    c7 = next(r for r in ledger if r['case']=='CASE-7' and r['state']=='REFUEL_EVENT')
    check('CASE7_instant_transfer', c7['time_start']==c7['time_end'] and close(c7['time_start'],13/60) and close(float(c7['station_H2_before_2'])-float(c7['station_H2_after_2']),10) and close(float(c7['onboard_H2_after'])-float(c7['onboard_H2_before']),10) and c7['from_node']=='14')
    c9 = next(r for r in ledger if r['case']=='CASE-9' and r['state']=='SERVICE')
    used = float(c9['onboard_H2_before'])-float(c9['onboard_H2_after'])
    expected = 66/(.55*33.33)
    check('CASE9_energy_H2', close(c9['P_output'],220) and close(float(c9['time_end'])-float(c9['time_start']),.3) and close(c9['energy_served_kWh'],66) and close(used,expected))
    c10 = [r for r in ledger if r['case']=='CASE-10' and r['state']=='REFUEL_EVENT']
    check('CASE10_shared', [r['status'] for r in c10]==['TRANSFERRED','REJECTED_STATION_INVENTORY'] and [float(r['station_H2_before_1']) for r in c10]==[5,1] and [float(r['station_H2_after_1']) for r in c10]==[1,1] and [float(r['onboard_H2_after']) for r in c10]==[14,5])
    check('CASE10_initial', inputs['CASE-10']['initial_actual_inventory']==[20]*4 and sum(inputs['CASE-10']['initial_onboard'][:2])==15)
    reg = read_csv(SOURCE / 'B2_C_regression.csv')
    check('B2_regression', len(reg)==15 and all(float(r['max_abs_diff_km'])==0 and int(r['unreachable_mismatches'])==0 for r in reg))
    preserved = snapshot() == before
    check('preexisting_worktree_preserved', preserved)
    for p,h in sources.items():
        check('source_unchanged:' + str(p.relative_to(ROOT)), digest(p)==h)
    write_csv('source_manifest.csv', [dict(path=p.relative_to(ROOT).as_posix(),bytes=p.stat().st_size,sha256=h) for p,h in sorted(sources.items())])
    write_csv('verification_checks.csv', checks)
    result = 'PASS' if all(r['result']=='PASS' for r in checks) else 'FAIL'
    values = dict(CASE2_arrival_min=float(c2[-1]['time_end'])*60, CASE4_enter_h=1.4, CASE4_closure_h=1.5,
        CASE4_next_node_h=float(c4[1]['time_h']), CASE4_edge_entries=[1,2,3], CASE6_partition=partition,
        CASE6_max_error_kg=max(abs(float(r['error_kg'])) for r in partition), CASE7_duration_h=0,
        CASE7_transfer_kg=10, CASE7_total_H2_kg=sum(inputs['CASE-7']['initial_actual_inventory']),
        CASE9_energy_kWh=float(c9['energy_served_kWh']), CASE9_used_H2_kg=used, CASE9_expected_H2_kg=expected,
        CASE9_error_kg=used-expected, CASE10_station1_kg=[20,5,1,1], CASE10_total_H2_kg=80,
        existing_cases=len(cases), existing_checks=len(old_checks), max_mass_error_kg=max_mass, max_C_diff_km=0)
    write_json('key_values.json', values)
    write_json('verification_summary.json', dict(B3_DETAILED_CLOSEOUT=result, ANALYSIS_QA=result,
        DATA_PRESERVATION_QA=result, checks=len(checks), failures=[r for r in checks if r['result']=='FAIL'],
        existing_B3_PHYSICS_ENGINE_SMOKE=summary['B3_PHYSICS_ENGINE_SMOKE'], B3_RERUN=False,
        existing_worktree_preserved=preserved, source_count=len(sources), **values))
    print(json.dumps(dict(result=result,checks=len(checks),failures=[r for r in checks if r['result']=='FAIL'],values=values), ensure_ascii=False, indent=2))
    if result!='PASS':
        raise SystemExit(1)


if __name__=='__main__':
    main()
