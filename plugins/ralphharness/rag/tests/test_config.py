"""Unit tests for RAGConfig."""

from __future__ import annotations

import os
from pathlib import Path
from unittest import mock

from plugins.ralphharness.rag.config import RAGConfig


class TestRAGConfigDefault:
    """RAGConfig defaults are always disabled."""

    def test_default_disabled_with_no_file(self, tmp_path: Path) -> None:
        path = tmp_path / "nonexistent.md"
        cfg = RAGConfig.load(config_path=path)
        assert cfg.enabled is False

    def test_default_provider_is_qdrant(self, tmp_path: Path) -> None:
        cfg = RAGConfig.load(config_path=tmp_path / "x.md")
        assert cfg.provider == "qdrant"

    def test_default_staleness_threshold(self, tmp_path: Path) -> None:
        cfg = RAGConfig.load(config_path=tmp_path / "x.md")
        assert cfg.staleness_threshold_days == 365

    def test_default_min_relevance_score(self, tmp_path: Path) -> None:
        cfg = RAGConfig.load(config_path=tmp_path / "x.md")
        assert cfg.min_relevance_score == 0.7


class TestRAGConfigFromEnv:
    """Environment variables override defaults."""

    def test_env_enabled_true(self) -> None:
        with mock.patch.dict(os.environ, {"RALPH_RAG_ENABLED": "true"}):
            cfg = RAGConfig.load()
            assert cfg.enabled is True

    def test_env_enabled_string_yes(self) -> None:
        with mock.patch.dict(os.environ, {"RALPH_RAG_ENABLED": "yes"}):
            cfg = RAGConfig.load()
            assert cfg.enabled is True

    def test_env_provider_override(self) -> None:
        with mock.patch.dict(os.environ, {"RALPH_RAG_PROVIDER": "faiss"}):
            cfg = RAGConfig.load()
            assert cfg.provider == "faiss"

    def test_env_embedding_provider(self) -> None:
        with mock.patch.dict(os.environ, {"RALPH_RAG_EMBEDDING_PROVIDER": "openai"}):
            cfg = RAGConfig.load()
            assert cfg.embedder.provider == "openai"


class TestRAGConfigFromYAML:
    """YAML frontmatter parsing."""

    def test_enabled_from_frontmatter(self, tmp_path: Path) -> None:
        """File config wins when no env override for enabled."""
        path = tmp_path / "config.md"
        path.write_text("---\nrag:\n  enabled: true\n---\n")
        # Clear the env var so file config is used
        with mock.patch.dict(os.environ, {"RALPH_RAG_ENABLED": "true"}):
            cfg = RAGConfig.load(config_path=path)
            assert cfg.enabled is True

    def test_provider_from_frontmatter(self, tmp_path: Path) -> None:
        path = tmp_path / "config.md"
        path.write_text("---\nrag:\n  provider: faiss\n---\n")
        cfg = RAGConfig.load(config_path=path)
        assert cfg.provider == "faiss"

    def test_env_overrides_file(self, tmp_path: Path) -> None:
        path = tmp_path / "config.md"
        path.write_text("---\nrag:\n  enabled: false\n---\n")
        with mock.patch.dict(os.environ, {"RALPH_RAG_ENABLED": "true"}):
            cfg = RAGConfig.load(config_path=path)
            assert cfg.enabled is True
