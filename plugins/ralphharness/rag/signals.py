"""Signal emission for the RAG integration module.

All signals go to spec-specific signals.jsonl with a `phase` field so the
harness can scope filtering (e.g. only SHOW signals from the retrieve phase).

Signal types:
- RETRIEVAL_FAILED: retrieval returned no results or errored (phase=retrieval|indexing)
- INDEXING_QUEUED: a task was queued for async indexing (phase=indexing)
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Literal, Union

logger = logging.getLogger(__name__)

# Accept both Path and str for spec_path (verify commands may pass strings)
_SpecPath = Union[Path, str]


def _norm(p: _SpecPath) -> Path:
    """Normalize a spec path to Path."""
    return Path(p) if isinstance(p, str) else p


def emit(spec_path: _SpecPath, signal_type: str, spec_name: str, **extra: str) -> None:
    """Append a signal event to spec-specific signals.jsonl.

    Args:
        spec_path: Path to the spec directory (signals go here, NOT ~/.cache).
        signal_type: One of RETRIEVAL_FAILED, INDEXING_QUEUED, etc.
        spec_name: The spec being executed.
        **extra: Additional fields (e.g. phase, reason, task_id).
    """
    p = _norm(spec_path)
    path = p / "signals.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)

    entry = {
        "ts": _now(),
        "op": signal_type,
        "spec": spec_name,
        **extra,
    }
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, default=str, separators=(",", ":")) + "\n")
    except OSError as e:
        logger.warning("Failed to write signal %s: %s", signal_type, e)


def emit_retrieval_complete(
    spec_path: _SpecPath,
    collection: str = "",
    result_count: int = 0,
    query_sha256: str = "",
) -> None:
    """Emit a RETRIEVAL_COMPLETE signal.

    Args:
        spec_path: Path to the spec directory.
        collection: Collection name.
        result_count: Number of results returned.
        query_sha256: SHA-256 hash of the query (optional).
    """
    emit(
        spec_path,
        "RETRIEVAL_COMPLETE",
        spec_name=_norm(spec_path).name,
        phase="retrieval",
        collection=collection,
        result_count=result_count,
        query_sha256=query_sha256,
    )


def emit_retrieval_failed(
    spec_path: _SpecPath,
    reason: str,
    phase: Literal["retrieval", "indexing"] = "retrieval",
    collection: str = "",
    query_sha256: str = "",
) -> None:
    """Emit a RETRIEVAL_FAILED signal with phase field.

    Args:
        spec_path: Path to the spec directory.
        reason: Error reason / exception message.
        phase: One of 'retrieval' or 'indexing'.
        collection: Collection name (optional).
        query_sha256: SHA-256 hash of the query (optional).
    """
    emit(
        spec_path,
        "RETRIEVAL_FAILED",
        spec_name=_norm(spec_path).name,
        phase=phase,
        reason=reason,
        collection=collection,
        query_sha256=query_sha256,
    )


def emit_indexing_queued(
    spec_path: _SpecPath,
    spec_name: str = "",
    chunk_count: int = 0,
) -> None:
    """Emit an INDEXING_QUEUED signal with phase field.

    Args:
        spec_path: Path to the spec directory.
        spec_name: Human-readable spec name (defaults to spec_path.name).
        chunk_count: Number of chunks to index.
    """
    if not spec_name:
        spec_name = _norm(spec_path).name
    emit(
        spec_path,
        "INDEXING_QUEUED",
        spec_name=spec_name,
        phase="indexing",
        chunk_count=chunk_count,
    )


def _now() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
