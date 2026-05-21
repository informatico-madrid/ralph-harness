"""RAG configuration loader.

Mirrors the YAML schema in design.md (Interfaces section - Configuration).
Default state is disabled - projects without a `rag:` block run with zero RAG calls.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)


# Default project config location (same pattern as other .ralphharness.*.md files)
_DEFAULT_CONFIG_PATH = Path.home() / ".config" / "smart-ralph" / ".ralphharness.local.md"


@dataclass
class EmbedderConfig:
    """Embedder provider configuration."""

    provider: str = "local"  # "local", "openai", "azure"
    model: str = "BAAI/bge-small-en-v1.5"
    api_key: Optional[str] = None
    api_base: Optional[str] = None
    fallback_order: list[str] = field(
        default_factory=lambda: ["local", "openai", "azure"]
    )
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
            result = _deep_merge(result, file_cfg)

        # Load and merge environment variables (override file config)
        env_cfg = _load_config_from_env()
        result = _deep_merge(result, env_cfg)

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
        fb_order = embedder_raw.get("fallback_order", ["local", "openai", "azure"])
        if not isinstance(fb_order, list):
            fb_order = ["local", "openai", "azure"]
        embedder = EmbedderConfig(
            provider=embedder_raw.get("provider", "local"),
            model=embedder_raw.get("model", "BAAI/bge-small-en-v1.5"),
            api_key=embedder_raw.get("api_key"),
            api_base=embedder_raw.get("api_base"),
            fallback_order=fb_order,
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

    Uses pyyaml for proper nested YAML parsing. Falls back to None
    (with warning) if pyyaml is not installed.
    """
    try:
        import yaml  # noqa: F811
    except ImportError:
        logger.warning(
            "pyyaml not installed — using default RAG config "
            "(install with: pip install pyyaml)"
        )
        return None

    try:
        content = path.read_text(encoding="utf-8")
    except (OSError, FileNotFoundError):
        return None

    yaml_content: str | None = None

    # Try ```yaml fenced block first
    start = content.find("```yaml")
    if start != -1:
        start += 7  # past "```yaml"
        # Skip trailing whitespace/newline
        while start < len(content) and content[start] in (" ", "\t"):
            start += 1
        end = content.find("```", start)
        if end != -1:
            yaml_content = content[start:end].strip()

    # Try --- delimited frontmatter
    if yaml_content is None and content.lstrip().startswith("---"):
        rest = content.lstrip()[3:]
        end_idx = rest.find("---")
        if end_idx > 0:
            yaml_content = rest[:end_idx].strip()

    if not yaml_content:
        return None

    try:
        data = yaml.safe_load(yaml_content)
    except yaml.YAMLError as exc:
        logger.warning("Failed to parse YAML frontmatter: %s", exc)
        return None

    if not isinstance(data, dict):
        return None

    # Extract rag: block if present
    if "rag" in data and isinstance(data["rag"], dict):
        return data["rag"]
    return data if data else None


def _load_config_from_env() -> dict[str, Any]:
    """Load RAG configuration from environment variables.

    Environment variables take precedence over file config.
    RALPH_RAG_ENABLED=true
    RALPH_RAG_PROVIDER=qdrant
    RALPH_RAG_ENDPOINT=http://localhost:6333
    RALPH_RAG_EMBEDDER_PROVIDER=openai
    RALPH_RAG_OPENAI_API_KEY=sk-...
    RALPH_RAG_AZURE_ENDPOINT=https://...
    """
    result: dict[str, Any] = {}

    enabled = os.environ.get("RALPH_RAG_ENABLED")
    if enabled is not None:
        result["enabled"] = enabled.lower() in ("true", "yes", "1")

    provider = os.environ.get("RALPH_RAG_PROVIDER")
    if provider:
        result["provider"] = provider

    endpoint = os.environ.get("RALPH_RAG_ENDPOINT")
    if endpoint:
        result["endpoint"] = endpoint

    api_key = os.environ.get("RALPH_RAG_API_KEY")
    if api_key:
        result["api_key"] = api_key

    # RALPH_RAG_EMBEDDER_PROVIDER (new) + backward compat RALPH_RAG_EMBEDDING_PROVIDER
    for env_var in ("RALPH_RAG_EMBEDDER_PROVIDER", "RALPH_RAG_EMBEDDING_PROVIDER"):
        provider = os.environ.get(env_var)
        if provider is not None:
            result.setdefault("embedder", {})["provider"] = provider
            break

    # RALPH_RAG_OPENAI_API_KEY read once (M2 dedup fix)
    openai_key = os.environ.get("RALPH_RAG_OPENAI_API_KEY")
    if openai_key:
        result.setdefault("embedder", {})["api_key"] = openai_key

    azure_endpoint = os.environ.get("RALPH_RAG_AZURE_ENDPOINT")
    if azure_endpoint:
        result.setdefault("embedder", {})["azure_endpoint"] = azure_endpoint

    return result


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Recursively merge override into base (override wins)."""
    result = dict(base)
    for key, value in override.items():
        if (
            key in result
            and isinstance(result[key], dict)
            and isinstance(value, dict)
        ):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result
