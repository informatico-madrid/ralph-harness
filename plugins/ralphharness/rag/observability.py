"""Per-call telemetry for RAG operations.

Records metrics to `~/.cache/smart-ralph/rag/retrieval-metrics.log` as
JSONL lines. Query is ALWAYS hashed with SHA-256 — never stored in raw
form.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

_DEFAULT_METRICS_DIR = Path.home() / ".cache" / "smart-ralph" / "rag"
_METRICS_FILE = _DEFAULT_METRICS_DIR / "retrieval-metrics.log"


def _metrics_path() -> Path:
    """Resolve the metrics file path.

    Uses XDG_CACHE_HOME or ~/.cache/smart-ralph/rag/retrieval-metrics.log.
    """
    xdg = os.environ.get("XDG_CACHE_HOME")
    if xdg:
        return Path(xdg) / "smart-ralph" / "rag" / "retrieval-metrics.log"
    return _METRICS_FILE


def _ensure_dir(path: Path):
    """Ensure the parent directory of a path exists."""
    path.parent.mkdir(parents=True, exist_ok=True)


def record_metric(
    op: str,
    spec: str,
    query: str,
    collection: str,
    top_k: int,
    provider_used: str,
    embedder_used: str,
    latency_ms: float,
    result_count: int,
    outcome: str,
):
    """Record a per-call metric to retrieval-metrics.log.

    Hashes the query with SHA-256 (NEVER stores raw query). Appends one
    JSONL line to the metrics file.

    Args:
        op: Operation type ("retrieve" or "index").
        spec: Spec name.
        query: Original query (hashed before storage).
        collection: Collection name.
        top_k: Number of requested results.
        provider_used: Provider name ("qdrant" or "faiss").
        embedder_used: Embedder name ("local", "openai", "azure").
        latency_ms: Elapsed time in milliseconds.
        result_count: Number of results returned.
        outcome: "ok" or "error".
    """
    try:
        query_hash = hashlib.sha256(query.encode()).hexdigest()
    except Exception:
        query_hash = "ERROR"

    line = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "op": op,
        "spec": spec,
        "query_sha256": query_hash,
        "collection": collection,
        "top_k": top_k,
        "provider_used": provider_used,
        "embedder_used": embedder_used,
        "latency_ms": round(latency_ms, 1),
        "result_count": result_count,
        "outcome": outcome,
    }

    path = _metrics_path()
    _ensure_dir(path)

    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(line) + "\n")
    except Exception as e:
        logger.warning("Failed to write metric: %s", e)
