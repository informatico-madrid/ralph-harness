"""OpenAI embedder implementation.

Lazy-loads the openai package to avoid import overhead when RAG is disabled.
"""

from __future__ import annotations

from typing import Any

from .base import Embedder, EmbedderError


class OpenAIEmbedder(Embedder):
    """OpenAI API embedder.

    Uses text-embedding-3-small by default (1536-dim). Raises EmbedderError
    on auth/rate-limit/network failure (caught by fallback chain).
    """

    DEFAULT_MODEL = "text-embedding-3-small"
    _dimensions_map: dict[str, int] = {
        "text-embedding-3-small": 1536,
        "text-embedding-3-large": 3072,
        "text-embedding-ada-002": 1536,
    }

    def __init__(self, api_key: str, model: str = DEFAULT_MODEL, api_base: str | None = None):
        """Initialize the OpenAI embedder.

        Args:
            api_key: OpenAI API key.
            model: Model name. Defaults to text-embedding-3-small.
            api_base: Optional custom API base URL (for local OpenAI-compatible endpoints).
        """
        self._api_key = api_key
        self._model = model
        self._api_base = api_base
        self._client: Any = None

    @property
    def dimensions(self) -> int:
        """Number of dimensions in the embedding vector."""
        return self._dimensions_map.get(self._model, 1536)

    def _get_client(self) -> Any:
        """Get the OpenAI client (lazy import + cache)."""
        if self._client is None:
            try:
                from openai import OpenAI
            except ImportError as e:
                raise EmbedderError(
                    "openai package is not installed. "
                    "Install with: pip install openai"
                ) from e
            kwargs: dict[str, Any] = {"api_key": self._api_key, "timeout": 30.0}
            if self._api_base:
                kwargs["base_url"] = self._api_base
            self._client = OpenAI(**kwargs)
        return self._client

    def embed(self, text: str) -> list[float]:
        """Embed a single text string.

        Args:
            text: Text to embed.

        Returns:
            Normalized embedding vector (list of floats).

        Raises:
            EmbedderError: On auth/rate-limit/network failure.
        """
        client = self._get_client()

        try:
            response = client.embeddings.create(
                model=self._model,
                input=text,
            )
            data = response.data[0].embedding
            if data is None:
                return [0.0] * self.dimensions
            return data
        except Exception as e:
            # Normalize all errors to EmbedderError for fallback chain
            raise EmbedderError(f"OpenAI embedding failed: {e}") from e

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Embed a batch of text strings.

        Uses the OpenAI API's batch input support.

        Args:
            texts: List of text strings to embed.

        Returns:
            List of embedding vectors.

        Raises:
            EmbedderError: On any embedding failure.
        """
        client = self._get_client()

        if not texts:
            return []

        try:
            response = client.embeddings.create(
                model=self._model,
                input=texts,
            )
            results = [d.embedding for d in response.data if d.embedding is not None]
            if len(results) != len(texts):
                raise EmbedderError(
                    f"Batch embedding returned {len(results)} vectors for "
                    f"{len(texts)} inputs"
                )
            return results
        except Exception as e:
            raise EmbedderError(
                f"OpenAI batch embedding failed: {e}"
            ) from e

    def health_check(self) -> dict[str, Any]:
        """Check the health of the OpenAI embedder via a test API call."""
        import time

        start = time.monotonic()
        try:
            client = self._get_client()
            client.embeddings.create(model=self._model, input="health_check")
            latency_ms = (time.monotonic() - start) * 1000
            return {
                "status": "ok",
                "dimensions": self.dimensions,
                "model": self._model,
                "provider": "openai",
                "latency_ms": round(latency_ms, 1),
            }
        except Exception as e:
            return {
                "status": "unhealthy",
                "dimensions": self.dimensions,
                "model": self._model,
                "provider": "openai",
                "latency_ms": 0,
                "error": str(e),
            }
