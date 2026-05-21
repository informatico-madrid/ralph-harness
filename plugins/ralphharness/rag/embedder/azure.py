"""Azure OpenAI embedder implementation.

Lazy-loads the openai package to avoid import overhead when RAG is disabled.
When endpoint is empty, embed() raises EmbedderError so the fallback chain
skips it silently.
"""

from __future__ import annotations

from typing import Any

from .base import Embedder, EmbedderError


class AzureOpenAIEmbedder(Embedder):
    """Azure OpenAI API embedder.

    Wraps openai.AzureOpenAI. If endpoint is "", embed() raises
    EmbedderError immediately so the fallback chain skips it silently.
    """

    _dimensions_map: dict[str, int] = {
        "text-embedding-3-small": 1536,
        "text-embedding-3-large": 3072,
        "text-embedding-ada-002": 1536,
    }

    def __init__(
        self,
        endpoint: str,
        api_key: str,
        deployment_name: str = "text-embedding-3-small",
    ):
        """Initialize the Azure OpenAI embedder.

        Args:
            endpoint: Azure OpenAI endpoint URL (e.g. "https://...openai.azure.com").
                Empty string means "unconfigured" — embed() raises EmbedderError.
            api_key: Azure OpenAI API key.
            deployment_name: Deployment name for the embedding model.
        """
        self._endpoint = endpoint
        self._api_key = api_key
        self._deployment_name = deployment_name
        self._client: Any = None

    @property
    def dimensions(self) -> int:
        """Number of dimensions in the embedding vector."""
        return self._dimensions_map.get(self._deployment_name, 1536)

    def _get_client(self) -> Any:
        """Get the Azure OpenAI client (lazy import + cache).

        Raises EmbedderError if endpoint is not configured.
        """
        if not self._endpoint:
            raise EmbedderError("azure not configured")

        if self._client is None:
            try:
                from openai import AzureOpenAI
            except ImportError as e:
                raise EmbedderError(
                    "openai package is not installed. "
                    "Install with: pip install openai"
                ) from e
            self._client = AzureOpenAI(
                api_key=self._api_key,
                api_version="2023-05-15",
                azure_endpoint=self._endpoint,
                timeout=30.0,
            )
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
                model=self._deployment_name,
                input=text,
            )
            data = response.data[0].embedding
            if data is None:
                return [0.0] * self.dimensions
            return data
        except Exception as e:
            raise EmbedderError(f"Azure OpenAI embedding failed: {e}") from e

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Embed a batch of text strings.

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
                model=self._deployment_name,
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
                f"Azure OpenAI batch embedding failed: {e}"
            ) from e

    def health_check(self) -> dict[str, Any]:
        """Check the health of the Azure OpenAI embedder.

        Returns:
            Dict with status, dimensions, and deployment info.
        """
        if not self._endpoint:
            return {
                "status": "configured",
                "dimensions": self.dimensions,
                "model": self._deployment_name,
                "provider": "azure",
                "latency_ms": 0,
            }
        return {
            "status": "ok",
            "dimensions": self.dimensions,
            "model": self._deployment_name,
            "provider": "azure",
            "latency_ms": 0,
        }
