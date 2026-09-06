# B3 checkpoint reproducibility

The B3 checkpoint contains the original deterministic engine, road adapter, provisional configuration, smoke runner, report/closeout scripts, and all 22 compact original run-001 artifacts. It also contains a separate read-only closeout verifier and its accepted output. No solver is implemented.

The original smoke was executed previously. This checkpoint task did not run it again. Inspect case_inputs.json, event_ledger.csv, action_events.csv, mass_balance_ledger.csv and checks.csv to review all 17 saved cases without executing any engine code. The six focused cases are extracted with original CSV line numbers in the final closeout directory.

The existing smoke runner requires Python with numpy, pandas, scipy and h5py. Its full regression/integration setup also requires the locally retained B2 and preflight directories, recovered actual inventory, near_stage_msp_input.mat, stage1_road_edges.csv, the formal road consequence source and frozen W H5 inputs. Their paths, sizes and SHA256 are recorded in the original source manifest and the new closeout source manifest. These protected historical assets are intentionally not copied into this commit. A fresh clone without those local inputs cannot execute the full runner; Git restores the engine and saved evidence, not the excluded data bank.

The read-only verifier uses only the Python standard library and Git, does not import engine/road and never calls Simulator.run. It reads historical files and recalculates arithmetic/hashes. Its retained run-002 path refuses overwrite. A future explicitly authorized repetition must use a new run number and its own current mechanical baseline; the saved verifier also audits the expected development branch and initially empty index. No repetition is needed for this closeout.

The smoke nominal remains PROVISIONAL_PARAMETER: six vehicles, 220 kW, 66.6 kg, 40 km/h, eta_FC=0.55, LHV=33.33 kWh/kg. Engine correctness under supplied action sequences does not establish optimization, rescue effectiveness, formal OOS performance or final parameter adoption.
