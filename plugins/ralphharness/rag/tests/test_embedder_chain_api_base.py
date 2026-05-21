"""Tests for api_base passthrough in embedder chain."""

from unittest import mock

import pytest

from plugins.ralphharness.rag.config import RAGConfig, EmbedderConfig, VectorDBConfig
from plugins.ralphharness.rag.embedder.chain import from_config


class TestEmbedderChainApiBase:
    def test_passes_api_base_to_openai_embedder(self) -> None:
        """EmbedderChain.from_config should pass api_base to OpenAIEmbedder."""
        config = RAGConfig(
            enabled=True,
            embedder=EmbedderConfig(
                provider="openai",
                api_key="test-key",
                api_base="http://localhost:8001/v1",
                fallback_order=["openai"],
            ),
            vector_db=VectorDBConfig(provider="qdrant", endpoint="http://localhost:6333"),
        )

        with mock.patch(
            "plugins.ralphharness.rag.embedder.openai.OpenAIEmbedder"
        ) as mock_embedder_cls:
            from_config(config)

            mock_embedder_cls.assert_called_once()
            call_kwargs = mock_embedder_cls.call_args.kwargs
            assert call_kwargs["api_key"] == "test-key"
            assert call_kwargs["api_base"] == "http://localhost:8001/v1"
