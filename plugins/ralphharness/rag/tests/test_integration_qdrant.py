"""End-to-end integration test against a real Qdrant instance.

Requires QDRANT_URL env var pointing to a running Qdrant server.
Skips (exit 77) if not set.

Uses a deterministic mock embedder -- verifies Qdrant round-trip,
not the quality of the embedding model.
"""

from __future__ import annotations

import hashlib
import math
import os
from typing import Any

import pytest

from typing import Any

from plugins.ralphharness.rag.embedder.base import Embedder, EmbedderError
from plugins.ralphharness.rag.providers.qdrant import QdrantProvider
from plugins.ralphharness.rag.types import Chunk

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
def qdrant_url() -> str:
    """Return QDRANT_URL or skip the entire module."""
    url = os.environ.get("QDRANT_URL", "")
    if not url:
        pytest.skip("QDRANT_URL required for integration tests")
    return url


@pytest.fixture(scope="module")
def provider(qdrant_url: str) -> Any:
    """QdrantProvider with test collection prefix."""
    p = QdrantProvider(endpoint=qdrant_url, prefix="integ_")
    # Force-delete any stale collection with wrong dimensions
    try:
        client = p._get_client()
        client.delete_collection(p._collection_name(p._project, TEST_COLLECTION))
    except Exception:
        pass
    p._ensure_collection(TEST_COLLECTION, dimensions=VECTOR_DIM)
    yield p
    # Cleanup: delete test collection
    try:
        client = p._get_client()
        client.delete_collection(p._collection_name(p._project, TEST_COLLECTION))
    except Exception:
        pass


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
