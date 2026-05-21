"""Qdrant vector database provider.

Primary provider — uses qdrant_client QdrantClient for HTTP REST API.
"""

from __future__ import annotations

import hashlib
import logging
import uuid
from typing import Any

from .base import VectorDBProvider

logger = logging.getLogger(__name__)


class QdrantProvider(VectorDBProvider):
    """Qdrant HTTP REST provider.

    Uses qdrant_client.QdrantClient to connect to a Qdrant server.
    Collection names get a project-level prefix and the project name.
    """

    # Default embedding dimensions for OpenAI / bge-large models
    DEFAULT_DIMENSIONS = 1536

    def __init__(
        self,
        endpoint: str,
        api_key: str = "",
        prefix: str = "",
        project: str = "",
    ):
        """Initialize the Qdrant provider.

        Args:
            endpoint: Qdrant server URL (e.g. "http://localhost:6333").
            api_key: Qdrant API key (optional).
            prefix: Collection name prefix (project-level).
            project: Human-readable project name (used in collection naming).
        """
        self._endpoint = endpoint
        self._api_key = api_key
        self._prefix = prefix
        self._project = project or self._detect_project()
        self._client: Any = None

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _detect_project() -> str:
        """Derive a project name from the working directory."""
        import os

        return os.path.basename(os.getcwd()) or "unknown"

    def _collection_name(self, project: str, collection: str) -> str:
        """Build the full collection name with prefix and project.

        Returns ``{prefix}{project}-{collection}``.
        """
        name = f"{project}-{collection}"
        if self._prefix:
            name = f"{self._prefix}{name}"
        return name

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

    def _ensure_collection(self, collection: str, dimensions: int = 1536) -> None:
        """Create the collection on first use if it does not exist.

        Args:
            collection: Target collection name.
            dimensions: Embedding vector dimensions (default 1536).
        """
        client = self._get_client()
        if client is None:
            return

        full_name = self._collection_name(self._project, collection)
        try:
            # Check if collection already exists
            collections = client.get_collections()
            exists = any(
                c.name == full_name for c in collections.collections
            )
            if exists:
                return

            from qdrant_client import models as qmodels

            client.create_collection(
                collection_name=full_name,
                vectors_config=qmodels.VectorParams(
                    size=dimensions,
                    distance=qmodels.Distance.COSINE,
                ),
            )
        except Exception as e:
            logger.warning("Failed to create collection %s: %s", full_name, e)

    # ------------------------------------------------------------------
    # Abstract implementations
    # ------------------------------------------------------------------

    def health_check(self) -> bool:
        """Check if the Qdrant server is reachable.

        Returns True on success, False on any exception.
        """
        try:
            client = self._get_client()
            if client is None:
                return False
            client.get_collections()
            return True
        except Exception:
            return False

    def retrieve(
        self, query_vec: list[float], collection: str, top_k: int = 3
    ) -> list:
        """Retrieve relevant chunks via Qdrant search.

        Uses qdrant_client.QdrantClient.search with the provided
        embedding vector.

        Args:
            query_vec: Pre-computed embedding vector.
            collection: Target collection name.
            top_k: Number of results to return.

        Returns:
            List of Chunk objects ranked by relevance score.
            Empty list on any error.
        """
        from ..types import Chunk

        client = self._get_client()
        if client is None:
            return []

        full_name = self._collection_name(self._project, collection)
        try:
            response = client.query_points(
                collection_name=full_name,
                query=query_vec,
                limit=top_k,
            )
            points = response.points if hasattr(response, "points") else response
        except Exception as e:
            logger.warning("Qdrant search failed for %s: %s", full_name, e)
            return []

        results: list[Chunk] = []
        for point in points:
            payload = point.payload or {}
            results.append(
                Chunk(
                    content=payload.get("content", ""),
                    source_path=payload.get("source_path", ""),
                    spec_name=payload.get("spec_name", ""),
                    score=point.score if point.score is not None else 0.0,
                    source_line_start=payload.get("source_line_start", 0),
                    source_line_end=payload.get("source_line_end", 0),
                    indexed_at=payload.get("indexed_at", ""),
                    embedder_model=payload.get("embedder_model", ""),
                )
            )
        return results

    def index(
        self, chunks: list, collection: str, dimensions: int | None = None
    ) -> int:
        """Index chunks into a Qdrant collection.

        Creates the collection on-demand if it does not exist.
        Each chunk must have a ``vector`` attribute (list[float]).

        Args:
            chunks: Chunks to index (each needs a ``vector`` attr).
            collection: Target collection name.
            dimensions: Override embedding dimensions.

        Returns:
            Number of chunks successfully indexed.
        """
        client = self._get_client()
        if client is None:
            return 0

        # Infer dimensions from the first chunk's vector
        if dimensions is None and chunks:
            vec = getattr(chunks[0], "vector", None)
            if vec is not None:
                dimensions = len(vec)
        dimensions = dimensions or self.DEFAULT_DIMENSIONS

        full_name = self._collection_name(self._project, collection)
        self._ensure_collection(collection, dimensions)

        try:
            from qdrant_client import models as qmodels

            points = []
            for chunk in chunks:
                vec = getattr(chunk, "vector", None)
                if vec is None:
                    logger.warning(
                        "Chunk %s has no vector — skipping", chunk.id
                    )
                    continue

                # Sanitize chunk.id to a valid Qdrant UUID
                point_id = chunk.id
                if ":" not in point_id:
                    try:
                        int(point_id)
                    except ValueError:
                        pass  # Valid as-is (UUID or short string)
                else:
                    # Replace colons with hyphens to form valid UUID-like ID
                    point_id = hashlib.sha256(
                        chunk.id.encode()
                    ).hexdigest()[:32]

                points.append(
                    qmodels.PointStruct(
                        id=point_id,
                        vector=vec,
                        payload={
                            "content": chunk.content,
                            "source_path": chunk.source_path,
                            "spec_name": chunk.spec_name,
                            "source_line_start": chunk.source_line_start,
                            "source_line_end": chunk.source_line_end,
                            "indexed_at": chunk.indexed_at,
                            "embedder_model": chunk.embedder_model,
                        },
                    )
                )

            if not points:
                return 0

            client.upsert(collection_name=full_name, points=points)
            return len(points)
        except Exception as e:
            logger.warning("Qdrant upsert failed for %s: %s", full_name, e)
            return 0
