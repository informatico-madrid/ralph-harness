"""Unit tests for vector DB providers."""

from plugins.ralphharness.rag.providers.faiss import FAISSProvider
from plugins.ralphharness.rag.providers.qdrant import QdrantProvider


class TestFAISSProvider:
    def test_health_check_no_numpy(self) -> None:
        """When numpy/FAISS unavailable, health_check returns False."""
        p = FAISSProvider(index_dir="/tmp/nonexistent")
        assert p.health_check() is False

    def test_index_not_implemented(self) -> None:
        """FAISS is read-only per design (Decision #4)."""
        p = FAISSProvider(index_dir="/tmp/x")
        try:
            p.index([], collection="test")
            assert False, "Should raise"
        except NotImplementedError:
            pass


class TestQdrantProvider:
    def test_health_check_no_server(self) -> None:
        """When no Qdrant server, health_check returns False."""
        p = QdrantProvider(endpoint="http://nonexistent:6333")
        result = p.health_check()
        assert result is False
