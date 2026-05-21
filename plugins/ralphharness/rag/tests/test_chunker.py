"""Unit tests for Chunker."""

from plugins.ralphharness.rag.chunker import Chunker


class TestChunkerMarkdown:
    def test_splits_on_headings(self, sample_markdown: str) -> None:
        chunks = Chunker().chunk("test.md", sample_markdown)
        assert len(chunks) >= 1

    def test_includes_spec_name(self, sample_markdown: str) -> None:
        chunks = Chunker().chunk("specs/foo/file.md", sample_markdown)
        for c in chunks:
            assert c.spec_name == "foo"

    def test_empty_content(self) -> None:
        chunks = Chunker().chunk("test.md", "")
        assert len(chunks) == 0


class TestChunkerJSONL:
    def test_one_chunk_per_line(self, sample_jsonl: str) -> None:
        chunks = Chunker().chunk("data.jsonl", sample_jsonl)
        assert len(chunks) == 3

    def test_skips_empty_lines(self) -> None:
        chunks = Chunker().chunk("data.jsonl", '{"a":1}\n\n{"b":2}\n')
        assert len(chunks) == 2


class TestChunkerPython:
    def test_splits_by_function(self) -> None:
        content = "def hello():\n    pass\n\ndef goodbye():\n    pass\n"
        chunks = Chunker().chunk("test.py", content)
        all_text = "\n".join(c.content for c in chunks)
        assert "def hello" in all_text and "def goodbye" in all_text

    def test_empty_python_file(self) -> None:
        chunks = Chunker().chunk("test.py", "")
        assert len(chunks) == 1


class TestChunkerUnknown:
    def test_single_chunk_for_unknown_ext(self) -> None:
        chunks = Chunker().chunk("file.txt", "hello world")
        assert len(chunks) == 1
