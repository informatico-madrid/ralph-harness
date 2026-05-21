"""Tests for observability — metric registration in service.retrieve."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from plugins.ralphharness.rag.observability import record_metric


@pytest.fixture()
def metrics_file(tmp_path: Path) -> Path:
    """Return a path for the metrics file in a temp directory."""
    return tmp_path / "retrieval-metrics.log"


def test_record_metric_writes_jsonl(metrics_file: Path) -> None:
    """record_metric appends one JSONL line with all required fields."""
    with patch(
        "plugins.ralphharness.rag.observability._metrics_path",
        return_value=metrics_file,
    ):
        record_metric(
            op="retrieve",
            spec="test-spec",
            query="test query",
            collection="specs_tasks",
            top_k=3,
            provider_used="qdrant",
            embedder_used="local",
            latency_ms=150.5,
            result_count=2,
            outcome="ok",
        )

    lines = metrics_file.read_text(encoding="utf-8").strip().split("\n")
    assert len(lines) == 1

    entry = json.loads(lines[0])
    assert entry["op"] == "retrieve"
    assert entry["spec"] == "test-spec"
    assert entry["collection"] == "specs_tasks"
    assert entry["top_k"] == 3
    assert entry["provider_used"] == "qdrant"
    assert entry["embedder_used"] == "local"
    assert entry["latency_ms"] == 150.5
    assert entry["result_count"] == 2
    assert entry["outcome"] == "ok"


def test_record_metric_hashes_query(metrics_file: Path) -> None:
    """record_metric stores SHA-256 of query, never raw query."""
    import hashlib

    expected_hash = hashlib.sha256("test query".encode()).hexdigest()

    with patch(
        "plugins.ralphharness.rag.observability._metrics_path",
        return_value=metrics_file,
    ):
        record_metric(
            op="retrieve",
            spec="test-spec",
            query="test query",
            collection="specs_tasks",
            top_k=3,
            provider_used="qdrant",
            embedder_used="local",
            latency_ms=50.0,
            result_count=0,
            outcome="error",
        )

    entry = json.loads(metrics_file.read_text(encoding="utf-8").strip())
    assert entry["query_sha256"] == expected_hash
    assert "test query" not in entry["query_sha256"]


def test_record_metric_multiple_calls(metrics_file: Path) -> None:
    """Multiple calls append separate JSONL lines."""
    with patch(
        "plugins.ralphharness.rag.observability._metrics_path",
        return_value=metrics_file,
    ):
        for i in range(5):
            record_metric(
                op="retrieve",
                spec="spec",
                query=f"q{i}",
                collection="c",
                top_k=1,
                provider_used="qdrant",
                embedder_used="local",
                latency_ms=i * 10.0,
                result_count=i,
                outcome="ok" if i % 2 == 0 else "error",
            )

    lines = metrics_file.read_text(encoding="utf-8").strip().split("\n")
    assert len(lines) == 5


def test_record_metric_op_index(metrics_file: Path) -> None:
    """record_metric with op=index records correctly."""
    with patch(
        "plugins.ralphharness.rag.observability._metrics_path",
        return_value=metrics_file,
    ):
        record_metric(
            op="index",
            spec="my-spec",
            query="index-specs_tasks",
            collection="specs_tasks",
            top_k=10,
            provider_used="qdrant",
            embedder_used="openai",
            latency_ms=250.0,
            result_count=10,
            outcome="ok",
        )

    entry = json.loads(metrics_file.read_text(encoding="utf-8").strip())
    assert entry["op"] == "index"
    assert entry["query_sha256"] is not None
