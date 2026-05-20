"""Qdrant vector database provider.

Primary provider — uses qdrant_client QdrantClient for HTTP REST API.
"""

from __future__ import annotations

import logging
from typing import Any

from .base import VectorDBProvider

logger = logging.getLogger(__name__)


class QdrantProvider(VectorDBProvider):
    """Qdrant HTTP REST provider.

    Uses qdrant_client.QdrantClient to connect to a Qdrant server.
    Collection names get a project-level prefix.
    """

    def __init__(self, endpoint: str, api_key: str = "", prefix: str = ""):
        """Initialize the Qdrant provider.

        Args:
            endpoint: Qdrant server URL (e.g. "http://localhost:6333").
            api_key: Qdrant API key (optional).
            prefix: Collection name prefix (project-level).
        """
        self._endpoint = endpoint
        self._api_key = api_key
        self._prefix = prefix
        self._client: Any = None

    def _get_client(self) -> Any:
        """Lazy-load the Qdrant client."""
        if self._client is not None:
            return self._client
        try:
            from qdrant_client import QdrantClient
        except ImportError as e:
            logger.warning("qdrant-client not installed: %s", e)
            self._client = None
            return None

        try:
            self._client = QdrantClient(
                url=self._endpoint,
                api_key=self._api_key if self._api_key else None,
                timeout=10,
            )
            return self._client
        except Exception as e:
            logger.warning("Failed to create QdrantClient: %s", e)
            self._client = None
            return None

    def _collection_name(self, collection: str) -> str:
        """Build the full collection name with prefix."""
        if self._prefix:
            return f"{self._prefix}{collection}"
        return collection

    def health_check(self) -> bool:
        """Check if the Qdrant server is reachable.

        Performs QdrantClient.get_collections(). Returns True on success,
        False on any exception.

        Returns:
            True if Qdrant is reachable, False otherwise.
        """
        try:
            client = self._get_client()
            if client is None:
                return False
            client.get_collections()
            return True
        except Exception:
            return False

    def retrieve(self, query: str, collection: str, top_k: int = 3) -> list:
        """Retrieve relevant chunks (stub — full impl in task 1.13).

        Args:
            query: Search query.
            collection: Collection name.
            top_k: Number of results.

        Returns:
            Empty list (stub).
        """
        return []

    def index(self, chunks: list, collection: str) -> int:
        """Index chunks (stub — full impl in task 1.13).

        Args:
            chunks: List of chunks to index.
            collection: Collection name.

        Returns:
            Number of chunks indexed (stub: 0).
        """
        return 0
