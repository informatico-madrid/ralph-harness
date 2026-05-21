"""Core types for the RAG integration module.

Chunk dataclass matching the JSON shape in design.md Component 2.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from hashlib import sha256


def _now_iso() -> str:
    """Return current UTC time as ISO 8601 string."""
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass
class Chunk:
    """A single chunk of text with metadata for vector search.

    Each chunk carries provenance information so retrieved results
    can link back to the source document and line range.
    """

    # Required fields
    content: str
    source_path: str
    spec_name: str

    # Computed fields (optional override for tests / construction)
    id: str = ""
    content_hash: str = ""

    # Retrieval result fields (set by VectorDBProvider)
    score: float = 0.0
    stale: bool = False

    # Transient: set by RAGService.index() before delegating to provider
    vector: list[float] | None = None

    # Indexing metadata
    source_line_start: int = 0
    source_line_end: int = 0
    indexed_at: str = field(default_factory=_now_iso)
    staleness_days: int = 0
    embedder_model: str = ""

    def __post_init__(self):
        """Compute id and content_hash from content and source_path, unless already set."""
        if not self.content_hash:
            raw = f"{self.source_path}:{self.source_line_start}:{self.content}"
            self.content_hash = sha256(raw.encode()).hexdigest()
        if not self.id:
            self.id = f"{self.spec_name}:{self.content_hash}"
