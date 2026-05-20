"""Local embedder implementation using sentence-transformers.

Lazy-loads sentence_transformers to avoid import overhead when RAG is disabled.
"""

from __future__ import annotations

from typing import Any

from .base import Embedder, EmbedderError


class LocalEmbedder(Embedder):
    """Local embedder backed by sentence-transformers.

    Uses BAAI/bge-small-en-v1.5 by default (384-dim). Loads the model
    lazily on first embed() call to avoid startup overhead.
    """

    DEFAULT_MODEL = "BAAI/bge-small-en-v1.5"
    _model: Any = None
    _tokenizer: Any = None
    _dimensions: int = 0
    _model_name: str = ""
    _initialized: bool = False
    _import_error: Exception | None = None

    def __init__(self, model: str = DEFAULT_MODEL):
        """Initialize the LocalEmbedder.

        Does NOT load the model. Model loading happens on first embed() call.

        Args:
            model: Model name or path. Defaults to BAAI/bge-small-en-v1.5.
        """
        self._model_name = model

    @property
    def dimensions(self) -> int:
        """Number of dimensions in the embedding vector."""
        if not self._initialized:
            return 384  # Default for bge-small-en-v1.5
        return self._dimensions

    def _ensure_loaded(self) -> None:
        """Load the model lazily on first use."""
        if self._initialized:
            return

        try:
            from sentence_transformers import SentenceTransformer

            self._model = SentenceTransformer(self._model_name)
            # Get actual dimensions
            test_embedding = self._model.encode("test", show_progress_bar=False)
            self._dimensions = len(test_embedding) if test_embedding is not None else 384
            self._tokenizer = self._model.tokenizer
            self._initialized = True
        except ImportError as e:
            self._import_error = e
            raise EmbedderError(
                f"sentence-transformers is not installed. "
                f"Install with: pip install sentence-transformers"
            ) from e
        except Exception as e:
            self._import_error = e
            raise EmbedderError(
                f"Failed to load model '{self._model_name}': {e}"
            ) from e

    def embed(self, text: str) -> list[float]:
        """Embed a single text string.

        Args:
            text: Text to embed.

        Returns:
            Normalized embedding vector (list of floats).

        Raises:
            EmbedderError: On model loading or inference failure.
        """
        self._ensure_loaded()

        try:
            result = self._model.encode(text, show_progress_bar=False)
            if result is None:
                return [0.0] * self.dimensions
            return result.tolist()
        except Exception as e:
            raise EmbedderError(f"Embedding failed: {e}") from e

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Embed a batch of text strings.

        Chunks into batches of 32 to control memory usage.

        Args:
            texts: List of text strings to embed.

        Returns:
            List of embedding vectors.

        Raises:
            EmbedderError: On model loading or inference failure.
        """
        self._ensure_loaded()

        if not texts:
            return []

        results: list[list[float]] = []
        batch_size = 32

        for i in range(0, len(texts), batch_size):
            batch = texts[i : i + batch_size]
            try:
                batch_result = self._model.encode(batch, show_progress_bar=False)
                if batch_result is None:
                    batch_result = [[0.0] * self.dimensions for _ in batch]
                results.extend(r.tolist() if hasattr(r, "tolist") else [r] for r in batch_result)
            except Exception as e:
                raise EmbedderError(
                    f"Batch embedding failed (batch {i//batch_size + 1}): {e}"
                ) from e

        return results

    def health_check(self) -> dict[str, Any]:
        """Check the health of the local embedder.

        Returns:
            Dict with status, dimensions, and model info.
        """
        if not self._initialized:
            return {
                "status": "ready",
                "dimensions": self.dimensions,
                "model": self._model_name,
                "provider": "local",
                "latency_ms": 0,
            }

        return {
            "status": "ok",
            "dimensions": self.dimensions,
            "model": self._model_name,
            "provider": "local",
            "latency_ms": 0,
        }
