# Stage-79 hourly LinDistFlow smoke

- `run-001` is a preserved pre-Gate-B launcher failure and is not accepted.
- `run-002` is the completed Stage-79 diagnostic run.
- Stage-79 used the initially frozen `0.95-1.05 p.u.` voltage bounds and failed Gate B because the base grid was infeasible in all 48 hours.
- The minimum relaxed-diagnostic voltage was `0.915940163768 p.u.` at bus 18 in hours 21 and 45.
- No hosting, integrated-stage, dual/cut, legacy numerical smoke, training, or OOS was run after the Gate-B failure.

Stage-80 supersedes the voltage-bound experiment; Stage-79 remains the provenance record for why the voltage range was reconsidered.
