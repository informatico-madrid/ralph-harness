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


class ProjectNameStep(OnboardingStep):
    """Ask for the project name used in Qdrant collection naming."""

    _CONFIG_PATH = Path.home() / ".config" / "smart-ralph" / ".ralphharness.local.md"

    @property
    def name(self) -> str:
        return "Project name"

    def detect(self) -> DetectionResult:
        """Check if project name is configured or if cwd will be used."""
        from .config import RAGConfig

        config = RAGConfig.load()
        if config.project:
            return DetectionResult(DetectionState.OK, detail=config.project)
        # Check if config file exists with rag: block but no project
        try:
            content = self._CONFIG_PATH.read_text(encoding="utf-8")
            if "rag:" in content:
                return DetectionResult(
                    DetectionState.MISSING,
                    detail="RAG configured but no project name set (will use cwd)",
                )
        except OSError:
            pass
        return DetectionResult(
            DetectionState.MISSING,
            detail="Project name not configured (will derive from cwd)",
        )

    def explain(self) -> str:
        return (
            "Set a project name for Qdrant collection naming. "
            "Collections will be named <project>-research, <project>-design, etc. "
            "If empty, the current directory name will be used."
        )

    def install_command(self) -> Optional[list[str]]:
        return None  # Handled via prompt_interactive

    def prompt_interactive(self, answer: str) -> DetectionResult:
        """Handle interactive prompt: write project name to config."""
        project = answer.strip() if answer else ""
        if not project:
            return DetectionResult(DetectionState.OK, detail="Using cwd fallback")
        try:
            import yaml as _yaml
        except ImportError:
            return DetectionResult(
                DetectionState.MISSING,
                detail="pyyaml not installed — cannot update config",
            )
        try:
            content = self._CONFIG_PATH.read_text(encoding="utf-8")
        except OSError:
            content = ""
        data: dict[str, Any] = {}
        if content:
            yaml_content: str | None = None
            if "```yaml" in content:
                start = content.find("```yaml") + 7
                while start < len(content) and content[start] in (" ", "\t"):
                    start += 1
                end = content.find("```", start)
                if end != -1:
                    yaml_content = content[start:end].strip()
            if yaml_content is None and content.lstrip().startswith("---"):
                rest = content.lstrip()[3:]
                end_idx = rest.find("---")
                if end_idx > 0:
                    yaml_content = rest[:end_idx].strip()
            if yaml_content:
                try:
                    data = _yaml.safe_load(yaml_content) or {}
                except _yaml.YAMLError:
                    pass
        if "rag" not in data or not isinstance(data["rag"], dict):
            data["rag"] = {}
        data["rag"]["project"] = project
        new_content = f"---\n{_yaml.dump(data, default_flow_style=False, sort_keys=False)}\n---\n"
        self._CONFIG_PATH.write_text(new_content, encoding="utf-8")
        return DetectionResult(DetectionState.OK, detail=project)


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


def run(steps: list[OnboardingStep], interactive: bool = True) -> dict:
    """Run the onboarding flow over a list of steps.

    For each step: detect state, explain, (optionally) prompt for confirmation,
    run install_command, then verify. Accumulate a summary.

    Returns a dict with keys: installed, already_present, skipped, failed.
    """
    total = len(steps)
    summary = {"installed": 0, "already_present": 0, "skipped": 0, "failed": 0}

    for i, step in enumerate(steps, 1):
        print(f"\n[{i}/{total}] {step.name}")
        detect_result = step.detect()
        print(f"Detect: {detect_result.state.value} – {detect_result.detail}")

        if detect_result.state == DetectionState.OK:
            print("Already present – skipping.")
            summary["already_present"] += 1
            continue

        # Explain why this step matters
        explanation = step.explain()
        print(f"Why: {explanation}")

        install_cmd = step.install_command()
        if install_cmd is not None:
            print(f"Would run: {' '.join(install_cmd)}")
        else:
            print("Would run: (no install command needed — manual step)")

        if interactive:
            try:
                answer = input("Proceed? [y/n/r/a] > ").strip().lower()
            except EOFError:
                answer = "n"

            if answer == "n":
                summary["skipped"] += 1
                print("Skipped (user declined).")
                continue
            if answer == "a":
                # Auto-approve: skip prompt for remaining
                pass  # fall through to install
            elif answer == "r":
                # Retry detect
                detect_result = step.detect()
                if detect_result.state == DetectionState.OK:
                    summary["already_present"] += 1
                    print("Already present after retry.")
                    continue
                else:
                    print(f"Retry detect still {detect_result.state.value}. Proceeding with install.")
            # y or a or default -> proceed with install
            # Special handling for steps with prompt_interactive (e.g. ProjectNameStep)
            if hasattr(step, "prompt_interactive"):
                prompt_result = step.prompt_interactive(answer)
                if prompt_result.state == DetectionState.OK:
                    summary["installed"] += 1
                    print(f"OK – {prompt_result.detail}")
                    continue
                else:
                    print(f"FAIL – {prompt_result.detail}")
                    summary["failed"] += 1
                    continue
        else:
            # Non-interactive: record MISSING steps as skipped
            summary["skipped"] += 1
            print("Skipped (non-interactive mode).")
            continue

        # Install
        if install_cmd is not None:
            print("Installing...")
            try:
                import subprocess

                subprocess.run(install_cmd, shell=False, check=False)
            except Exception as e:
                print(f"Install error: {e}")
                summary["failed"] += 1
                continue

        # Verify
        if step.verify():
            summary["installed"] += 1
            print("OK – verified.")
        else:
            summary["failed"] += 1
            print("FAIL – verification failed after install.")

    print("\nOnboarding summary:")
    print(f"  installed: {summary['installed']}")
    print(f"  already_present: {summary['already_present']}")
    print(f"  skipped: {summary['skipped']}")
    print(f"  failed: {summary['failed']}")

    return summary
