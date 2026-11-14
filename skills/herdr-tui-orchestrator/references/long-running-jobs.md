# Long-Running Jobs, Mid-Flight Steering, and Sequential Pipelines (Herdr TUI)

Read this reference when orchestrating multi-minute/hour builds, trainings, or cloud/GPU runs inside Herdr TUI (`herdr` CLI).

## 1. Single Blocking Bash Monitor (Zero Idle LLM Polling)
- Instruct the worker to run a **single blocking bash monitor** (see `herdr-tui-worker/references/long-running-monitor.md`) rather than burning LLM turns on repeated short `sleep` calls.
- For reactive notifications when the orchestrator is parked `idle`, the worker's bash monitor can push real state transitions (`QUEUED` -> `RUNNING`, smoke gates passed, coarse 15–30m heartbeats, completion) via:
  - `herdr agent prompt <orchestrator-agent-name> "<worker-name> milestone: <event>"` (into your `idle` orchestrator pane), and/or
  - Appending timestamped milestones to `<state-dir>/reports/<worker-name>.log`.

## 2. Out-of-Turn Dead-Man Watchdog / Safety Timer (Never Hold `working` Status)
- **Never** park the orchestrator in a foreground `herdr agent wait` or an in-turn `bg_*` shell job that keeps your session `working` and blocks chat. Always end your turn to return to `idle`.
- Use either a native out-of-turn timer (`schedule` / `ScheduleWakeup` / `CronCreate`, canceled on completion) or a fully detached `nohup setsid` background shell job (`</dev/null >>"<state-dir>/logs/watch.log" 2>&1 &`) that runs `herdr agent wait <worker-name>` and nudges `<orchestrator-agent-name>` via `herdr agent prompt`.

## 3. Mid-Flight Steering & Backend Pivoting
When a worker is blocked (`blocked`), stalled on a remote queue, or needs redirection:
1. Inspect live state: `herdr agent get <worker-name>` and `herdr agent read <worker-name> --source recent` (or `herdr pane read "<pane_id>" --lines 80`).
2. If the worker is parked inside a long blocking bash monitor (`working`):
   - Interrupt its active turn cleanly: `herdr agent send-keys <worker-name> esc` (or `ctrl+c` for raw bash foreground commands if needed).
   - Confirm it settled: `herdr agent wait <worker-name> --state idle`.
   - Submit the updated plan: `herdr agent prompt <worker-name> "<new plan>"`, ensuring superseded remote VMs/jobs and local lockfiles are released.

## 4. Sequential Pipeline Handoff (Stage $N \to N+1$)
1. As soon as stage $N$ finishes (`idle`/`done`), verify `<state-dir>/reports/<worker-N>.md`, clean git commits, and confirm billable remote compute (`colab stop`, cloud GPU) + lockfiles are released.
2. Keep worker $N$'s pane/tab alive (`idle`) for potential user follow-ups unless asked to close it.
3. Propagate runtime lessons from stage $N$ into stage $N+1$'s handoff spec before starting worker $N+1$.
