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
from .observability import record_metric
from .signals import emit_indexing_queued, emit_retrieval_complete, emit_retrieval_failed
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
        spec_path: Optional[_Path] = None,
    ):
        """Initialize RAGService.

        Args:
            provider: VectorDBProvider instance.
            embedder: Embedder instance.
            spec_path: Optional path to the active spec directory for signal emission.
        """
        self._provider = provider
        self._embedder = embedder
        self._spec_path = self._resolve_spec_path(spec_path)

    def _resolve_spec_path(self, spec_path: Optional[_Path]) -> Optional[_Path]:
        """Resolve the spec directory path for signal emission.

        Returns None if no spec context is available.
        """
        if spec_path is not None:
            if (spec_path / "signals.jsonl").exists() or (
                spec_path / ".ralph-state.json"
            ).exists():
                return spec_path
            # Accept the path anyway — may be created later
            return spec_path

        # Auto-detect: walk up from CWD looking for .ralph-state.json
        cwd = _Path.cwd()
        for parent in [cwd] + list(cwd.parents):
            if (parent / ".ralph-state.json").exists():
                return parent
        return None

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

        # Use config.project if set, otherwise derive from cwd
        project = config.project or cls._detect_project()

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

        Special case: ``collection="all"`` searches across all project-scoped
        collections managed by the provider, merges results, deduplicates,
        and returns top_k sorted by score.

        Emits RETRIEVAL_REQUEST at start, RETRIEVAL_COMPLETE on success,
        RETRIEVAL_FAILED on error. Records observability metrics.

        Args:
            query: Search query.
            collection: Collection name (use ``"all"`` to search all).
            top_k: Number of results.

        Returns:
            List of chunks ranked by relevance. Empty list on any error.
        """
        import time

        start = time.monotonic()

        # Special case: "all" searches across all indexed collections
        if collection == "all":
            return self._retrieve_all(query, top_k, start)

        try:
            query_vec = self._embedder.embed(query)
            results = self._provider.retrieve(query_vec, collection, top_k)
            latency_ms = (time.monotonic() - start) * 1000
            if self._spec_path is not None:
                emit_retrieval_complete(
                    self._spec_path, collection, len(results)
                )
            record_metric(
                op="retrieve",
                spec=self._spec_path.name if self._spec_path else "unknown",
                query=query,
                collection=collection,
                top_k=top_k,
                provider_used=type(self._provider).__name__,
                embedder_used=type(self._embedder).__name__,
                latency_ms=latency_ms,
                result_count=len(results),
                outcome="ok",
            )
            return results
        except Exception as e:
            latency_ms = (time.monotonic() - start) * 1000
            logger.warning("RAGService.retrieve failed: %s", e)
            if self._spec_path is not None:
                emit_retrieval_failed(
                    self._spec_path, reason=str(e), phase="retrieval"
                )
            record_metric(
                op="retrieve",
                spec=self._spec_path.name if self._spec_path else "unknown",
                query=query,
                collection=collection,
                top_k=top_k,
                provider_used=type(self._provider).__name__,
                embedder_used=type(self._embedder).__name__,
                latency_ms=latency_ms,
                result_count=0,
                outcome="error",
            )
            return []

    def _retrieve_all(
        self,
        query: str,
        top_k: int,
        start: float,
    ) -> list[Chunk]:
        """Search across all indexed collections and merge results.

        Embeds the query once, searches each collection, merges and
        reranks by score, deduplicates by (source_path, line_start, line_end),
        and returns top_k total.
        """
        import time

        try:
            query_vec = self._embedder.embed(query)
        except Exception as e:
            logger.warning("RAGService._retrieve_all embed failed: %s", e)
            latency_ms = (time.monotonic() - start) * 1000
            record_metric(
                op="retrieve",
                spec=self._spec_path.name if self._spec_path else "unknown",
                query=query,
                collection="all",
                top_k=top_k,
                provider_used=type(self._provider).__name__,
                embedder_used=type(self._embedder).__name__,
                latency_ms=latency_ms,
                result_count=0,
                outcome="error",
            )
            self._emit_retrieval_failed("all", str(e), "retrieval")
            return []

        try:
            all_collections = self._provider.list_collections()
        except Exception as e:
            logger.warning("RAGService._retrieve_all list_collections failed: %s", e)
            latency_ms = (time.monotonic() - start) * 1000
            record_metric(
                op="retrieve",
                spec=self._spec_path.name if self._spec_path else "unknown",
                query=query,
                collection="all",
                top_k=top_k,
                provider_used=type(self._provider).__name__,
                embedder_used=type(self._embedder).__name__,
                latency_ms=latency_ms,
                result_count=0,
                outcome="error",
            )
            self._emit_retrieval_failed("all", str(e), "retrieval")
            return []

        if not all_collections:
            return []

        all_results: list[Chunk] = []
        for coll in all_collections:
            try:
                results = self._provider.retrieve_raw(query_vec, coll, top_k)
                all_results.extend(results)
            except Exception as e:
                logger.warning("_retrieve_all failed for %s: %s", coll, e)
                coll_latency_ms = (time.monotonic() - start) * 1000
                record_metric(
                    op="retrieve",
                    spec=self._spec_path.name if self._spec_path else "unknown",
                    query=query,
                    collection="all",
                    top_k=top_k,
                    provider_used=type(self._provider).__name__,
                    embedder_used=type(self._embedder).__name__,
                    latency_ms=coll_latency_ms,
                    result_count=0,
                    outcome="error",
                )

        # Deduplicate by (source_path, line_start, line_end)
        seen: set[tuple[str, int, int]] = set()
        deduped: list[Chunk] = []
        for r in all_results:
            key = (r.source_path, r.source_line_start, r.source_line_end)
            if key not in seen:
                seen.add(key)
                deduped.append(r)

        # Sort by score and take top_k
        deduped.sort(key=lambda r: r.score if r.score else 0.0, reverse=True)
        result = deduped[:top_k]

        latency_ms = (time.monotonic() - start) * 1000
        record_metric(
            op="retrieve",
            spec=self._spec_path.name if self._spec_path else "unknown",
            query=query,
            collection="all",
            top_k=top_k,
            provider_used=type(self._provider).__name__,
            embedder_used=type(self._embedder).__name__,
            latency_ms=latency_ms,
            result_count=len(result),
            outcome="ok",
        )
        self._emit_retrieval_complete("all", len(result), start)
        return result

    def _emit_retrieval_complete(
        self, collection: str, count: int, start: float
    ) -> None:
        """Emit RETRIEVAL_COMPLETE signal with latency tracking."""
        if self._spec_path is not None:
            emit_retrieval_complete(self._spec_path, collection, count)

    def _emit_retrieval_failed(self, collection: str, reason: str, phase: str) -> None:
        """Emit RETRIEVAL_FAILED signal."""
        if self._spec_path is not None:
            emit_retrieval_failed(self._spec_path, reason=reason, phase=phase)

    def index(self, chunks: list[Chunk], collection: str) -> int:
        """Index chunks with graceful degradation.

        Embeds each chunk's content via the embedder, then delegates
        to provider.index(). Catches ALL exceptions, logs WARN, returns 0.

        Emits INDEXING_QUEUED on success, RETRIEVAL_FAILED on error.
        Records observability metrics.

        Args:
            chunks: Chunks to index.
            collection: Collection name.

        Returns:
            Number of chunks indexed, or 0 on error.
        """
        import time

        start = time.monotonic()
        chunk_count = len(chunks)

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

            count = self._provider.index(chunks, collection)
            latency_ms = (time.monotonic() - start) * 1000
            if self._spec_path is not None:
                emit_indexing_queued(self._spec_path, chunk_count=count)
            record_metric(
                op="index",
                spec=self._spec_path.name if self._spec_path else "unknown",
                query=f"index-{collection}",
                collection=collection,
                top_k=chunk_count,
                provider_used=type(self._provider).__name__,
                embedder_used=type(self._embedder).__name__,
                latency_ms=latency_ms,
                result_count=count,
                outcome="ok",
            )
            return count
        except Exception as e:
            latency_ms = (time.monotonic() - start) * 1000
            logger.warning("RAGService.index failed: %s", e)
            if self._spec_path is not None:
                emit_retrieval_failed(
                    self._spec_path, reason=str(e), phase="indexing"
                )
            record_metric(
                op="index",
                spec=self._spec_path.name if self._spec_path else "unknown",
                query=f"index-{collection}",
                collection=collection,
                top_k=chunk_count,
                provider_used=type(self._provider).__name__,
                embedder_used=type(self._embedder).__name__,
                latency_ms=latency_ms,
                result_count=0,
                outcome="error",
            )
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
                except (OSError, UnicodeDecodeError) as e:
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
