# Long-Running Jobs, Mid-Flight Steering, and Sequential Pipelines (Herdr TUI)

Read this reference when orchestrating multi-minute/hour builds, trainings, or cloud/GPU runs inside Herdr TUI (`herdr` CLI).

## 1. Single Blocking Bash Monitor (Zero Idle LLM Polling)
- Instruct the worker to run a **single blocking bash monitor** (see `herdr-tui-worker/references/long-running-monitor.md`) rather than burning LLM turns on repeated short `sleep` calls.
- The worker's bash monitor records real state transitions (`QUEUED` -> `RUNNING`, smoke gates passed, coarse 15–30m heartbeats, completion) with `herdr-tui-inbox.sh write ... working --summary "<event>"`. These land in `status/<worker-name>.log` and wake nobody; check them with `herdr-tui-inbox.sh tail "$STATE_DIR" <worker-name>` when you want a quick look.

## 2. Out-of-Turn Dead-Man Watchdog (Never Hold `working` Status)
- **Never** park the orchestrator in a foreground `herdr agent wait` or an in-turn `bg_*` shell job that keeps your session `working` and blocks chat. Always end your turn to return to `idle`.
- The detached inbox watcher (`herdr-tui-inbox.sh watch "$STATE_DIR" --detach`) is the dead-man switch: it wakes you when a worker is blocked, stalls idle while its status says working (raise `--stall-min` for long silent jobs), disappears, or when all workers settle. A native out-of-turn timer (`schedule` / `ScheduleWakeup` / `CronCreate`, canceled on completion) is optional in `agy` and `claude`.

## 3. Mid-Flight Steering & Backend Pivoting
When a worker is blocked (`blocked`), stalled on a remote queue, or needs redirection:
1. Inspect live state: `herdr agent get <worker-name>` and `herdr agent read <worker-name> --source recent` (or `herdr pane read "<pane_id>" --lines 80`).
2. If the worker is parked inside a long blocking bash monitor (`working`):
   - Interrupt its active turn cleanly: `herdr agent send-keys <worker-name> esc` (or `ctrl+c` for raw bash foreground commands if needed).
   - Confirm it settled: `herdr agent wait <worker-name> --until idle --timeout 30000`.
   - Submit the updated plan: `herdr agent prompt <worker-name> "<new plan>"`, ensuring superseded remote VMs/jobs and local lockfiles are released.

## 4. Sequential Pipeline Handoff (Stage $N \to N+1$)
1. As soon as stage $N$ finishes (`idle`/`done`), verify `<state-dir>/reports/<worker-N>.md`, clean git commits, and confirm billable remote compute (`colab stop`, cloud GPU) + lockfiles are released.
2. Keep worker $N$'s workspace alive (`idle`) for potential user follow-ups unless asked to close it.
3. Propagate runtime lessons from stage $N$ into stage $N+1$'s handoff spec before starting worker $N+1$.
