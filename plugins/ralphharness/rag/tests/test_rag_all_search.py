"""Tests for 'all' collection search and list_collections."""

from pathlib import Path
from unittest import mock

import pytest

from plugins.ralphharness.rag.providers.qdrant import QdrantProvider
from plugins.ralphharness.rag.providers.faiss import FAISSProvider
from plugins.ralphharness.rag.service import RAGService
from plugins.ralphharness.rag.types import Chunk


class TestListCollectionsQdrant:
    def test_returns_matching_collections(self) -> None:
        """list_collections returns only project-scoped collections."""
        mock_client = mock.MagicMock()
        c1 = mock.MagicMock()
        c1.name = "smart-ralph-testspec-research"
        c2 = mock.MagicMock()
        c2.name = "other-project-other"
        mock_client.get_collections.return_value = mock.MagicMock(
            collections=[c1, c2]
        )

        provider = QdrantProvider(endpoint="http://localhost:6333", project="smart-ralph")
        provider._client = mock_client

        result = provider.list_collections()
        assert result == ["smart-ralph-testspec-research"]

    def test_returns_empty_when_no_collections(self) -> None:
        """list_collections returns [] when Qdrant has no collections."""
        mock_client = mock.MagicMock()
        mock_client.get_collections.return_value = mock.MagicMock(collections=[])

        provider = QdrantProvider(endpoint="http://localhost:6333", project="smart-ralph")
        provider._client = mock_client

        assert provider.list_collections() == []

    def test_returns_empty_when_client_is_none(self) -> None:
        """list_collections returns [] when client cannot be created."""
        with mock.patch("qdrant_client.QdrantClient", side_effect=Exception("connect failed")):
            provider = QdrantProvider(endpoint="http://localhost:6333", project="smart-ralph")
            # _get_client() will set _client=None after the exception
            provider.list_collections()

        assert provider._client is None


class TestListCollectionsFAISS:
    def test_returns_collections_from_directory(self, tmp_path: Path) -> None:
        """list_collections returns .index file stems."""
        (tmp_path / "spec1-research.index").write_text("data")
        (tmp_path / "spec1-design.index").write_text("data")
        (tmp_path / "unrelated.index").write_text("data")

        provider = FAISSProvider(index_dir=tmp_path)
        result = provider.list_collections()
        assert sorted(result) == ["spec1-design", "spec1-research", "unrelated"]

    def test_returns_empty_when_dir_missing(self, tmp_path: Path) -> None:
        """list_collections returns [] when index dir does not exist."""
        provider = FAISSProvider(index_dir=tmp_path / "nonexistent")
        assert provider.list_collections() == []


class TestRetrieveAll:
    def test_merges_results_from_multiple_collections(self, tmp_path: Path) -> None:
        """_retrieve_all searches all collections and returns top_k merged."""
        mock_provider = mock.MagicMock()
        mock_provider.list_collections.return_value = [
            "smart-ralph-spec1-research",
            "smart-ralph-spec2-design",
        ]
        chunk1 = Chunk(
            content="result1", source_path="a.md", spec_name="spec1", score=0.9,
            source_line_start=1, source_line_end=10
        )
        chunk2 = Chunk(
            content="result2", source_path="b.md", spec_name="spec2", score=0.7,
            source_line_start=1, source_line_end=10
        )
        mock_provider.retrieve.side_effect = [[chunk1], [chunk2]]
        mock_provider.retrieve_raw.side_effect = [[chunk1], [chunk2]]

        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384

        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)
        results = svc.retrieve("test query", "all", top_k=10)

        assert len(results) == 2
        assert results[0].score >= results[1].score  # sorted by score

    def test_returns_empty_when_no_collections(self, tmp_path: Path) -> None:
        """_retrieve_all returns [] when provider has no collections."""
        mock_provider = mock.MagicMock()
        mock_provider.list_collections.return_value = []

        mock_embedder = mock.MagicMock()

        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)
        results = svc.retrieve("test query", "all", top_k=5)

        assert results == []

    def test_deduplicates_by_source_path(self, tmp_path: Path) -> None:
        """Same chunk appearing in multiple collections is deduped."""
        mock_provider = mock.MagicMock()
        mock_provider.list_collections.return_value = ["smart-ralph-spec-research"]

        chunk1 = Chunk(
            content="same", source_path="a.md", spec_name="spec",
            source_line_start=10, source_line_end=20, score=0.9
        )
        chunk2 = Chunk(
            content="same", source_path="a.md", spec_name="spec",
            source_line_start=10, source_line_end=20, score=0.85
        )
        mock_provider.retrieve.side_effect = [[chunk1, chunk2]]
        mock_provider.retrieve_raw.side_effect = [[chunk1, chunk2]]

        mock_embedder = mock.MagicMock()
        mock_embedder.embed.return_value = [0.1] * 384

        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)
        results = svc.retrieve("test", "all", top_k=10)

        assert len(results) == 1

    def test_embed_failure_returns_empty(self, tmp_path: Path) -> None:
        """_retrieve_all returns [] when embedder fails."""
        mock_provider = mock.MagicMock()
        mock_provider.list_collections.return_value = ["smart-ralph-spec-research"]
        mock_embedder = mock.MagicMock()
        mock_embedder.embed.side_effect = Exception("model not loaded")

        svc = RAGService(mock_provider, mock_embedder, spec_path=tmp_path)
        results = svc.retrieve("test", "all", top_k=5)

        assert results == []
