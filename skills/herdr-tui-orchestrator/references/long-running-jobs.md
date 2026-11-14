# Long-Running Jobs, Mid-Flight Steering, and Sequential Pipelines (Herdr TUI)

Read this reference when orchestrating multi-minute/hour builds, trainings, or cloud/GPU runs inside Herdr TUI (`herdr` CLI).

## 1. Single Blocking Bash Monitor (Zero Idle LLM Polling)
- Instruct the worker to run a **single blocking bash monitor** (see `herdr-tui-worker/references/long-running-monitor.md`) rather than burning LLM turns on repeated short `sleep` calls.
- For reactive notifications when the orchestrator is parked `idle`, the worker's bash monitor can push real state transitions (`QUEUED` -> `RUNNING`, smoke gates passed, coarse 15–30m heartbeats, completion) via:
  - `herdr agent prompt <orchestrator-agent-name> "<worker-name> milestone: <event>"` (when an orchestrator agent name is provided), and/or
  - Appending timestamped milestones to `<state-dir>/reports/<worker-name>.log` while the orchestrator waits via `herdr agent wait <worker-name>`.

## 2. Optional Dead-Man Safety Timer
- If your host harness supports one-shot timers (`schedule`), arm a coarse safety timer slightly longer than the heartbeat interval (canceling any prior active timer first, and canceling on completion).

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
