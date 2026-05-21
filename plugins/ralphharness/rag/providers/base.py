"""Abstract base class for vector database providers.

Concrete providers: QdrantProvider, FAISSProvider.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from ..types import Chunk


class VectorDBProvider(ABC):
    """Abstract base class for vector database providers.

    All methods are synchronous — the service layer (RAGService)
    orchestrates async embedding before calling provider methods.
    """

    @abstractmethod
    def health_check(self) -> bool:
        """Check if the vector database is reachable.

        Returns:
            True if reachable, False otherwise.
        """

    @abstractmethod
    def retrieve(self, query_vec: list[float], collection: str, top_k: int = 3) -> list[Chunk]:
        """Retrieve relevant chunks for an embedding vector.

        The caller (RAGService) is responsible for embedding the text
        query before calling this method.

        Args:
            query_vec: Pre-computed embedding vector.
            collection: Target collection name.
            top_k: Number of results to return.

        Returns:
            List of chunks ranked by relevance score.
        """

    @abstractmethod
    def index(self, chunks: list[Chunk], collection: str) -> int:
        """Index a batch of chunks into a collection.

        Args:
            chunks: Chunks to index (each must have a ``vector``
                attribute set by the service layer).
            collection: Target collection name.

        Returns:
            Number of chunks successfully indexed.
        """

    @abstractmethod
    def list_collections(self) -> list[str]:
        """List all collection names available in this provider.

        Returns:
            List of collection names.
        """

    def _retrieve_raw(
        self, query_vec: list[float], collection_name: str, top_k: int = 3
    ) -> list[Chunk]:
        """Retrieve from a fully-qualified collection name (no prefix transformation).

        Override this in providers that apply name transformations (e.g. Qdrant).
        The default implementation calls ``retrieve()`` for compatibility.
        """
        return self.retrieve(query_vec, collection_name, top_k)
