"""End-to-end integration test against a fake Qdrant instance.

Uses an in-memory mock Qdrant server to simulate HTTP API responses.
Tests verify Qdrant round-trip (upsert/search/delete) without requiring
a running Qdrant server or Docker.

Uses a deterministic mock embedder -- verifies Qdrant round-trip,
not the quality of the embedding model.
"""

from __future__ import annotations

import hashlib
import math
from typing import Any
from unittest.mock import patch

import pytest

from plugins.ralphharness.rag.embedder.base import Embedder, EmbedderError
from plugins.ralphharness.rag.providers.qdrant import QdrantProvider
from plugins.ralphharness.rag.types import Chunk

# ---------------------------------------------------------------------------
# Fake Qdrant server (in-memory, no HTTP required)
# ---------------------------------------------------------------------------

class FakePoint:
    """Mock Qdrant point for search results."""

    def __init__(self, point_id: int, vector: list[float], score: float, payload: dict):
        self.id = point_id
        self.vector = vector
        self.score = score
        self.payload = payload


class FakeCollectionInfo:
    """Mock collection metadata."""

    def __init__(self, name: str):
        self.name = name


class FakeCollectionsResponse:
    """Mock response from get_collections."""

    def __init__(self, names: list[str]):
        self.collections = [FakeCollectionInfo(n) for n in names]


class FakeQdrantClient:
    """In-memory Qdrant client simulator for testing."""

    def __init__(self, url: str = "", api_key: str = "", timeout: int = 10):
        self.url = url
        self.api_key = api_key
        self.timeout = timeout
        self._collections: dict[str, dict[int, tuple[list[float], dict]]] = {}

    def get_collections(self) -> FakeCollectionsResponse:
        return FakeCollectionsResponse(list(self._collections.keys()))

    def create_collection(self, collection_name: str, vectors_config: Any) -> None:
        if collection_name not in self._collections:
            self._collections[collection_name] = {}

    def delete_collection(self, collection_name: str) -> None:
        self._collections.pop(collection_name, None)

    def upsert(
        self, collection_name: str, points: list, wait: bool = True
    ) -> dict:
        if collection_name not in self._collections:
            self._collections[collection_name] = {}
        for point in points:
            point_id = point.id
            vector = point.vector
            payload = point.payload if hasattr(point, "payload") else {}
            self._collections[collection_name][point_id] = (vector, payload)
        return {"status": "ok"}

    def query_points(
        self,
        collection_name: str,
        query: list[float],
        limit: int = 10,
        score_threshold: float | None = None,
    ) -> Any:
        """Search using cosine similarity."""
        if collection_name not in self._collections:
            return type("Response", (), {"points": []})()

        results = []
        for point_id, (vector, payload) in self._collections[collection_name].items():
            # Cosine similarity
            dot = sum(a * b for a, b in zip(query, vector))
            mag_q = sum(v ** 2 for v in query) ** 0.5
            mag_v = sum(v ** 2 for v in vector) ** 0.5
            score = dot / (mag_q * mag_v) if mag_q > 0 and mag_v > 0 else 0.0
            if score_threshold is None or score >= score_threshold:
                results.append(FakePoint(point_id, vector, score, payload))

        results.sort(key=lambda x: x.score, reverse=True)
        return type("Response", (), {"points": results[:limit]})()

    def search(
        self,
        collection_name: str,
        query_vector: list[float],
        limit: int = 10,
        score_threshold: float | None = None,
    ) -> list:
        """Alias for query_points (compatibility)."""
        response = self.query_points(collection_name, query_vector, limit, score_threshold)
        return response.points if hasattr(response, "points") else response


# ---------------------------------------------------------------------------
# Deterministic mock embedder (fixed 384-dim, reproducible unit vectors)
# ---------------------------------------------------------------------------

VECTOR_DIM = 384


class DeterministicEmbedder(Embedder):
    """Embedder that produces deterministic unit vectors from text."""

    @property
    def dimensions(self) -> int:
        return VECTOR_DIM

    def embed(self, text: str) -> list[float]:
        raw: list[float] = []
        current = hashlib.sha256(text.encode()).digest()
        while len(raw) < self.dimensions:
            current = hashlib.sha256(current).digest()
            for b in current:
                if len(raw) >= self.dimensions:
                    break
                raw.append(b / 255.0 - 0.5)
        norm = (sum(v * v for v in raw)) ** 0.5 or 1.0
        return [v / norm for v in raw]

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        results = [self.embed(t) for t in texts]
        if len(results) != len(texts):
            raise EmbedderError(
                f"Batch length mismatch: in={len(texts)} out={len(results)}"
            )
        return results

    def health_check(self) -> dict[str, Any]:
        return {"status": "ok"}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

TEST_COLLECTION = "test_integration_rag"


@pytest.fixture(scope="module")
def fake_qdrant_client() -> FakeQdrantClient:
    """Create a fake Qdrant client that stores data in memory."""
    return FakeQdrantClient(url="http://localhost:6333")


@pytest.fixture(scope="module")
def provider(fake_qdrant_client: FakeQdrantClient) -> Any:
    """QdrantProvider with mocked QdrantClient (in-memory)."""
    with patch("qdrant_client.QdrantClient") as mock_class:
        mock_class.return_value = fake_qdrant_client
        p = QdrantProvider(endpoint="http://localhost:6333", prefix="integ_")
        # Force-delete any stale collection
        client = p._get_client()
        client.delete_collection(p._collection_name(p._project, TEST_COLLECTION))
        p._ensure_collection(TEST_COLLECTION, dimensions=VECTOR_DIM)
        yield p
        # Cleanup — don't suppress failures; fake client shouldn't fail
        try:
            client.delete_collection(p._collection_name(p._project, TEST_COLLECTION))
        except Exception:
            pass  # teardown: collection may already be gone


@pytest.fixture(scope="module")
def embedder() -> DeterministicEmbedder:
    return DeterministicEmbedder()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_qdrant_health(provider: QdrantProvider) -> None:
    """Provider health_check returns True against live Qdrant."""
    result = provider.health_check()
    assert result is True


def test_index_and_retrieve(
    provider: QdrantProvider,
    embedder: DeterministicEmbedder,
) -> None:
    """Index 3 chunks, retrieve query matching one chunk, assert score > 0.5."""
    chunks = [
        Chunk(content="alpha", source_path="test.md", spec_name="test"),
        Chunk(content="beta", source_path="test.md", spec_name="test"),
        Chunk(content="gamma", source_path="test.md", spec_name="test"),
    ]

    # Attach vectors (RAGService normally does this before calling provider.index)
    vectors = embedder.embed_batch([c.content for c in chunks])
    for c, v in zip(chunks, vectors):
        c.vector = v

    count = provider.index(chunks, TEST_COLLECTION)
    assert count == 3, f"Expected 3 indexed, got {count}"

    query_vec = embedder.embed("alpha")
    results = provider.retrieve(query_vec, TEST_COLLECTION, top_k=3)

    assert len(results) >= 1, "Expected at least 1 result"
    assert results[0].content == "alpha", (
        f"Expected top result 'alpha', got '{results[0].content}'"
    )
    assert results[0].score is not None and results[0].score > 0.5, (
        f"Expected score > 0.5, got {results[0].score}"
    )


def test_retrieve_empty_collection(provider: QdrantProvider) -> None:
    """Retrieving from a non-existent collection returns empty."""
    vec = [0.0] * VECTOR_DIM
    results = provider.retrieve(vec, "nonexistent_collection_xyz", top_k=3)
    assert results == []
