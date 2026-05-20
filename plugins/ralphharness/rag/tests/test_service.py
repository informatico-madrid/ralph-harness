"""Unit tests for RAGService."""

import json
import os
from pathlib import Path
from unittest import mock

from plugins.ralphharness.rag.config import RAGConfig
from plugins.ralphharness.rag.service import RAGService


class TestRAGServiceDisabled:
    def test_from_config_returns_none_when_disabled(self) -> None:
        with mock.patch.dict(os.environ, {"RALPH_RAG_ENABLED": "false"}, clear=False):
            cfg = RAGConfig.load()
            svc = RAGService.from_config(cfg)
            assert svc is None

    def test_from_config_returns_none_with_no_env(self, tmp_path: Path) -> None:
        cfg = RAGConfig.load(config_path=tmp_path / "nope.md")
        svc = RAGService.from_config(cfg)
        assert svc is None


class TestRAGServiceRetrieval:
    def test_retrieve_graceful_on_error(self) -> None:
        """When RAG is enabled but provider fails, returns empty results."""
        cfg = RAGConfig.load()
        cfg.enabled = True
        cfg.provider = "qdrant"
        cfg.vector_db.endpoint = "http://nonexistent:6333"
        svc = RAGService.from_config(cfg)
        if svc is not None:
            results = svc.retrieve("test query", top_k=3)
            assert results == []


class TestRAGServiceTelemetry:
    def test_retrieval_metrics_logged(self, tmp_cache_dir: Path) -> None:
        """A retrieval attempt writes to retrieval-metrics.log."""
        from plugins.ralphharness.rag import observability

        obs_path = tmp_cache_dir / "smart-ralph" / "rag" / "retrieval-metrics.log"
        # Set XDG_CACHE_HOME so observability writes here
        with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": str(tmp_cache_dir)}):
            observability.record_metric(
                op="retrieve", spec="test", query="hello",
                collection="test_col", top_k=3, provider_used="qdrant",
                embedder_used="local", latency_ms=50, result_count=0, outcome="ok",
            )
        assert obs_path.exists()
        lines = obs_path.read_text().strip().split("\n")
        entry = json.loads(lines[0])
        assert "query_sha256" in entry
        assert entry["latency_ms"] == 50
        assert entry["result_count"] == 0

    def test_metrics_never_store_raw_query(self, tmp_cache_dir: Path) -> None:
        """Raw query text must not appear in metrics."""
        from plugins.ralphharness.rag import observability

        obs_path = tmp_cache_dir / "smart-ralph" / "rag" / "retrieval-metrics.log"
        with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": str(tmp_cache_dir)}):
            observability.record_metric(
                op="retrieve", spec="test", query="password123 supersecret",
                collection="test_col", top_k=3, provider_used="qdrant",
                embedder_used="local", latency_ms=10, result_count=1, outcome="ok",
            )
        content = obs_path.read_text()
        assert "password123" not in content
        assert "supersecret" not in content
