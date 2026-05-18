---
name: reviewer-warmup
description: Canonical rules for the external-reviewer bootstrap, liveness heartbeat freshness gate, and convergence detection. This skill is the single source of truth for reviewer-warmup behavior.
version: 0.1.0
user-invocable: false
---

# Reviewer Warmup

Canonical rules for the external-reviewer cold-start bootstrap and heartbeat freshness gate.

## Bootstrap

Before cycle 1, the external-reviewer performs a **full spec-state read** to eliminate cold-start context deficit:

1. Read `chat.md` **in full** (not incrementally from the current line count).
2. Read `.progress.md` fully — parse Completed Tasks, Current Task, Learnings, Blockers sections.
3. Run `git log --oneline` and `git diff --stat` since the spec branch point to see committed changes and overall diff scope.
4. Set `chat.reviewer.lastReadLine = 0` so incremental reads start from the beginning.
5. State a short **spec-state mental model** in cycle 1 output: active signals, completed tasks, current task, overall phase, branch status.
6. Preserve existing HOLD/PENDING/DEADLOCK detection verbatim — if any blocking signal is present, follow the normal coordinator protocol.
7. If `chat.md` is absent (first cycle), skip silently — no error.

## Heartbeat Freshness Gate

**Run BEFORE the existing §4 Convergence Detection.** Prevents false stagnation escalation when the executor has emitted a recent liveness heartbeat.

```
# Heartbeat freshness gate — run BEFORE the existing §4 Convergence Detection
STALENESS_MINUTES = 10

newest = `grep -v '^[[:space:]]*#' <basePath>/signals.jsonl 2>/dev/null \
          | jq -c 'select(.type=="control" and (.signal=="ALIVE" or .signal=="STILL"))' \
          | tail -1`

if newest is empty:                       # no heartbeat ever emitted
    heartbeat_fresh = false                # treat as stale — do not block escalation
else:
    ts  = newest.timestamp                 # ISO 8601
    age_min = (now_epoch - epoch(ts)) / 60
    if epoch(ts) parse failed (malformed):
        heartbeat_fresh = false
    else:
        heartbeat_fresh = age_min < STALENESS_MINUTES

if heartbeat_fresh:
    log "REVIEWER: deferring escalation — fresh executor heartbeat "
        "(age <age_min> min, reason: <newest.reason>)"
    DO NOT write WARNING-progress-stuck / DEADLOCK this cycle
    DO NOT increment the existing §4 `convergence_rounds` counter
    return  # skip §4 Convergence Detection for this cycle
else:
    proceed with existing §4 Convergence Detection (3-round mechanism)
```

**Rules:**
- Fresh heartbeat (< 10 min): suppress stagnation verdict, skip `convergence_rounds` increment, do NOT escalate.
- Stale/absent heartbeat: §4 Convergence Detection runs unchanged (3-round threshold).
- No new time threshold added; convergence rounds counter stays at 3.

## Why This Matters

| Without | With |
|---------|------|
| External-reviewer starts with empty chat.md, needs multiple cycles to accumulate context | Full spec-state read gives reviewer immediate context |
| Long executor reads misread as stagnation, causing false DEADLOCK | Fresh heartbeat suppresses false escalation |
| 30-40 min overhead per spec at cold-start | Immediate momentum from cycle 1 |
| Reviewer cannot distinguish "processing" from "stuck" | Liveness heartbeat signals active work |
