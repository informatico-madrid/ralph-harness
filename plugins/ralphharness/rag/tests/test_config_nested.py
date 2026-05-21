"""Tests for config.py nested YAML loading (M1)."""

from __future__ import annotations

from pathlib import Path

from plugins.ralphharness.rag.config import _load_yaml_frontmatter


def test_nested_yaml_loads_with_pyyaml(tmp_path: Path) -> None:
    """YAML with nested rag: block loads as dict with preserved nesting."""
    spec_dir = tmp_path / "specs" / "test-nested"
    spec_dir.mkdir(parents=True)
    md_file = spec_dir / "requirements.md"
    md_file.write_text(
        "```yaml\n"
        "rag:\n"
        "  enabled: true\n"
        "  provider: qdrant\n"
        "  embeddings:\n"
        "    provider: local\n"
        "  vector_db:\n"
        "    endpoint: http://localhost:6333\n"
        "    api_key: secret123\n"
        "```\n",
        encoding="utf-8",
    )

    data = _load_yaml_frontmatter(md_file)
    assert data is not None
    # _load_yaml_frontmatter extracts the rag: block contents directly
    assert data["enabled"] is True
    assert data["provider"] == "qdrant"
    assert data["embeddings"]["provider"] == "local"
    assert data["vector_db"]["endpoint"] == "http://localhost:6333"
    assert data["vector_db"]["api_key"] == "secret123"


def test_flat_yaml_still_works(tmp_path: Path) -> None:
    """Flat YAML (single-level rag: block) still works."""
    spec_dir = tmp_path / "specs" / "test-flat"
    spec_dir.mkdir(parents=True)
    md_file = spec_dir / "design.md"
    md_file.write_text(
        "---\n"
        "rag:\n"
        "  enabled: true\n"
        "  provider: qdrant\n"
        "---\n",
        encoding="utf-8",
    )

    data = _load_yaml_frontmatter(md_file)
    assert data is not None
    assert data["enabled"] is True
    assert data["provider"] == "qdrant"


def test_no_rag_block_returns_none(tmp_path: Path) -> None:
    """Spec without rag: block returns None."""
    spec_dir = tmp_path / "specs" / "test-no-rag"
    spec_dir.mkdir(parents=True)
    md_file = spec_dir / "tasks.md"
    md_file.write_text(
        "## Tasks\n\n- [x] Task 1\n- [x] Task 2\n",
        encoding="utf-8",
    )

    data = _load_yaml_frontmatter(md_file)
    assert data is None


def test_ragged_enabled_flag(tmp_path: Path) -> None:
    """enabled: false disables RAG."""
    spec_dir = tmp_path / "specs" / "test-disabled"
    spec_dir.mkdir(parents=True)
    md_file = spec_dir / "config.md"
    md_file.write_text(
        "```yaml\n"
        "rag:\n"
        "  enabled: false\n"
        "```\n",
        encoding="utf-8",
    )

    data = _load_yaml_frontmatter(md_file)
    assert data is not None
    assert data["enabled"] is False

