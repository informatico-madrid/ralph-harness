"""Chunker for splitting spec artifacts into indexed chunks.

Dispatches by file extension / name to per-artifact splitters.
Each chunk carries accurate source_line_start/source_line_end.
"""

from __future__ import annotations

import ast
import logging
import re
from pathlib import Path

from .types import Chunk

logger = logging.getLogger(__name__)

# ── token-count helpers ────────────────────────────────────────────────

def _approx_tokens(text: str) -> int:
    """Rough token count when no tokenizer is available."""
    return max(1, len(text) // 4)


class Chunker:
    """Chunk splitter with per-artifact strategies.

    Dispatches based on file extension:
    - .md: splits on ## / ### headings, 800-token target, 100-token overlap
    - .jsonl: emits one chunk per line
    - .py: splits by function/class (AST-based)
    - others: single chunk per file

    Args:
        embedder: Optional embedder whose tokenizer is used for accurate
            token-based chunking. When absent, falls back to ``len(text)//4``.
    """

    # design.md target
    DEFAULT_TARGET_TOKENS = 800
    DEFAULT_OVERLAP_TOKENS = 100

    def __init__(self, embedder: object | None = None) -> None:
        self._embedder = embedder

    # ── public API ─────────────────────────────────────────────────────

    def chunk(self, source_path: str, content: str) -> list[Chunk]:
        """Split content into chunks based on file type.

        Args:
            source_path: Path to the source file.
            content: Raw file content.

        Returns:
            List of Chunk objects.
        """
        ext = Path(source_path).suffix.lower()

        if ext == ".md":
            return self._chunk_markdown(source_path, content)
        elif ext == ".jsonl":
            return self._chunk_jsonl(source_path, content)
        elif ext == ".py":
            return self._chunk_python(source_path, content)
        else:
            return [
                Chunk(
                    content=content,
                    source_path=source_path,
                    spec_name=self._extract_spec_name(source_path),
                )
            ]

    # ── token-counting ─────────────────────────────────────────────────

    @property
    def _tokenizer(self) -> object | None:
        """Return the active embedder's tokenizer, if available."""
        if self._embedder is None:
            return None
        # Use the tokenizer property (overridden in LocalEmbedder)
        return getattr(self._embedder, "tokenizer", None)

    def _token_count(self, text: str) -> int:
        """Count tokens using the embedder tokenizer or fallback."""
        tokenizer = self._tokenizer
        if tokenizer is not None:
            try:
                return len(tokenizer.encode(text))
            except Exception:
                return _approx_tokens(text)
        return _approx_tokens(text)

    def _split_by_tokens(
        self, text: str, target: int = DEFAULT_TARGET_TOKENS,
        overlap: int = DEFAULT_OVERLAP_TOKENS,
    ) -> list[str]:
        """Split *text* into token-bounded pieces."""
        if self._token_count(text) <= target:
            return [text]

        tokenizer = self._tokenizer
        if tokenizer is not None:
            try:
                tokens = tokenizer.encode(text)
            except Exception:
                tokens = []

        if not tokens:
            return [text]  # fallback to whole text

        pieces: list[str] = []
        start = 0
        while start < len(tokens):
            end = min(start + target, len(tokens))
            try:
                pieces.append(tokenizer.decode(tokens[start:end]))
            except Exception:
                # fallback character-based
                chunk_text = text[start * 4 : end * 4]
                pieces.append(chunk_text)
            if end >= len(tokens):
                break
            start = end - overlap
            if start >= len(tokens):
                start = len(tokens)
        return pieces

    # ── per-artifact splitters ─────────────────────────────────────────

    def _chunk_markdown(self, source_path: str, content: str) -> list[Chunk]:
        """Split markdown on ``## `` and ``### `` heading boundaries only.

        Target ~800 tokens per chunk, ~100-token overlap.
        """
        lines = content.split("\n")
        sections: list[tuple[str, int, int]] = []
        current_heading = "# root"
        current_start = 0

        for i, line in enumerate(lines):
            match = re.match(r"^(#{1,6})\s+(.+)$", line)
            if match and len(match.group(1)) in (2, 3):  # ## or ### only
                if current_start < i:
                    sections.append(
                        (current_heading, current_start, i),
                    )
                current_heading = line.strip()
                current_start = i

        # Don't forget the last section
        if current_start < len(lines):
            sections.append(
                (current_heading, current_start, len(lines)),
            )

        if not sections:
            return [
                Chunk(
                    content=content,
                    source_path=source_path,
                    spec_name=self._extract_spec_name(source_path),
                    source_line_start=1,
                    source_line_end=len(lines),
                )
            ]

        # Merge small sections to reach target size, then split by tokens
        merged_lines: list[tuple[str, int, int]] = []
        buf_heading = sections[0][0]
        buf_start = sections[0][1]
        buf_end = sections[0][2]

        for heading, start, end in sections[1:]:
            # Tentative merged block text
            test_text = "\n".join(lines[buf_start:buf_end]) + "\n" + "\n".join(lines[start:end])
            if self._token_count(test_text) <= self.DEFAULT_TARGET_TOKENS:
                buf_end = end
            else:
                merged_lines.append((buf_heading, buf_start, buf_end))
                buf_heading = heading
                buf_start = start
                buf_end = end

        merged_lines.append((buf_heading, buf_start, buf_end))

        # Split merged blocks by token target and create Chunks
        result: list[Chunk] = []
        for heading, start, end in merged_lines:
            text = "\n".join(lines[start:end])
            pieces = self._split_by_tokens(text, self.DEFAULT_TARGET_TOKENS, self.DEFAULT_OVERLAP_TOKENS)
            for idx, piece in enumerate(pieces):
                if not piece.strip():
                    continue
                overlap_offset = 0
                if idx > 0 and self._token_count(piece) > self.DEFAULT_OVERLAP_TOKENS:
                    # approximate overlap start
                    overlap_offset = self.DEFAULT_OVERLAP_TOKENS * 4

                line_start = start + 1
                line_end = end
                if overlap_offset > 0:
                    line_start = max(line_start, line_end - overlap_offset // 4)

                result.append(
                    Chunk(
                        content=piece,
                        source_path=source_path,
                        spec_name=self._extract_spec_name(source_path),
                        source_line_start=line_start,
                        source_line_end=line_end,
                    )
                )

        return result

    def _chunk_jsonl(self, source_path: str, content: str) -> list[Chunk]:
        """Emit one chunk per JSONL line."""
        lines = content.strip().split("\n")
        result: list[Chunk] = []
        for i, line in enumerate(lines):
            line = line.strip()
            if not line:
                continue
            result.append(
                Chunk(
                    content=line,
                    source_path=source_path,
                    spec_name=self._extract_spec_name(source_path),
                    source_line_start=i + 1,
                    source_line_end=i + 1,
                )
            )
        return result

    def _chunk_python(self, source_path: str, content: str) -> list[Chunk]:
        """Split Python source by top-level FunctionDef / ClassDef (AST-based).

        Uses ``ast.parse`` so each chunk contains a complete, parseable unit.
        Module-level preamble (imports, comments before first def/class) becomes
        one chunk; then each top-level function/class is its own chunk.
        """
        lines = content.split("\n")
        spec_name = self._extract_spec_name(source_path)
        try:
            tree = ast.parse(content)
        except SyntaxError:
            # Fall back to single-chunk if content is not valid Python
            return [
                Chunk(
                    content=content,
                    source_path=source_path,
                    spec_name=spec_name,
                    source_line_start=1,
                    source_line_end=len(lines),
                )
            ]

        # Collect top-level body nodes with their source line ranges
        body_items: list[tuple[ast.AST, int, int]] = []
        for node in tree.body:
            start = node.lineno
            end = getattr(node, "end_lineno", start + 1)
            body_items.append((node, start, end))

        if not body_items:
            # No top-level defs — single chunk
            return [
                Chunk(
                    content=content,
                    source_path=source_path,
                    spec_name=self._extract_spec_name(source_path),
                    source_line_start=1,
                    source_line_end=len(lines),
                )
            ]

        # Extract source text for each top-level node
        result: list[Chunk] = []
        for node, start, end in body_items:
            try:
                text = ast.get_source_segment(content, node)
            except Exception:
                # Fallback: use line slicing
                text = "\n".join(lines[start - 1 : end])
            if text is None or not text.strip():
                continue
            result.append(
                Chunk(
                    content=text,
                    source_path=source_path,
                    spec_name=self._extract_spec_name(source_path),
                    source_line_start=start,
                    source_line_end=end,
                )
            )

        return result if result else [
            Chunk(
                content=content,
                source_path=source_path,
                spec_name=self._extract_spec_name(source_path),
            )
        ]

    @staticmethod
    def _extract_spec_name(source_path: str) -> str:
        """Extract spec name from path like specs/<name>/file.md."""
        parts = Path(source_path).parts
        for i, part in enumerate(parts):
            if part == "specs" and i + 1 < len(parts):
                return parts[i + 1]
        return "unknown"
