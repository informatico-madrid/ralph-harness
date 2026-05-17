
### [task-1.8] Update docs: chat.md legend, signals.jsonl schema, coordinator-pattern.md
- status: PASS
- severity: none
- reviewed_at: 2026-05-17T22:09:04Z
- criterion_failed: none
- evidence: |
  $ grep -Eqi 'heartbeat|liveness' plugins/ralphharness/templates/chat.md && \
    grep -Eqi 'ALIVE|STILL' plugins/ralphharness/templates/signals.jsonl && \
    grep -Eqi 'heartbeat' plugins/ralphharness/references/coordinator-pattern.md && echo PASS
  PASS
  
  3 docs actualizados:
  - chat.md: ALIVE/STILL heartbeat legend actualizado
  - signals.jsonl: heartbeat schema comment añadido
  - coordinator-pattern.md: heartbeat row actualizado (non-blocking + signals.jsonl transport)
- fix_hint: N/A
- resolved_at: 2026-05-17T22:09:04Z

### [task-1.9] POC Checkpoint: heartbeat shape valid + non-blocking
- status: PASS
- severity: none
- reviewed_at: 2026-05-17T22:12:14Z
- criterion_failed: none
- evidence: |
  $ echo '{"type":"control","signal":"ALIVE",...}' | jq -e . >/dev/null && \
    git diff --quiet -- lib-signals.sh condense-context.sh lib-context.sh && echo PASS
  PASS
  
  heartbeat JSON passes jq -e validation;
  lib-signals.sh, condense-context.sh, lib-context.sh byte-unchanged.
  Non-blocking proof: ALIVE/STILL no son HOLD|PENDING|URGENT|DEADLOCK,
  ignorados por active_signal_count().
- fix_hint: N/A
- resolved_at: 2026-05-17T22:12:14Z

### [task-2.1] Tighten heartbeat + gate prose to match surrounding style
- status: PASS
- severity: none
- reviewed_at: 2026-05-17T22:18:34Z
- criterion_failed: none
- evidence: |
  $ grep -q 'See skill: reviewer-warmup' plugins/ralphharness/agents/external-reviewer.md && \
    grep -q 'ALIVE' plugins/ralphharness/agents/spec-executor.md && echo PASS
  PASS
  
  Phase 2 — refactor concisión:
  - skill pointer presente (Sections 0 y 4)
  - ALIVE heartbeat presente en spec-executor.md
  - No duplicated rule text más allá de summary + skill pointer
- fix_hint: N/A
- resolved_at: 2026-05-17T22:18:34Z

### [task-3.1] Create test-reviewer-warmup.bats — heartbeat shape + non-regression + emission
- status: PASS
- severity: none
- reviewed_at: 2026-05-17T22:28:45Z
- criterion_failed: none
- evidence: |
  $ bats plugins/ralphharness/tests/test-reviewer-warmup.bats
  20 tests, 0 failed — all ok (incl. heartbeat-shape, active_signal_count, executor-emission grep)
- fix_hint: N/A
- resolved_at: 2026-05-17T22:28:45Z

### [task-3.2] Add freshness-gate simulation tests (fresh / stale / skip-increment / empty)
- status: PASS
- severity: none
- reviewed_at: 2026-05-17T22:28:45Z
- criterion_failed: none
- evidence: |
  Tests 4-9: freshness-gate fresh/stale/empty scenarios — 6 tests all ok
- fix_hint: N/A
- resolved_at: 2026-05-17T22:28:45Z

### [task-3.3] Add bootstrap, byte-stable guard, skill, reference, export, docs grep tests
- status: PASS
- severity: none
- reviewed_at: 2026-05-17T22:28:45Z
- criterion_failed: none
- evidence: |
  Tests 10-19: bootstrap, byte-stable, skill, export, docs grep — all ok (10 tests)
  Tests 1-20: full suite 20/20 pass
- fix_hint: N/A
- resolved_at: 2026-05-17T22:28:45Z
