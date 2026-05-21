"""Abstract base class for embedders and EmbedderError.

Concrete embedders: LocalEmbedder, OpenAIEmbedder, AzureOpenAIEmbedder.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Iterable
from typing import Any


class EmbedderError(Exception):
    """Base exception for embedder errors.

    Raised on auth failures, rate limits, network errors, and model loading
    issues. Catching this allows graceful fallback in the embedder chain.
    """


class Embedder(ABC):
    """Abstract base class for text embedders.

    All embedders must implement embed (single text), embed_batch (batch),
    and expose a dimensions property.
    """

    @property
    def tokenizer(self) -> Iterable[str] | None:
        """Tokenizer for approximate token counting.

        Returns an iterable of token strings, or None if unavailable.
        Subclasses (e.g. LocalEmbedder) populate this after model load.
        """
        return None

    @property
    @abstractmethod
    def dimensions(self) -> int:
        """Number of dimensions in the embedding vector."""

    @abstractmethod
    def embed(self, text: str) -> list[float]:
        """Embed a single text string.

        Args:
            text: Text to embed.

        Returns:
            Normalized embedding vector (list of floats).

        Raises:
            EmbedderError: On authentication, rate limit, or network failure.
        """

    @abstractmethod
    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Embed a batch of text strings.

        Args:
            texts: List of text strings to embed.

        Returns:
            List of embedding vectors, one per input text.

        Raises:
            EmbedderError: On any error during batch embedding.
        """

    @abstractmethod
    def health_check(self) -> dict[str, Any]:
        """Check the health of the embedder.

        Returns:
            Dict with status, latency_ms, and provider-specific details.
        """
