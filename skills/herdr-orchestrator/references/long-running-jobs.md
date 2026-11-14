# Long-Running Jobs, Mid-Flight Steering, and Sequential Pipelines

Read this reference when orchestrating multi-minute/hour builds, trainings, or cloud/GPU runs (`colab`, `kaggle`, remote SSH).

## 1. Proactive Milestone Push (Zero Idle LLM Polling)
- Instruct the worker to run a **single blocking bash monitor** (see `~/.agents/skills/herdr-worker/references/long-running-monitor.md`) that pushes `hc send $HC_TERMINAL_ID "<worker-name> milestone: <event>"` **only** on real state transitions:
  - Job launched / `QUEUED` -> `RUNNING`
  - Sanity or smoke gates passed
  - Coarse 15–30 min heartbeats with concrete progress (rows/steps, elapsed time)
  - Terminal artifact download + final verified handoff
- **No duplicate watchers:** Never run a separate `hc run --bg` watcher script on a job whose worker already runs its own bash milestone loop. Use an external bash watcher **only** for non-agent processes or legacy workers that cannot push milestones themselves.
- **High-frequency cron polling (opt-in only):** Use a short-interval `schedule` cron (e.g., `* * * * *`) **only** when the user explicitly asks for fixed-interval heartbeats.

## 2. Out-of-Turn Dead-Man Watchdog / Safety Timer (Never Hold `working` Status)
- **Never** hold the orchestrator's turn open with a foreground `hc wait` or an in-turn `bg_*` shell job that keeps the orchestrator in `working` (`waiting on 1 job`). Always end your turn so `$HC_TERMINAL_ID` returns to `idle`.
- Choose whichever out-of-turn safety net fits your harness:
  1. **Native out-of-turn timer (`schedule` / `ScheduleWakeup` / `CronCreate`):** Arm a one-shot timer slightly longer than the worker's heartbeat interval (e.g., `DurationSeconds: 2100` for a 20m heartbeat, `TimerCondition: "any"`). Always cancel any prior active timer before re-arming, and cancel on completion.
  2. **Detached `hc` watchdog (`../scripts/herdr-watch.sh`):** In harnesses without out-of-turn timers (e.g. `omp`/`codex`), launch `<skills-dir>/herdr-orchestrator/scripts/herdr-watch.sh "$HC_TERMINAL_ID" "<state-dir>/logs/watch.log" <worker-name>` under `hc run --bg --rm --no-notify` so your turn ends in `<50ms`, exit reasons are logged to `watch.log`, and `done`-state orchestrators are nudged cleanly (never use `hc send --if idle`, which fails with exit 10 when status is `done`).

## 3. Mid-Flight Steering & Backend Pivoting
When woken by a milestone, `<hc> ... is blocked`, queue stall, or user pivot:
1. Inspect live state: `hc get <worker-name>` and `hc read --lines 80 <worker-name>`.
2. If the worker is parked inside a blocking bash monitor (`working`) and needs immediate redirection:
   - Run `hc interrupt <worker-name>` to stop its current turn/tool call without killing the session.
   - Confirm it settled (`hc wait <worker-name>` -> `idle`).
   - Send the updated plan (`hc send <worker-name> "<new plan>"`), ensuring any superseded remote VM/job or local lockfile is released so quota is not wasted.

## 4. Sequential Pipeline Handoff (Stage $N \to N+1$)
When stages share GPU quota, a resource lockfile (`locks/<resource>.lock`), or downstream artifacts:
1. As soon as stage $N$ reports `COMPLETE`, verify its outputs, row counts, clean git commits, and confirm billable remote compute (`colab stop`, cloud GPU) + locks are released.
2. Leave worker $N$ parked (`idle`) for potential user follow-ups unless asked to clean up.
3. Propagate runtime lessons from stage $N$ into stage $N+1$'s handoff spec before launching worker $N+1$.
