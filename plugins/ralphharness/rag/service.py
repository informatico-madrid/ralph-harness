"""RAGService facade with Qdrant→FAISS fallback.

Wraps vector DB provider + embedder chain. Provides retrieve/index with
graceful degradation — ALL exceptions caught, returns empty/default.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

from .config import RAGConfig
from .types import Chunk

logger = logging.getLogger(__name__)


class RAGService:
    """Facade for RAG retrieval and indexing.

    Combines a VectorDBProvider (Qdrant primary, FAISS fallback) and
    an Embedder (chain with local→openai→azure fallback).

    All public methods catch exceptions and degrade gracefully.
    """

    def __init__(
        self,
        provider: Any,
        embedder: Any,
    ):
        """Initialize RAGService.

        Args:
            provider: VectorDBProvider instance.
            embedder: Embedder instance.
        """
        self._provider = provider
        self._embedder = embedder

    @classmethod
    def from_config(cls, config: Optional[RAGConfig] = None) -> Optional["RAGService"]:
        """Build RAGService from RAGConfig.

        Returns None when enabled=False (backward-compatible: projects
        without rag: config run with zero RAG calls).

        Args:
            config: RAGConfig instance. If None, loads default config.

        Returns:
            RAGService instance, or None if disabled.
        """
        if config is None:
            config = RAGConfig.load()

        if not config.enabled:
            logger.info("RAG disabled — returning None (zero overhead)")
            return None

        # Build provider (Qdrant primary, FAISS fallback)
        provider = cls._build_provider(config)
        if provider is None:
            logger.warning("No vector DB provider available")
            return None

        # Build embedder chain
        embedder = cls._build_embedder(config)
        if embedder is None:
            logger.warning("No embedder available")
            return None

        logger.info("RAGService initialized (provider=%s, embedder=%s)",
                     type(provider).__name__, type(embedder).__name__)
        return cls(provider=provider, embedder=embedder)

    @staticmethod
    def _build_provider(config: RAGConfig) -> Any:
        """Build vector DB provider with Qdrant→FAISS fallback.

        Args:
            config: RAGConfig instance.

        Returns:
            VectorDBProvider instance or None.
        """
        # Try Qdrant first
        try:
            from .providers.qdrant import QdrantProvider

            qdrant = QdrantProvider(
                endpoint=config.vector_db.endpoint or "http://localhost:6333",
                api_key=config.vector_db.api_key or "",
                prefix=config.vector_db.collection_prefix or "",
            )

            if qdrant.health_check():
                logger.info("Using Qdrant provider at %s", config.vector_db.endpoint)
                return qdrant
            else:
                logger.warning("Qdrant health check failed — trying FAISS")
        except ImportError:
            logger.info("qdrant-client not installed — using FAISS")
        except Exception as e:
            logger.warning("Qdrant provider failed: %s — trying FAISS", e)

        # Fall back to FAISS
        if config.vector_db.faiss_index_path:
            try:
                from .providers.faiss import FAISSProvider

                return FAISSProvider(index_dir=config.vector_db.faiss_index_path)
            except ImportError as e:
                logger.warning("FAISS not installed: %s", e)
        else:
            logger.warning("No FAISS index path configured")

        return None

    @staticmethod
    def _build_embedder(config: RAGConfig) -> Any:
        """Build embedder chain from config.

        Args:
            config: RAGConfig instance.

        Returns:
            Embedder instance or None.
        """
        try:
            from .embedder.chain import from_config as chain_from_config

            return chain_from_config(config)
        except ImportError:
            logger.warning("embedder chain not available")
            return None
        except Exception as e:
            logger.warning("Failed to build embedder chain: %s", e)
            return None

    def retrieve(
        self,
        query: str,
        collection: str,
        top_k: int = 3,
    ) -> list[Chunk]:
        """Retrieve relevant chunks with graceful degradation.

        Embeds the query, calls provider.retrieve(), returns list of chunks.
        Catches ALL exceptions, logs WARN, returns [].

        Args:
            query: Search query.
            collection: Collection name.
            top_k: Number of results.

        Returns:
            List of chunks ranked by relevance. Empty list on any error.
        """
        try:
            query_vec = self._embedder.embed(query)
            return self._provider.retrieve(query_vec, collection, top_k)
        except Exception as e:
            logger.warning("RAGService.retrieve failed: %s", e)
            return []

    def index(self, chunks: list[Chunk], collection: str) -> int:
        """Index chunks with graceful degradation.

        Catches ALL exceptions, logs WARN, returns 0.

        Args:
            chunks: Chunks to index.
            collection: Collection name.

        Returns:
            Number of chunks indexed, or 0 on error.
        """
        try:
            return self._provider.index(chunks, collection)
        except NotImplementedError:
            logger.info("Indexing not yet implemented for %s",
                        type(self._provider).__name__)
            return 0
        except Exception as e:
            logger.warning("RAGService.index failed: %s", e)
            return 0
