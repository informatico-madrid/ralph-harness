"""Signal emission for the RAG integration module.

All signals go to signals.jsonl with a `phase` field so the harness
can scope filtering (e.g. only SHOW signals from the retrieve phase).

Signal types:
- RETRIEVAL_FAILED: retrieval returned no results or errored (phase=retrieve)
- INDEXING_QUEUED: a task was queued for async indexing (phase=index)
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)


def emit(signal_type: str, spec_name: str, **extra: str) -> None:
    """Append a signal event to signals.jsonl.

    Args:
        signal_type: One of RETRIEVAL_FAILED, INDEXING_QUEUED, etc.
        spec_name: The spec being executed.
        **extra: Additional fields (e.g. phase, reason, task_id).
    """
    phase_dir = Path.home() / ".cache" / "smart-ralph"
    path = phase_dir / "signals.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)

    entry = {
        "ts": _now(),
        "op": signal_type,
        "spec": spec_name,
        **extra,
    }
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, default=str) + "\n")
    except OSError as e:
        logger.warning("Failed to write signal %s: %s", signal_type, e)


def _now() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
