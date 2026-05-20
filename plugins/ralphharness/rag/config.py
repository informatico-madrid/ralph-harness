"""RAG configuration loader.

Mirrors the YAML schema in design.md (Interfaces section - Configuration).
Default state is disabled - projects without a `rag:` block run with zero RAG calls.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional


# Default project config location (same pattern as other .ralphharness.*.md files)
_DEFAULT_CONFIG_PATH = Path.home() / ".config" / "smart-ralph" / ".ralphharness.local.md"


@dataclass
class EmbedderConfig:
    """Embedder provider configuration."""

    provider: str = "local"  # "local", "openai", "azure"
    model: str = "BAAI/bge-small-en-v1.5"
    api_key: Optional[str] = None
    api_base: Optional[str] = None
    # OpenAI specific
    openai_model: str = "text-embedding-3-small"
    # Azure specific
    azure_endpoint: Optional[str] = None
    azure_deployment: Optional[str] = None


@dataclass
class VectorDBConfig:
    """Vector database provider configuration."""

    provider: str = "qdrant"  # "qdrant", "faiss"
    endpoint: Optional[str] = None
    api_key: Optional[str] = None
    # Qdrant specific
    collection_prefix: str = ""
    # FAISS specific
    faiss_index_path: Optional[str] = None


@dataclass
class RetrievalConfig:
    """Retrieval-specific configuration."""

    timeout_seconds: int = 2
    top_k_default: int = 3


@dataclass
class RAGConfig:
    """RAG integration configuration.

    All settings default to disabled/empty so that projects without
    a `rag:` block in their config file run with zero RAG overhead.

    The single source of truth is `enabled` - all code paths should
    check `config.enabled` before making any RAG calls.
    """

    enabled: bool = False
    provider: str = "qdrant"  # VectorDB default
    embedder: EmbedderConfig = field(default_factory=EmbedderConfig)
    vector_db: VectorDBConfig = field(default_factory=VectorDBConfig)
    retrieval: RetrievalConfig = field(default_factory=RetrievalConfig)
    allow_cross_project: bool = False
    staleness_threshold_days: int = 365
    min_relevance_score: float = 0.7

    @classmethod
    def load(cls, config_path: Optional[Path] = None) -> "RAGConfig":
        """Load RAG configuration from file and/or environment.

        Priority (highest to lowest):
        1. Environment variables (RALPH_RAG_*)
        2. YAML config file (~/.config/smart-ralph/.ralphharness.local.md)
        3. Built-in defaults (all disabled/empty)

        Args:
            config_path: Path to the config file. If None, uses default.

        Returns:
            RAGConfig instance with merged configuration.
        """
        # Start with defaults
        result: dict[str, Any] = {"enabled": False}

        # Load file config
        path = config_path or _DEFAULT_CONFIG_PATH
        file_cfg = _load_yaml_frontmatter(path)
        if file_cfg:
            result = _merge_configs(result, file_cfg)

        # Load and merge environment variables (override file config)
        env_cfg = _load_config_from_env()
        result = _merge_configs(result, env_cfg)

        return cls._from_dict(result)

    @classmethod
    def _from_dict(cls, d: dict[str, Any]) -> "RAGConfig":
        """Build a RAGConfig from a merged configuration dict."""
        # Extract top-level fields
        enabled = d.get("enabled", False)
        if isinstance(enabled, str):
            enabled = enabled.lower() in ("true", "yes", "1")

        provider = d.get("provider", "qdrant")
        if not isinstance(provider, str):
            provider = "qdrant"

        # Embedder config
        embedder_raw = d.get("embedding", d.get("embedder", {}))
        if not isinstance(embedder_raw, dict):
            embedder_raw = {}
        embedder = EmbedderConfig(
            provider=embedder_raw.get("provider", "local"),
            model=embedder_raw.get("model", "BAAI/bge-small-en-v1.5"),
            api_key=embedder_raw.get("api_key"),
            api_base=embedder_raw.get("api_base"),
            openai_model=embedder_raw.get("openai_model", "text-embedding-3-small"),
            azure_endpoint=embedder_raw.get("azure_endpoint"),
            azure_deployment=embedder_raw.get("azure_deployment"),
        )

        # Vector DB config
        vdb_raw = d.get("vector_db", d.get("qdrant", {}))
        if not isinstance(vdb_raw, dict):
            vdb_raw = {}
        vdb = VectorDBConfig(
            provider=d.get("provider", "qdrant"),
            endpoint=vdb_raw.get("endpoint", d.get("endpoint")),
            api_key=vdb_raw.get("api_key", d.get("api_key")),
            collection_prefix=vdb_raw.get("collection_prefix", ""),
            faiss_index_path=vdb_raw.get("faiss_index_path"),
        )

        # Retrieval config
        retrieval_raw = d.get("retrieval", {})
        if not isinstance(retrieval_raw, dict):
            retrieval_raw = {}
        timeout = retrieval_raw.get("timeout_seconds", 2)
        if not isinstance(timeout, (int, float)):
            try:
                timeout = int(timeout)
            except (ValueError, TypeError):
                timeout = 2
        top_k = retrieval_raw.get("top_k_default", 3)
        if not isinstance(top_k, (int, float)):
            try:
                top_k = int(top_k)
            except (ValueError, TypeError):
                top_k = 3

        retrieval = RetrievalConfig(
            timeout_seconds=int(timeout),
            top_k_default=int(top_k),
        )

        # Cross-project
        allow_cross_project = d.get("allow_cross_project", False)
        if isinstance(allow_cross_project, str):
            allow_cross_project = allow_cross_project.lower() in ("true", "yes", "1")

        # Staleness
        staleness = d.get("staleness_threshold_days", 365)
        if not isinstance(staleness, (int, float)):
            try:
                staleness = int(staleness)
            except (ValueError, TypeError):
                staleness = 365

        # Min relevance score
        min_score = d.get("min_relevance_score", 0.7)
        if not isinstance(min_score, (int, float)):
            try:
                min_score = float(min_score)
            except (ValueError, TypeError):
                min_score = 0.7

        return cls(
            enabled=enabled,
            provider=provider,
            embedder=embedder,
            vector_db=vdb,
            retrieval=retrieval,
            allow_cross_project=allow_cross_project,
            staleness_threshold_days=int(staleness),
            min_relevance_score=float(min_score),
        )


def _load_yaml_frontmatter(path: Path) -> Optional[dict[str, Any]]:
    """Parse the YAML frontmatter from a markdown file.

    Looks for content between ```yaml ... ``` or --- delimiters
    and extracts a `rag:` block if present.

    Returns None if the file doesn't exist or has no rag: block.
    """
    try:
        content = path.read_text(encoding="utf-8")
    except (OSError, FileNotFoundError):
        return None

    # Simple YAML frontmatter parser (no pyyaml dependency for config loading)
    # Try --- delimited frontmatter
    if content.startswith("---"):
        end_idx = content.find("---", 3)
        if end_idx > 0:
            yaml_content = content[3:end_idx].strip()
        else:
            return None
    else:
        # Try ```yaml delimited
        start = content.find("```yaml")
        if start == -1:
            return None
        start += 9
        end = content.find("```", start)
        if end == -1:
            return None
        yaml_content = content[start:end].strip()

    # Simple key: value parser
    result: dict[str, Any] = {}
    for line in yaml_content.split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" in line:
            key, _, value = line.partition(":")
            key = key.strip()
            value = value.strip()
            if value:
                result[key] = _parse_yaml_value(value)

    # Look for rag: nested block in the raw content
    rag_block = _extract_rag_block(content, yaml_content)
    if rag_block:
        result = {**result, **rag_block}

    return result if result else None


def _extract_rag_block(content: str, frontmatter: str) -> Optional[dict[str, Any]]:
    """Extract the rag: block from YAML content.

    Handles both frontmatter and regular markdown YAML blocks.
    """
    lines = content.split("\n")
    in_rag = False
    rag_indent = 0
    result: dict[str, Any] = {}

    for line in lines:
        stripped = line.lstrip()
        indent = len(line) - len(stripped)

        # Detect rag: top-level key
        if stripped.startswith("rag:") and indent == 0:
            in_rag = True
            rag_indent = indent
            rest = stripped[4:].strip()
            if rest:
                result["enabled"] = _parse_yaml_value(rest)
            continue

        if in_rag:
            # End of rag block if we hit a non-empty line at same or lower indent
            if stripped and indent <= rag_indent:
                break
            # Parse nested keys (rag.provider, rag.endpoint, etc.)
            if stripped:
                if ":" in stripped:
                    key, _, value = stripped.partition(":")
                    key = key.strip()
                    value = value.strip()
                    if value and not value.startswith("#"):
                        result[key] = _parse_yaml_value(value)

    return result if result else None


def _parse_yaml_value(value: str) -> Any:
    """Parse a simple YAML value string."""
    if value.lower() in ("true", "yes"):
        return True
    if value.lower() in ("false", "no"):
        return False
    if value.lower() == "null" or value == "~":
        return None
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return float(value)
    except ValueError:
        pass
    # Strip quotes if present
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    return value


def _load_config_from_env() -> dict[str, Any]:
    """Load RAG configuration from environment variables.

    Environment variables take precedence over file config.
    RALPH_RAG_ENABLED=true
    RALPH_RAG_PROVIDER=qdrant
    RALPH_RAG_ENDPOINT=http://localhost:6333
    RALPH_RAG_EMBEDDING_PROVIDER=openai
    RALPH_RAG_OPENAI_API_KEY=sk-...
    """
    result: dict[str, Any] = {}

    enabled = os.environ.get("RALPH_RAG_ENABLED", "false")
    result["enabled"] = enabled.lower() in ("true", "yes", "1")

    provider = os.environ.get("RALPH_RAG_PROVIDER", "qdrant")
    result["provider"] = provider

    endpoint = os.environ.get("RALPH_RAG_ENDPOINT")
    if endpoint:
        result["endpoint"] = endpoint

    api_key = os.environ.get("RALPH_RAG_API_KEY")
    if api_key:
        result["api_key"] = api_key

    embedder_provider = os.environ.get("RALPH_RAG_EMBEDDING_PROVIDER", "local")
    result["embedding"] = {"provider": embedder_provider}

    openai_key = os.environ.get("RALPH_RAG_OPENAI_API_KEY")
    if openai_key:
        result.setdefault("embedding", {})["api_key"] = openai_key

    azure_endpoint = os.environ.get("RALPH_RAG_AZURE_ENDPOINT")
    if azure_endpoint:
        result.setdefault("embedding", {})["azure_endpoint"] = azure_endpoint

    return result


def _merge_configs(file_cfg: dict[str, Any], env_cfg: dict[str, Any]) -> dict[str, Any]:
    """Merge environment config over file config (env takes precedence)."""
    merged = dict(file_cfg)
    # Deep merge for nested dicts
    for key, value in env_cfg.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
            merged[key] = {**merged[key], **value}
        else:
            merged[key] = value
    return merged
