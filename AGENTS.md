# Agent Instructions

1. Before each task, read `codex_rule/core.md`, `codex_rule/longtask.md`,
   `codex_rule/log.md`, and the current task specification or attached task file.
2. Modify only files required by the current task. Keep protected MSP modules,
   data, and accepted outputs unchanged unless the task explicitly says otherwise.
3. Treat `core.md` and `longtask.md` as read-only unless the current task
   explicitly authorizes rule updates. Update `log.md` only after verified work.
4. Do not invent fallback, mock, placeholder, or replacement research data.
5. Keep `main` for accepted stable versions. Perform development only on the
   task branch named by the user.
6. Git writes are disabled by default. Commit and push the current task branch
   only when the task explicitly authorizes both and every required audit passes.
7. Never modify `main`, create or merge a PR, delete a branch, or force-push.
8. Archive small results under `results/task-xxx/step-xx/run-xxx/`. Keep large
   results under `terminalLoh_wdro/output/` and record path, rows, bytes, and SHA-256.
9. Use a new run number for every rerun. Never overwrite an accepted prior run.
10. GitHub can review only pushed content; report local unpushed work as local-only.
11. Stop without Git writes when an audit fails or a task conflicts with fixed rules.
12. Task prompts may state only goal, allowed files, acceptance criteria, output/run
    id, and Commit/Push authorization; all fixed Git safety rules still apply.
13. Do not run MATLAB, Gurobi, WDRO, or MSP unless explicitly required.
