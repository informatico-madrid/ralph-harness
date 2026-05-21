"""Tests for per-spec signal emission (FR-6)."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from plugins.ralphharness.rag.signals import (
    emit_indexing_queued,
    emit_retrieval_complete,
    emit_retrieval_failed,
)


@pytest.fixture()
def spec_dir(tmp_path: Path) -> Path:
    """Create a fake spec directory with signals.jsonl."""
    spec = tmp_path / "specs" / "test-spec"
    spec.mkdir(parents=True)
    (spec / "signals.jsonl").write_text("", encoding="utf-8")
    return spec


def test_emit_retrieval_complete_writes_to_spec_path(
    spec_dir: Path,
) -> None:
    """RETRIEVAL_COMPLETE goes to spec/signals.jsonl, NOT ~/.cache."""
    with patch("plugins.ralphharness.rag.signals._now", return_value="2026-05-21T00:00:00Z"):
        emit_retrieval_complete(spec_dir, collection="specs_tasks", result_count=3)

    lines = spec_dir.joinpath("signals.jsonl").read_text(encoding="utf-8").strip().split("\n")
    assert len(lines) == 1

    entry = json.loads(lines[0])
    assert entry["op"] == "RETRIEVAL_COMPLETE"
    assert entry["spec"] == "test-spec"
    assert entry["phase"] == "retrieval"
    assert entry["collection"] == "specs_tasks"
    assert entry["result_count"] == 3


def test_emit_retrieval_failed_writes_phase(
    spec_dir: Path,
) -> None:
    """RETRIEVAL_FAILED includes phase field (retrieval|indexing)."""
    with patch("plugins.ralphharness.rag.signals._now", return_value="2026-05-21T00:00:00Z"):
        emit_retrieval_failed(spec_dir, reason="timeout", phase="indexing")

    lines = spec_dir.joinpath("signals.jsonl").read_text(encoding="utf-8").strip().split("\n")
    entry = json.loads(lines[0])
    assert entry["op"] == "RETRIEVAL_FAILED"
    assert entry["phase"] == "indexing"
    assert entry["reason"] == "timeout"


def test_emit_indexing_queued_writes_phase(
    spec_dir: Path,
) -> None:
    """INDEXING_QUEUED includes phase=indexing."""
    with patch("plugins.ralphharness.rag.signals._now", return_value="2026-05-21T00:00:00Z"):
        emit_indexing_queued(spec_dir, chunk_count=5)

    lines = spec_dir.joinpath("signals.jsonl").read_text(encoding="utf-8").strip().split("\n")
    entry = json.loads(lines[0])
    assert entry["op"] == "INDEXING_QUEUED"
    assert entry["phase"] == "indexing"
    assert entry["chunk_count"] == 5


def test_emits_dont_contain_raw_query(
    spec_dir: Path,
) -> None:
    """Signals use SHA-256 hash, not raw query."""
    with patch("plugins.ralphharness.rag.signals._now", return_value="2026-05-21T00:00:00Z"):
        emit_retrieval_complete(spec_dir, collection="test", result_count=1, query_sha256="abc123")

    lines = spec_dir.joinpath("signals.jsonl").read_text(encoding="utf-8").strip()
    assert "raw" not in lines.lower()
    assert "abc123" in lines  # query_sha256 is present
