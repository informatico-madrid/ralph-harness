"""Shared test fixtures for RAG integration tests."""

from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Generator

import pytest


@pytest.fixture()
def tmp_cache_dir() -> Generator[Path, None, None]:
    """Provide a temporary cache directory for RAG artifacts."""
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


@pytest.fixture()
def sample_chunk() -> object:
    """Provide a basic Chunk instance for testing."""
    from plugins.ralphharness.rag.types import Chunk

    return Chunk(content="hello world", source_path="test.md", spec_name="test")


@pytest.fixture()
def sample_secret_chunk() -> object:
    """Provide a Chunk containing a secret pattern."""
    from plugins.ralphharness.rag.types import Chunk

    return Chunk(
        content="AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE",
        source_path="test.md",
        spec_name="test",
    )


@pytest.fixture()
def sample_markdown() -> str:
    return "# Root\nSome intro text.\n\n## Section One\nContent here.\n\n### Subsection\nMore detail.\n\n## Section Two\nContent two.\n"


@pytest.fixture()
def sample_jsonl() -> str:
    return '{"key": "value 1"}\n{"key": "value 2"}\n{"key": "value 3"}\n'


@pytest.fixture()
def sample_python() -> str:
    return '''def hello():
    return "hello"

class MyClass:
    def greet(self):
        return "hi"

def goodbye():
    return "bye"
'''
