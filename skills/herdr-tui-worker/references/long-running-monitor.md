# Single Blocking Bash Monitor for Long-Running Jobs (Herdr TUI)

Read this reference when your `herdr-tui-worker` assignment runs a multi-minute/hour build, training, evaluation, or remote cloud/GPU job.

## Rules
1. **Zero LLM polling:** Never burn LLM turns in repeated short `sleep` + status tool calls.
2. **Detached launch + lockfile:** Launch the runner detached (`nohup setsid <runner> > <state-dir>/logs/<job>.log 2>&1 < /dev/null &`), holding any required lockfile (`flock` on `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/locks/<resource>.lock`).
3. **One blocking bash monitor loop:** Supervise the detached PID/remote job inside a single blocking bash loop (with an appropriate tool timeout) that:
   - Records real state changes (`QUEUED` -> `RUNNING`, smoke gate passed, 15–30m coarse heartbeats with completed rows/steps, exit) with `"$INBOX" write "$STATE_DIR" <worker-name> working --summary "<event>"` (it appends to `status/<worker-name>.log`; nobody is woken).
   - Never `herdr agent prompt` the orchestrator from the loop. If the job needs a decision (quota, crash you cannot fix), write `blocked --needs "<what>"`; the orchestrator's watcher wakes it.
   - Exits immediately when the job finishes so you can verify outputs, run analysis, and commit.
4. **Honest exit verification:** Always check the real exit code and output artifacts before reporting completion—never report an early crash as `COMPLETE`.
5. **Clean pivot & compute teardown:**
   - If interrupted (`esc` / `ctrl+c`) and steered onto a new plan by the orchestrator, kill/release superseded local pollers, remote jobs, and lockfiles before starting the replacement run.
   - Always stop billable remote sessions (`colab stop`, cloud VMs) upon completion unless explicitly instructed to keep them alive.
