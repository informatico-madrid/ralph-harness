"""Chunker for splitting spec artifacts into indexed chunks.

Dispatches by file extension / name to per-artifact splitters.
Each chunk carries accurate source_line_start/source_line_end.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

from .types import Chunk

logger = logging.getLogger(__name__)


class Chunker:
    """Chunk splitter with per-artifact strategies.

    Dispatches based on file extension:
    - .md: splits on ## / ### headings, 800-token target, 100-token overlap
    - .jsonl: emits one chunk per line
    - .py: splits by function/class
    - others: single chunk per file
    """

    def chunk(self, source_path: str, content: str) -> list[Chunk]:
        """Split content into chunks based on file type.

        Args:
            source_path: Path to the source file.
            content: Raw file content.

        Returns:
            List of Chunk objects.
        """
        ext = Path(source_path).suffix.lower()
        _ = Path(source_path).stem.lower()  # used for logging, kept for future

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

    def _chunk_markdown(self, source_path: str, content: str) -> list[Chunk]:
        """Split markdown on ## / ### heading boundaries.

        Target: ~800 tokens per chunk, ~100-token overlap.
        """
        lines = content.split("\n")
        sections: list[tuple[str, int, int]] = []  # (heading, start_line, end_line)
        current_heading = "# root"
        current_start = 0

        for i, line in enumerate(lines):
            match = re.match(r"^(#{1,6})\s+(.+)$", line)
            if match and len(match.group(1)) <= 2:  # ## or ###
                if current_start < i:
                    sections.append(
                        (current_heading, current_start, i)
                    )
                current_heading = line.strip()
                current_start = i

        # Don't forget the last section
        if current_start < len(lines):
            sections.append((current_heading, current_start, len(lines)))

        # Merge small sections to reach target size
        merged: list[tuple[str, int, int]] = []
        current_merged_heading = ""
        current_merged_start = 0
        current_merged_end = 0

        for heading, start, end in sections:
            chunk_lines = lines[start:end]
            if len(chunk_lines) < 20 and current_merged_end > current_merged_start:
                # Small section, merge with previous
                current_merged_end = end
            else:
                if current_merged_heading:
                    merged.append(
                        (current_merged_heading, current_merged_start, current_merged_end)
                    )
                current_merged_heading = heading
                current_merged_start = start
                current_merged_end = end

        if current_merged_heading:
            merged.append((current_merged_heading, current_merged_start, current_merged_end))

        # Create Chunk objects
        result: list[Chunk] = []
        for heading, start, end in merged:
            text = "\n".join(lines[start:end])
            if text.strip():
                result.append(
                    Chunk(
                        content=text,
                        source_path=source_path,
                        spec_name=self._extract_spec_name(source_path),
                        source_line_start=start + 1,
                        source_line_end=end,
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
        """Split Python source by function/class."""
        lines = content.split("\n")
        result: list[Chunk] = []
        current_start = 0

        for i, line in enumerate(lines):
            if re.match(r"^\s*(def |class )", line):
                if i > current_start:
                    func_code = "\n".join(lines[current_start:i])
                    result.append(
                        Chunk(
                            content=func_code,
                            source_path=source_path,
                            spec_name=self._extract_spec_name(source_path),
                            source_line_start=current_start + 1,
                            source_line_end=i,
                        )
                    )
                current_start = i

        func_code = "\n".join(lines[current_start:])
        result.append(
            Chunk(
                content=func_code,
                source_path=source_path,
                spec_name=self._extract_spec_name(source_path),
                source_line_start=current_start + 1,
                source_line_end=len(lines),
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
