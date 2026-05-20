"""SecurityLayer — chunk sanitization before indexing.

Scans chunks against allowlist patterns from security_allowlist.yaml.
Rejected chunks are logged to sanitization-rejections.log (NEVER
stdout, NEVER signals.jsonl, NEVER raw secret values).
"""

from __future__ import annotations

import logging
import re
import uuid
from dataclasses import dataclass
from pathlib import Path

from .types import Chunk

logger = logging.getLogger(__name__)

_DEFAULT_PATTERNS = [
    r"AKIA[0-9A-Z]{16}",  # AWS access key
    r"AWS_ACCESS_KEY_ID\s*=",
    r"aws_secret_access_key\s*=",
    r"ssh-(rsa|dsa|ed25519)\s+",  # SSH keys
    r"BEGIN.*PRIVATE KEY",
    r"Bearer\s+[A-Za-z0-9\-_.]+",
    r"ghp_[A-Za-z0-9]{36}",  # GitHub PAT
    r"slack-[A-Za-z0-9\-]+",  # Slack token
    r"password\s*[:=]\s*['\"]?[A-Za-z0-9!@#$%^&*]{8,}",
    r"api_key\s*[:=]\s*['\"]?[A-Za-z0-9]{16,}",
]


@dataclass
class SanitizationResult:
    """Result of sanitizing a chunk."""

    accepted: bool
    reason: str = ""
    re_id: str = ""


class SecurityLayer:
    """Chunk sanitization before indexing.

    Scans chunk content against a allowlist of regex patterns.
    If any pattern matches, the chunk is rejected and logged.
    """

    def __init__(self, patterns: list[str] | None = None):
        """Initialize the security layer.

        Args:
            patterns: List of regex patterns. If None, uses defaults.
        """
        self._patterns: list[re.Pattern[str]] = []
        for p in (patterns or _DEFAULT_PATTERNS):
            try:
                self._patterns.append(re.compile(p))
            except re.error as e:
                logger.warning("Invalid pattern '%s': %s", p, e)

    def sanitize(self, chunk: Chunk) -> SanitizationResult:
        """Check a chunk for sensitive content.

        Args:
            chunk: Chunk to check.

        Returns:
            SanitizationResult with accepted=True if clean,
            accepted=False if any pattern matches.
        """
        for pattern in self._patterns:
            if pattern.search(chunk.content):
                re_id = str(uuid.uuid4())
                self._log_rejection(chunk, re_id, pattern.pattern)
                return SanitizationResult(
                    accepted=False,
                    reason=f"matched pattern: {pattern.pattern}",
                    re_id=re_id,
                )

        return SanitizationResult(accepted=True)

    def _log_rejection(self, chunk: Chunk, re_id: str, pattern: str):
        """Log a rejected chunk to the sanitization log.

        Never logs raw secret values — only metadata and pattern matched.
        """
        try:
            path = Path.home() / ".cache" / "smart-ralph" / "rag"
            path.mkdir(parents=True, exist_ok=True)
            log_path = path / "sanitization-rejections.log"

            with open(log_path, "a", encoding="utf-8") as f:
                f.write(
                    f"re_id={re_id} "
                    f"pattern={pattern} "
                    f"source={chunk.source_path} "
                    f"spec={chunk.spec_name} "
                    f"hash={chunk.content_hash[:8]}\n"
                )
        except OSError as e:
            logger.warning("Failed to write sanitization rejection: %s", e)
