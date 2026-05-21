"""FAISS vector database provider (read-only fallback).

Reads FAISS index files from disk. MVP is read-only per Decision #4.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

from .base import VectorDBProvider

logger = logging.getLogger(__name__)


class FAISSProvider(VectorDBProvider):
    """FAISS local-file provider (read-only in MVP).

    Loads index from index_dir/{project}/{collection}.index + .metadata.jsonl.
    Returns empty list on missing index; raises NotImplementedError on index()
    unless allow_write=True.
    """

    def __init__(self, index_dir: str | Path, allow_write: bool = False):
        """Initialize the FAISS provider.

        Args:
            index_dir: Root directory for FAISS index files.
            allow_write: If True, allows indexing (beyond MVP).
        """
        self._index_dir = Path(index_dir)
        self._allow_write = allow_write
        self._index: Any = None
        self._metadata: list[dict[str, Any]] = []
        self._loaded_collection: str = ""

    def _load(self, collection: str) -> bool:
        """Load index and metadata for a collection.

        Args:
            collection: Collection name.

        Returns:
            True if successfully loaded, False otherwise.
        """
        index_path = self._index_dir / f"{collection}.index"
        metadata_path = self._index_dir / f"{collection}.metadata.jsonl"

        if not index_path.exists():
            self._index = None
            self._metadata = []
            self._loaded_collection = ""
            return False

        try:
            import faiss as _faiss

            self._index = _faiss.read_index(str(index_path))
        except Exception as e:
            logger.warning("Failed to read FAISS index: %s", e)
            self._index = None
            return False

        self._metadata = []
        if metadata_path.exists():
            with open(metadata_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            self._metadata.append(json.loads(line))
                        except json.JSONDecodeError as e:
                            logger.warning("Failed to parse metadata line: %s", e)

        self._loaded_collection = collection
        return True

    def retrieve(self, query_vec: list[float], collection: str, top_k: int = 3) -> list:
        """Retrieve top-k chunks by cosine similarity.

        Args:
            query_vec: Query embedding vector.
            collection: Collection name.
            top_k: Number of results.

        Returns:
            List of Chunk objects ranked by score. Empty if index missing.
        """
        if not self._load(collection):
            return []

        try:
            import numpy as np
        except ImportError:
            logger.warning("numpy not installed, cannot perform FAISS search")
            return []

        q = np.array([query_vec], dtype=np.float32)
        k = min(top_k, len(self._metadata))
        if k <= 0:
            return []

        distances, indices = self._index.search(q, k)

        from ..types import Chunk

        results: list[Chunk] = []
        for i in range(k):
            idx = int(indices[0][i])
            if idx == -1 or idx >= len(self._metadata):
                continue
            meta = self._metadata[idx]
            results.append(
                Chunk(
                    content=meta.get("content", ""),
                    source_path=meta.get("source_path", ""),
                    spec_name=meta.get("spec_name", ""),
                    score=float(distances[0][i]),
                    source_line_start=meta.get("source_line_start", 0),
                    source_line_end=meta.get("source_line_end", 0),
                    indexed_at=meta.get("indexed_at", ""),
                    embedder_model=meta.get("embedder_model", ""),
                )
            )

        return results

    def index(self, chunks: list, collection: str) -> int:
        """Index chunks into FAISS.

        Raises NotImplementedError unless allow_write=True.

        Args:
            chunks: List of chunks to index.
            collection: Collection name.

        Returns:
            Number of chunks indexed.

        Raises:
            NotImplementedError: If allow_write is False.
        """
        if not self._allow_write:
            raise NotImplementedError(
                "FAISSProvider is read-only in MVP. "
                "Set allow_write=True to enable indexing."
            )
        # TODO: full FAISS write implementation
        raise NotImplementedError("FAISS write not yet implemented in MVP")

    def health_check(self) -> bool:
        """Check if the index directory is readable.

        Returns:
            True if index_dir exists and is readable.
        """
        return self._index_dir.exists() and os.access(str(self._index_dir), os.R_OK)

    def list_collections(self) -> list[str]:
        """List all collection names available in the FAISS index directory.

        Returns list of collection names (without .index suffix).
        """
        if not self._index_dir.exists():
            return []
        return sorted(p.stem for p in self._index_dir.glob("*.index"))
