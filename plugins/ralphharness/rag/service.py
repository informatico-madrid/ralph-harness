"""RAGService facade with Qdrant→FAISS fallback.

Wraps vector DB provider + embedder chain. Provides retrieve/index with
graceful degradation — ALL exceptions caught, returns empty/default.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path as _Path
from typing import Any, Callable, Optional

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

        project = cls._detect_project()

        # Build provider (Qdrant primary, FAISS fallback)
        provider = cls._build_provider(config, project)
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
    def _detect_project() -> str:
        """Derive a project name from the working directory."""
        return os.path.basename(os.getcwd()) or "unknown"

    @staticmethod
    def _build_provider(config: RAGConfig, project: str) -> Any:
        """Build vector DB provider with Qdrant→FAISS fallback.

        Args:
            config: RAGConfig instance.
            project: Project name used in collection naming.

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
                project=project,
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

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

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

        Embeds each chunk's content via the embedder, then delegates
        to provider.index(). Catches ALL exceptions, logs WARN, returns 0.

        Args:
            chunks: Chunks to index.
            collection: Collection name.

        Returns:
            Number of chunks indexed, or 0 on error.
        """
        try:
            if not chunks:
                return 0

            texts = [c.content for c in chunks]
            vectors = self._embedder.embed_batch(texts)

            if len(vectors) != len(chunks):
                logger.warning(
                    "Embedding count mismatch: in=%d out=%d",
                    len(chunks), len(vectors),
                )
                return 0

            for c, v in zip(chunks, vectors):
                c.vector = v

            return self._provider.index(chunks, collection)
        except Exception as e:
            logger.warning("RAGService.index failed: %s", e)
            return 0

    def health_check(self) -> dict[str, Any]:
        """Check the health of the full RAG stack.

        Returns:
            Dict with keys ``provider``, ``embedder``, and ``ok``.
            ``ok`` is True only when both provider and embedder are healthy.
        """
        try:
            provider_ok = bool(self._provider.health_check())
        except Exception as e:
            logger.warning("Provider health check failed: %s", e)
            provider_ok = False

        try:
            self._embedder.embed("health_check")
            embedder_ok = True
        except Exception as e:
            logger.warning("Embedder health check failed: %s", e)
            embedder_ok = False

        return {
            "provider": type(self._provider).__name__,
            "embedder": type(self._embedder).__name__,
            "ok": provider_ok and embedder_ok,
        }

    def health_check_json(self) -> str:
        """Return health check result as a JSON string.

        Convenience method for CLI output that matches the JSON format
        expected by verify commands (double-quoted keys, lowercase booleans).
        """
        return json.dumps(self.health_check())

    def index_all(
        self,
        specs_dir: str = "specs",
        on_progress: Optional[Callable[[str, str, int], None]] = None,
    ) -> dict[str, int]:
        """Index all spec artifacts across all specs.

        Walks ``<specs_dir>/*/`` directories, chunks each artifact via
        ``Chunker``, and indexes by collection_id (design.md Component 7
        table). Streams per-spec progress via ``on_progress`` callback.

        Args:
            specs_dir: Path to the specs root directory.
            on_progress: Optional callback ``func(name: str, status: str, total: int)``.

        Returns:
            Dict mapping spec name to number of chunks indexed.
        """
        from .chunker import Chunker
        from .security import SecurityLayer

        specs_path = _Path(specs_dir)
        results: dict[str, int] = {}

        if not specs_path.is_dir():
            logger.warning("Specs directory not found: %s", specs_dir)
            return results

        spec_dirs = sorted(
            d for d in specs_path.iterdir()
            if d.is_dir() and not d.name.startswith(".")
        )

        chunker = Chunker()
        security = SecurityLayer()

        for spec_dir in spec_dirs:
            spec_name = spec_dir.name
            total_indexed = 0

            # Collect all indexable files in this spec
            files: list[_Path] = []
            for ext in (".md", ".jsonl", ".py"):
                files.extend(sorted(spec_dir.glob(f"**/*{ext}")))

            if on_progress:
                on_progress(spec_name, "discovering", len(files))

            for filepath in files:
                try:
                    content = filepath.read_text(encoding="utf-8")
                except OSError as e:
                    logger.warning("Cannot read %s: %s", filepath, e)
                    if on_progress:
                        on_progress(spec_name, "skipped", 0)
                    continue

                try:
                    chunks = chunker.chunk(str(filepath), content)
                except Exception as e:
                    logger.warning("Chunking failed for %s: %s", filepath, e)
                    if on_progress:
                        on_progress(spec_name, "chunk_failed", 0)
                    continue

                # Security filter
                accepted_chunks: list[Chunk] = []
                for c in chunks:
                    sr = security.sanitize(c)
                    if sr.accepted:
                        accepted_chunks.append(c)
                    else:
                        logger.info(
                            "Chunk rejected by %s: %s",
                            sr.rejected_by, c.source_path,
                        )

                if not accepted_chunks:
                    if on_progress:
                        on_progress(spec_name, "rejected", 0)
                    continue

                # Index by collection (use spec name as collection)
                try:
                    count = self.index(accepted_chunks, spec_name)
                    total_indexed += count
                    if on_progress:
                        on_progress(spec_name, "indexed", count)
                except Exception as e:
                    logger.warning("Indexing failed for %s: %s", spec_name, e)
                    if on_progress:
                        on_progress(spec_name, "index_failed", 0)

            results[spec_name] = total_indexed
            if on_progress:
                on_progress(spec_name, "complete", total_indexed)

        return results
