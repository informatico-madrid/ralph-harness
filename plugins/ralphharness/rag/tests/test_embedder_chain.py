"""Unit tests for embedder fallback chain."""

from plugins.ralphharness.rag.embedder.chain import EmbedderChain
from plugins.ralphharness.rag.embedder.base import EmbedderError


class TestEmbedderChain:
    def test_chain_exhausted_no_deps(self) -> None:
        """When no embedder libraries are installed, chain returns EmbedderError."""
        chain = EmbedderChain([])
        try:
            chain.embed("test")
            assert False, "Should raise"
        except EmbedderError:
            pass  # Expected

    def test_embed_returns_empty_with_no_embedders(self) -> None:
        chain = EmbedderChain([])
        try:
            chain.embed("test")
            assert False, "Should raise"
        except EmbedderError:
            pass
