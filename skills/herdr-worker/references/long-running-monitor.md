# Single Blocking Bash Monitor for Long-Running Jobs

Read this reference when your `herdr-worker` assignment runs a multi-minute/hour build, training, evaluation, or remote cloud/GPU job.

## Rules
1. **Zero LLM polling:** Never burn LLM turns in repeated short `sleep` + status tool calls.
2. **Detached launch + lockfile:** Launch the runner detached (`nohup setsid <runner> > <state-dir>/logs/<job>.log 2>&1 < /dev/null &`), holding any required lockfile (`flock` on `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/locks/<resource>.lock`).
3. **One blocking bash monitor loop:** Supervise the detached PID/remote job inside a single blocking bash loop (with an appropriate tool timeout) that:
   - Resolves `hc` via `command -v hc || echo "$HOME/.local/bin/hc"`.
   - Pushes concise transitions via `hc send <parent-id> "<worker-name> milestone: <event>"` on real state changes (`QUEUED` -> `RUNNING`, smoke gate passed, stage boundary, exit).
   - Emits a coarse heartbeat every 15–30 minutes with concrete progress (e.g., `306/612 rows, 20m elapsed`).
   - Exits immediately when the job finishes so you can verify outputs, run analysis, and commit.
4. **Honest exit verification:** Always check the real exit code and output artifacts before sending a milestone—never report an early crash as completion. If you self-heal and relaunch within scope, send an honest correction milestone immediately.
5. **Clean pivot & compute teardown:**
   - If interrupted (`hc interrupt`) and steered onto a new plan by `<hc from="<parent-id>">`, kill/release superseded local pollers, remote jobs, and lockfiles before starting the replacement run.
   - Always stop billable remote sessions (`colab stop`, cloud VMs) upon completion unless explicitly instructed to keep them alive.
