"""OnboardingStep framework for RAG integration setup.

Provides a step-based onboarding system with detection, explanation,
installation commands, and verification.
"""

from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional


class DetectionState(str, Enum):
    """Detection state for an onboarding step."""

    OK = "ok"
    MISSING = "missing"
    UNKNOWN = "unknown"


@dataclass
class DetectionResult:
    """Result of detecting whether a step is satisfied."""

    state: DetectionState
    detail: str = ""


class OnboardingStep(ABC):
    """Base class for onboarding steps."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Human-readable step name."""

    @abstractmethod
    def detect(self) -> DetectionResult:
        """Detect whether this step's requirements are met."""

    @abstractmethod
    def explain(self) -> str:
        """Explain what this step does and why it matters."""

    @abstractmethod
    def install_command(self) -> Optional[list[str]]:
        """Return argv list to install this step, or None if no install needed.

        MUST return a list of strings — NEVER a joined string.
        """

    def verify(self) -> bool:
        """Verify the step is still satisfied after installation."""
        return self.detect().state == DetectionState.OK


class PythonStep(OnboardingStep):
    """Check that Python 3.10+ is available."""

    @property
    def name(self) -> str:
        return "Python 3.10+"

    def detect(self) -> DetectionResult:
        import sys

        if sys.version_info >= (3, 10):
            return DetectionResult(DetectionState.OK, detail=f"Python {sys.version_info.major}.{sys.version_info.minor}")
        return DetectionResult(DetectionState.MISSING, detail="Python 3.10+ required")

    def explain(self) -> str:
        return "Python 3.10+ is required to run the RAG integration."

    def install_command(self) -> Optional[list[str]]:
        return None


class PythonDepsStep(OnboardingStep):
    """Install Python package dependencies."""

    @property
    def name(self) -> str:
        return "Python dependencies"

    def detect(self) -> DetectionResult:
        try:
            import qdrant_client  # noqa: F401
            import faiss  # noqa: F401
            import yaml  # noqa: F401
            return DetectionResult(DetectionState.OK, detail="All deps installed")
        except ImportError:
            return DetectionResult(DetectionState.MISSING, detail="qdrant-client, faiss-cpu, pyyaml not found")

    def explain(self) -> str:
        return "Install Python packages: qdrant-client, faiss-cpu, pyyaml."

    def install_command(self) -> Optional[list[str]]:
        return ["pip", "install", "qdrant-client", "faiss-cpu", "pyyaml"]


class VectorDBStep(OnboardingStep):
    """Check/install a vector database (Qdrant via Docker)."""

    @property
    def name(self) -> str:
        return "Vector database"

    def detect(self) -> DetectionResult:
        try:
            import docker
            client = docker.from_env()
            try:
                client.containers.get("smart-ralph-qdrant")
                return DetectionResult(DetectionState.OK, detail="Qdrant container running")
            except docker.errors.NotFound:
                pass
        except Exception:
            pass
        return DetectionResult(DetectionState.UNKNOWN, detail="No Qdrant container detected")

    def explain(self) -> str:
        return "Start a Qdrant container for the vector database."

    def install_command(self) -> Optional[list[str]]:
        return ["docker", "run", "-d", "--name", "smart-ralph-qdrant", "-p", "6333:6333", "qdrant/qdrant:1.7.0"]


class EmbedderStep(OnboardingStep):
    """Check/install embedder dependencies."""

    @property
    def name(self) -> str:
        return "Embedder library"

    def detect(self) -> DetectionResult:
        try:
            import sentence_transformers  # noqa: F401
            return DetectionResult(DetectionState.OK, detail="sentence-transformers available")
        except ImportError:
            return DetectionResult(DetectionState.MISSING, detail="sentence-transformers not installed")

    def explain(self) -> str:
        return "Install sentence-transformers for local embedding."

    def install_command(self) -> Optional[list[str]]:
        return ["pip", "install", "sentence-transformers"]


class ConfigStep(OnboardingStep):
    """Check RAG configuration in .ralphharness.local.md."""

    @property
    def name(self) -> str:
        return "RAG configuration"

    def detect(self) -> DetectionResult:
        path = Path.home() / ".config" / "smart-ralph" / ".ralphharness.local.md"
        if not path.exists():
            return DetectionResult(DetectionState.MISSING, detail="Config file not found")
        content = path.read_text()
        if "rag:" in content:
            return DetectionResult(DetectionState.OK, detail="RAG config found")
        return DetectionResult(DetectionState.MISSING, detail="No rag: block in config")

    def explain(self) -> str:
        return "Add a `rag:` block to `.ralphharness.local.md`."

    def install_command(self) -> Optional[list[str]]:
        return None


class IndexBootstrapStep(OnboardingStep):
    """Check that indexing has been performed."""

    @property
    def name(self) -> str:
        return "Index bootstrap"

    def detect(self) -> DetectionResult:
        lock_path = Path.home() / ".cache" / "smart-ralph" / "rag" / "index-all.lock"
        if not lock_path.exists():
            return DetectionResult(DetectionState.MISSING, detail="Index has not been bootstrapped")
        mtime = lock_path.stat().st_mtime
        if (time.time() - mtime) > 3600:
            return DetectionResult(DetectionState.UNKNOWN, detail="Index is older than 1 hour")
        return DetectionResult(DetectionState.OK, detail="Index is recent")

    def explain(self) -> str:
        return "Run `/ralphharness:index-all` to bootstrap the RAG index."

    def install_command(self) -> Optional[list[str]]:
        return ["python", "-m", "plugins.ralphharness.rag", "index-all"]


class DoctorStep(OnboardingStep):
    """Run rag-doctor to verify health."""

    @property
    def name(self) -> str:
        return "Doctor check"

    def detect(self) -> DetectionResult:
        from .config import RAGConfig

        config = RAGConfig.load()
        if not config.enabled:
            return DetectionResult(DetectionState.OK, detail="RAG disabled, doctor not needed")
        try:
            from .providers.qdrant import QdrantProvider

            p = QdrantProvider(endpoint=config.vector_db.endpoint or "http://localhost:6333")
            if p.health_check():
                return DetectionResult(DetectionState.OK, detail="RAG health check passed")
            return DetectionResult(DetectionState.UNKNOWN, detail="RAG health check returned false")
        except Exception as e:
            return DetectionResult(DetectionState.UNKNOWN, detail=f"Doctor check failed: {e}")

    def explain(self) -> str:
        return "Run `/ralphharness:rag-doctor` to verify RAG health."

    def install_command(self) -> Optional[list[str]]:
        return None
