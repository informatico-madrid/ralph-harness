"""Unit tests for RAGService."""

import hashlib
import json
import os
from pathlib import Path
from unittest import mock

import pytest

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
    def test_retrieve_graceful_on_embedder_error(self, tmp_path: Path) -> None:
        """Embedder failure -> empty results, no crash."""
        mock_provider = mock.MagicMock()
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.side_effect = Exception("embedder boom")
        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)
        results = svc.retrieve("test query", collection="test_col", top_k=3)
        assert results == []
        mock_provider.retrieve.assert_not_called()

    def test_retrieve_graceful_on_provider_error(self, tmp_path: Path) -> None:
        """Provider failure -> empty results, no crash."""
        mock_provider = mock.MagicMock()
        mock_provider.retrieve.side_effect = Exception("provider boom")
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384
        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)
        results = svc.retrieve("test query", collection="test_col", top_k=3)
        assert results == []

    def test_retrieve_graceful_on_timeout_error(self, tmp_path: Path) -> None:
        """TimeoutError -> empty results, no crash."""
        mock_provider = mock.MagicMock()
        mock_provider.retrieve.side_effect = TimeoutError("timed out")
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384
        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)
        results = svc.retrieve("test query", collection="test_col", top_k=3)
        assert results == []


class TestRAGServiceTelemetry:
    def test_record_metric_called_on_success(self, tmp_path: Path) -> None:
        """service.retrieve() calls record_metric with correct params."""
        mock_provider = mock.MagicMock()
        mock_provider.retrieve.return_value = []
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384
        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)

        with mock.patch(
            "plugins.ralphharness.rag.service.record_metric"
        ) as mock_record:
            svc.retrieve("hello", "execution_memory", 3)

        mock_record.assert_called_once()
        call_kwargs = mock_record.call_args.kwargs
        assert call_kwargs["outcome"] == "ok"
        assert call_kwargs["query"] == "hello"
        assert call_kwargs["collection"] == "execution_memory"
        assert call_kwargs["top_k"] == 3
        assert call_kwargs["result_count"] == 0

    def test_record_metric_called_on_error(self, tmp_path: Path) -> None:
        """service.retrieve() calls record_metric with outcome='error' on failure."""
        mock_provider = mock.MagicMock()
        mock_provider.retrieve.side_effect = Exception("boom")
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384
        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)

        with mock.patch(
            "plugins.ralphharness.rag.service.record_metric"
        ) as mock_record:
            svc.retrieve("failing query", "test_col", 5)

        mock_record.assert_called_once()
        call_kwargs = mock_record.call_args.kwargs
        assert call_kwargs["outcome"] == "error"
        assert call_kwargs["result_count"] == 0

    def test_emit_retrieval_complete_called_on_success(
        self, tmp_path: Path
    ) -> None:
        """Success path emits RETRIEVAL_COMPLETE signal."""
        mock_provider = mock.MagicMock()
        mock_provider.retrieve.return_value = []
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384
        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)

        with mock.patch(
            "plugins.ralphharness.rag.service.emit_retrieval_complete"
        ) as mock_emit:
            svc.retrieve("hello", "execution_memory", 3)

        mock_emit.assert_called_once()
        call_args = mock_emit.call_args
        # emit_retrieval_complete(spec_path, collection, result_count) -> positional args
        assert call_args.args[0] == tmp_path
        assert call_args.args[1] == "execution_memory"
        assert call_args.args[2] == 0

    def test_emit_retrieval_failed_called_on_failure(
        self, tmp_path: Path
    ) -> None:
        """Failure path emits RETRIEVAL_FAILED with phase='retrieval'."""
        mock_provider = mock.MagicMock()
        mock_provider.retrieve.side_effect = Exception("connection refused")
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384
        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)

        with mock.patch(
            "plugins.ralphharness.rag.service.emit_retrieval_failed"
        ) as mock_emit:
            svc.retrieve("hello", "execution_memory", 3)

        mock_emit.assert_called_once()
        call_args = mock_emit.call_args
        # emit_retrieval_failed(spec_path, reason, phase) -> spec_path positional, others keyword
        assert call_args.args[0] == tmp_path
        assert call_args.kwargs["phase"] == "retrieval"
        assert call_args.kwargs["reason"] == "connection refused"

    def test_no_emit_retrieval_complete_on_failure(
        self, tmp_path: Path
    ) -> None:
        """Failure path does NOT emit RETRIEVAL_COMPLETE."""
        mock_provider = mock.MagicMock()
        mock_provider.retrieve.side_effect = Exception("boom")
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384
        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)

        with mock.patch(
            "plugins.ralphharness.rag.service.emit_retrieval_complete"
        ) as mock_emit_complete:
            svc.retrieve("hello", "test_col", 3)

        mock_emit_complete.assert_not_called()

    def test_metrics_never_store_raw_query_in_log(
        self, tmp_path: Path
    ) -> None:
        """Per-call metrics log must contain query_sha256, not raw query."""
        mock_provider = mock.MagicMock()
        mock_provider.retrieve.return_value = []
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384
        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)

        obs_path = tmp_path / "smart-ralph" / "rag" / "retrieval-metrics.log"
        with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": str(tmp_path)}):
            with mock.patch(
                "plugins.ralphharness.rag.service.emit_retrieval_complete"
            ):
                svc.retrieve("password123 supersecret", "test_col", 3)

        assert obs_path.exists()
        content = obs_path.read_text()
        assert "password123" not in content
        assert "supersecret" not in content
        entry = json.loads(content.strip().split("\n")[0])
        assert "query_sha256" in entry
        assert entry["query_sha256"] == hashlib.sha256(
            b"password123 supersecret"
        ).hexdigest()
