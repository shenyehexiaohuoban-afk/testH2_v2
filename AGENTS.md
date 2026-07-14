# Agent Instructions

1. Before each task, read `codex_rule/core.md`, `codex_rule/longtask.md`,
   `codex_rule/log.md`, and the current task specification or attached task file.
2. Modify only files required by the current task. Keep protected MSP modules,
   data, and accepted outputs unchanged unless the task explicitly says otherwise.
3. Treat `core.md` and `longtask.md` as read-only. Update `log.md` only after a
   task has actually completed and been verified.
4. Do not invent fallback, mock, placeholder, or replacement research data.
5. Do not automatically execute Git write operations, including `git init`,
   `git add`, `git commit`, `git push`, `git pull`, branch creation, or PR creation.
6. Do not run MATLAB, Gurobi, WDRO, or MSP unless the current task explicitly
   requires that execution.
