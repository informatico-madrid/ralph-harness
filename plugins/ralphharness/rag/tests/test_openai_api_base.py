"""Tests for OpenAI embedder api_base support."""

import sys
import types
from unittest import mock

import pytest

from plugins.ralphharness.rag.embedder.openai import OpenAIEmbedder


_OPENAI_STUB: types.ModuleType | None = None


@pytest.fixture(autouse=True)
def _openai_stub() -> None:
    """Ensure openai module exists in sys.modules for mock.patch to work."""
    global _OPENAI_STUB
    _OPENAI_STUB = types.ModuleType("openai")
    _OPENAI_STUB.OpenAI = mock.MagicMock
    sys.modules["openai"] = _OPENAI_STUB
    yield
    sys.modules.pop("openai", None)


class TestOpenAIBaseUrl:
    def test_default_no_base_url(self) -> None:
        """Without api_base, OpenAI client uses default endpoint."""
        embedder = OpenAIEmbedder(api_key="test-key")
        mock_openai_cls = mock.MagicMock()

        with mock.patch("openai.OpenAI", mock_openai_cls):
            embedder._get_client()

        mock_openai_cls.assert_called_once_with(api_key="test-key", timeout=30.0)

    def test_passes_api_base_as_base_url(self) -> None:
        """When api_base is set, it is passed as base_url to OpenAI client."""
        embedder = OpenAIEmbedder(
            api_key="test-key",
            api_base="http://localhost:8001/v1",
        )
        mock_openai_cls = mock.MagicMock()

        with mock.patch("openai.OpenAI", mock_openai_cls):
            embedder._get_client()

        mock_openai_cls.assert_called_once_with(
            api_key="test-key",
            timeout=30.0,
            base_url="http://localhost:8001/v1",
        )

    def test_health_check_makes_real_call(self) -> None:
        """health_check should actually call the API to verify connectivity."""
        mock_response = mock.MagicMock()
        mock_response.data = [mock.MagicMock(embedding=[0.1] * 1536)]

        mock_client = mock.MagicMock()
        mock_client.embeddings.create.return_value = mock_response

        embedder = OpenAIEmbedder(api_key="test-key")
        embedder._client = mock_client

        health = embedder.health_check()

        mock_client.embeddings.create.assert_called_once()
        assert health["status"] == "ok"
        assert "latency_ms" in health
        assert health["latency_ms"] >= 0

    def test_health_check_returns_unhealthy_on_error(self) -> None:
        """health_check returns 'unhealthy' when API call fails."""
        mock_client = mock.MagicMock()
        mock_client.embeddings.create.side_effect = Exception("connection refused")

        embedder = OpenAIEmbedder(api_key="test-key")
        embedder._client = mock_client

        health = embedder.health_check()

        assert health["status"] == "unhealthy"
        assert "connection refused" in health["error"]
