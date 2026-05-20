"""Abstract base class for vector database providers.

Concrete providers: QdrantProvider, FAISSProvider.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from ..types import Chunk


class VectorDBProvider(ABC):
    """Abstract base class for vector database providers.

    All providers must implement retrieve, index, and health_check.
    """

    @abstractmethod
    async def retrieve(self, query: str, collection: str, top_k: int = 3) -> list[Chunk]:
        """Retrieve relevant chunks for a query.

        Args:
            query: Search query string.
            collection: Target collection name.
            top_k: Number of results to return.

        Returns:
            List of chunks ranked by relevance score.
        """

    @abstractmethod
    async def index(self, chunks: list[Chunk], collection: str) -> int:
        """Index a batch of chunks into a collection.

        Args:
            chunks: Chunks to index.
            collection: Target collection name.

        Returns:
            Number of chunks successfully indexed.
        """

    @abstractmethod
    async def health_check(self) -> dict[str, Any]:
        """Check the health of the vector database.

        Returns:
            Dict with status, latency_ms, and provider-specific details.
        """
