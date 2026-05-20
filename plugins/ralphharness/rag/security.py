"""SecurityLayer — chunk sanitization before indexing.

Scans chunks against allowlist patterns loaded from security_allowlist.yaml.
Each pattern carries an ``id``, a ``regex``, and a ``severity`` (block or warn).
Rejected chunks are logged to sanitization-rejections.log (NEVER
stdout, NEVER signals.jsonl, NEVER raw secret values).
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


@dataclass
class _Pattern:
    """Compiled allowlist pattern with metadata."""

    id: str
    compiled: re.Pattern[str]
    severity: str  # "block" | "warn"


@dataclass
class SanitizationResult:
    """Result of sanitizing a chunk.

    Attributes:
        accepted: ``True`` when the chunk is clean (or only ``warn`` patterns).
        rejected_by: Pattern ``id`` that caused rejection (``block`` severity).
        warnings: List of pattern ``id``s that triggered ``warn`` severity.
    """

    accepted: bool
    rejected_by: str = ""
    warnings: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Default patterns (rich format) — used when no YAML file is found
# ---------------------------------------------------------------------------

_DEFAULT_PATTERNS: list[dict[str, str]] = [
    {"id": "aws_access_key", "regex": r"AKIA[0-9A-Z]{16}", "severity": "block"},
    {"id": "aws_key_id_assignment", "regex": r"AWS_ACCESS_KEY_ID\s*=", "severity": "block"},
    {"id": "aws_secret_assignment", "regex": r"aws_secret_access_key\s*=", "severity": "block"},
    {"id": "ssh_key", "regex": r"ssh-(rsa|dsa|ed25519)\s+", "severity": "block"},
    {"id": "private_key", "regex": r"BEGIN.*PRIVATE KEY", "severity": "block"},
    {"id": "bearer_token", "regex": r"Bearer\s+[A-Za-z0-9\-_.]+", "severity": "block"},
    {"id": "github_pat", "regex": r"ghp_[A-Za-z0-9]{36}", "severity": "block"},
    {"id": "slack_token", "regex": r"slack-[A-Za-z0-9\-]+", "severity": "block"},
    {"id": "password_leak", "regex": r"password\s*[:=]\s*['\"]?[A-Za-z0-9!@#$%^&*]{8,}", "severity": "block"},
    {"id": "api_key_leak", "regex": r"api_key\s*[:=]\s*['\"]?[A-Za-z0-9]{16,}", "severity": "block"},
]

# ---------------------------------------------------------------------------
# YAML loading helpers
# ---------------------------------------------------------------------------


def _load_yaml(path: Path) -> list[dict[str, str]]:
    """Load security_allowlist.yaml.

    Supports two formats:
      1. Plain list of regex strings: ["pattern1", "pattern2"]
      2. Rich list: [{id: ..., regex: ..., severity: ...}, ...]
    """
    try:
        import yaml
    except ImportError:
        logger.error("pyyaml not installed — using default patterns only")
        return []

    with open(path, encoding="utf-8") as f:
        data: Any = yaml.safe_load(f)

    if not isinstance(data, list):
        logger.warning("security_allowlist.yaml: expected a list, got %s", type(data).__name__)
        return []

    result: list[dict[str, str]] = []
    for entry in data:
        if isinstance(entry, str):
            # Plain list format: treat as regex with default severity
            result.append({"id": f"implicit_{len(result)}", "regex": entry, "severity": "block"})
        elif isinstance(entry, dict) and "regex" in entry:
            # Rich format: ensure required keys
            entry.setdefault("id", f"pattern_{len(result)}")
            entry.setdefault("severity", "block")
            result.append(entry)  # type: ignore[assignment]
        else:
            logger.warning("security_allowlist.yaml: skipping unrecognized entry %r", entry)

    return result


# ---------------------------------------------------------------------------
# SecurityLayer
# ---------------------------------------------------------------------------


class SecurityLayer:
    """Chunk sanitization before indexing.

    Loads patterns from a YAML allowlist file (``security_allowlist.yaml``).
    Each pattern is annotated with ``severity``:
      - ``block``: chunk is rejected immediately.
      - ``warn``: chunk is accepted but the pattern ``id`` is recorded in
        ``SanitizationResult.warnings``.
    """

    def __init__(self, allowlist_path: Path | None = None) -> None:
        """Initialize the security layer.

        Args:
            allowlist_path: Path to the YAML allowlist file.
                Defaults to ``security_allowlist.yaml`` next to this module.
        """
        self._patterns: list[_Pattern] = []

        # Resolve default allowlist path
        if allowlist_path is None:
            allowlist_path = Path(__file__).resolve().parent / "security_allowlist.yaml"

        # Load YAML if it exists
        yaml_patterns: list[dict[str, str]] = []
        if allowlist_path.is_file():
            yaml_patterns = _load_yaml(allowlist_path)
            if yaml_patterns:
                logger.info("Loaded %d patterns from %s", len(yaml_patterns), allowlist_path)

        # Merge: YAML overrides defaults (same id replaces)
        seen: dict[str, _Pattern] = {}
        for d in _DEFAULT_PATTERNS:
            seen[d["id"]] = _Pattern(
                id=d["id"],
                compiled=re.compile(d["regex"]),
                severity=d.get("severity", "block"),
            )

        for d in yaml_patterns:
            pat_id = d["id"]
            try:
                seen[pat_id] = _Pattern(
                    id=pat_id,
                    compiled=re.compile(d["regex"]),
                    severity=d.get("severity", "block"),
                )
            except re.error as e:
                logger.warning("Invalid pattern '%s' (%s): %s", pat_id, d.get("regex"), e)

        self._patterns = list(seen.values())

    def sanitize(self, chunk: Chunk) -> SanitizationResult:
        """Check a chunk for sensitive content.

        Iterates patterns in order. A ``block`` match rejects immediately.
        A ``warn`` match accumulates in the result but does not reject.

        Args:
            chunk: Chunk to check.

        Returns:
            SanitizationResult with ``accepted=True`` when clean (or
            only ``warn`` hits), ``accepted=False`` on first ``block`` hit.
        """
        warnings: list[str] = []
        for pat in self._patterns:
            if pat.compiled.search(chunk.content):
                if pat.severity == "block":
                    self._log_rejection(chunk, pat)
                    return SanitizationResult(
                        accepted=False,
                        rejected_by=pat.id,
                        warnings=warnings,
                    )
                warnings.append(pat.id)

        return SanitizationResult(accepted=True, warnings=warnings)

    @staticmethod
    def _log_rejection(chunk: Chunk, pat: _Pattern) -> None:
        """Log a rejected chunk to the sanitization log.

        Never logs raw secret values — only metadata and pattern matched.
        """
        try:
            path = Path.home() / ".cache" / "smart-ralph" / "rag"
            path.mkdir(parents=True, exist_ok=True)
            log_path = path / "sanitization-rejections.log"

            with open(log_path, "a", encoding="utf-8") as f:
                f.write(
                    f"pattern_id={pat.id} "
                    f"regex={pat.compiled.pattern} "
                    f"source={chunk.source_path} "
                    f"spec={chunk.spec_name} "
                    f"hash={chunk.content_hash[:8]}\n"
                )
        except OSError as e:
            logger.warning("Failed to write sanitization rejection: %s", e)
