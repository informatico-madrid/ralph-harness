"""Embedder fallback chain.

Tries each embedder in order; on EmbedderError, logs WARN and tries next.
All exhausted raises EmbedderError("chain exhausted").
"""

from __future__ import annotations

import logging
from typing import Any

from .base import Embedder, EmbedderError

logger = logging.getLogger(__name__)


class EmbedderChain(Embedder):
    """Fallback chain for embedders.

    Tries each embedder in order. On EmbedderError, logs WARN and
    tries the next embedder. All exhausted raises EmbedderError.
    """

    def __init__(self, embedders: list[Embedder]):
        """Initialize with ordered embedders.

        Args:
            embedders: List of embedders to try in order.
        """
        self._embedders = embedders

    @property
    def dimensions(self) -> int:
        """Number of dimensions — returns the first embedder's dimensions."""
        if self._embedders:
            return self._embedders[0].dimensions
        return 0

    def embed(self, text: str) -> list[float]:
        """Embed a single text string using the fallback chain.

        Tries each embedder in order. On EmbedderError, logs WARN and
        tries the next embedder.

        Args:
            text: Text to embed.

        Returns:
            Embedding vector from the first successful embedder.

        Raises:
            EmbedderError: If all embedders fail.
        """
        errors: list[str] = []
        for i, embedder in enumerate(self._embedders):
            try:
                return embedder.embed(text)
            except EmbedderError as e:
                errors.append(f"embedder[{i}] ({type(embedder).__name__}): {e}")
                logger.warning("Embedder %s failed: %s -- trying next", i, e)
        raise EmbedderError(
            "Chain exhausted: " + "; ".join(errors)
        )

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Embed a batch using the first available embedder.

        Uses the first working embedder for the entire batch.

        Args:
            texts: List of text strings to embed.

        Returns:
            List of embedding vectors.

        Raises:
            EmbedderError: If all embedders fail.
        """
        if not texts:
            return []

        errors: list[str] = []
        for i, embedder in enumerate(self._embedders):
            try:
                return embedder.embed_batch(texts)
            except EmbedderError as e:
                errors.append(f"embedder[{i}] ({type(embedder).__name__}): {e}")
                logger.warning("Embedder %s failed: %s -- trying next", i, e)
        raise EmbedderError(
            "Chain exhausted: " + "; ".join(errors)
        )

    def health_check(self) -> dict[str, Any]:
        """Health check for all embedders in the chain.

        Returns:
            Dict with chain-level status and per-embedder results.
        """
        embedder_health: list[dict[str, Any]] = []
        any_ok = False

        for embedder in self._embedders:
            health = embedder.health_check()
            embedder_health.append(health)
            if health.get("status") in ("ok", "ready"):
                any_ok = True

        return {
            "status": "ok" if any_ok else "degraded",
            "dimensions": self.dimensions,
            "provider": "chain",
            "latency_ms": 0,
            "embedders": embedder_health,
        }


def from_config(config: Any) -> EmbedderChain:
    """Build an EmbedderChain from RAGConfig.

    Builds embedders based on the configured fallback order.
    Only the embedders listed in config.embedder.fallback_order
    are included, in the exact order specified.

    Args:
        config: RAGConfig instance.

    Returns:
        EmbedderChain with configured embedders.
    """
    fallback_order = getattr(
        config.embedder, "fallback_order", ["local", "openai", "azure"]
    )
    api_key = getattr(config.embedder, "api_key", None)

    embedders: list[Embedder] = []

    for step in fallback_order:
        try:
            if step == "local":
                from .local import LocalEmbedder

                model = getattr(config.embedder, "model", "BAAI/bge-small-en-v1.5")
                embedders.append(LocalEmbedder(model=model))
            elif step == "openai" and api_key:
                from .openai import OpenAIEmbedder

                openai_model = getattr(
                    config.embedder, "openai_model", "text-embedding-3-small"
                )
                embedders.append(
                    OpenAIEmbedder(api_key=api_key, model=openai_model)
                )
            elif step == "azure":
                from .azure import AzureOpenAIEmbedder

                azure_endpoint = getattr(config.embedder, "azure_endpoint", None)
                azure_deployment = getattr(
                    config.embedder, "azure_deployment", ""
                )
                if azure_endpoint:
                    embedders.append(
                        AzureOpenAIEmbedder(
                            endpoint=azure_endpoint,
                            deployment_name=azure_deployment,
                            api_key=api_key or "",
                        )
                    )
        except Exception:
            pass

    return EmbedderChain(embedders)
