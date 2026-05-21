"""CLI entry point for the RAG integration module.

Usage: python -m plugins.ralphharness.rag <command> [options]

Subcommands: retrieve, index, index-all, doctor, search, onboard
"""

import argparse
import fcntl
import json
import os
import sys
import time
from typing import Optional
from pathlib import Path


def _print_stub(**kwargs):
    """Print a JSON stub and exit successfully."""
    result = {"stub": True, **kwargs}
    print(json.dumps(result))
    sys.exit(0)


def cmd_retrieve(args):
    """Retrieve subcommand — wire to RAGService."""
    from time import time

    from .service import RAGService

    start = time()
    service = RAGService.from_config()

    if service is None:
        print("[]")
        sys.exit(0)

    try:
        results = service.retrieve(args.query, args.collection, args.top_k)
    except Exception as e:
        print("[]", file=sys.stderr)
        import logging

        logging.getLogger("rag").warning("Retrieve failed: %s", e)
        print("[]")
        sys.exit(0)

    latency_ms = (time() - start) * 1000

    if not results:
        print("[]")
        sys.exit(0)

    provider_name = type(service._provider).__name__.lower()
    embedder_name = type(service._embedder).__name__.lower()

    chunks = []
    for r in results:
        chunks.append(
            {
                "content": r.content[:500],
                "source_path": r.source_path,
                "score": r.score,
            }
        )

    envelope = {
        "provider_used": provider_name,
        "embedder_used": embedder_name,
        "latency_ms": round(latency_ms, 1),
        "results": chunks,
    }
    print(json.dumps(envelope))
    sys.exit(0)


def cmd_index(args):
    """Stub index command."""
    _print_stub(command="index")


def cmd_index_all(args):
    """Index all spec artifacts with flock-based rate limiting."""
    from time import time

    from .config import RAGConfig
    from .service import RAGService

    config = RAGConfig.load()

    lock_dir = Path.home() / ".cache" / "smart-ralph" / "rag"
    lock_dir.mkdir(parents=True, exist_ok=True)
    lock_path = lock_dir / "index-all.lock"

    lock_fd: Optional[int] = None

    def _acquire_lock() -> Optional[int]:
        """Acquire exclusive lock with PID-validated steal.

        Uses "a+" (append) mode so the existing PID file is NOT truncated before
        flock succeeds — truncating the holder's PID would break the stale-mtime /
        PID-validation steal logic below. Only after the lock is held do we
        truncate and write our own PID.
        """
        fd = open(lock_path, "a+")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            # We now own the lock — safe to overwrite PID
            fd.seek(0)
            fd.truncate()
            fd.write(str(os.getpid()))
            fd.flush()
            return fd  # Got it immediately
        except BlockingIOError:
            pass

        # Lock held by another process — check mtime for soft rate limit
        try:
            st = lock_path.stat()
            mtime = st.st_mtime
            if (time() - mtime) < 60:
                fd.close()
                return None  # Not stale, reject
        except OSError:
            fd.close()
            return None

        # Stale lock (> 60s) — try to steal
        try:
            pid = int(lock_path.read_text().strip())
        except (ValueError, OSError):
            pid = 0

        # Only steal if PID is dead
        if pid > 0:
            try:
                os.kill(pid, 0)
                # PID alive — do not steal
                fd.close()
                return None
            except OSError:
                pass  # PID dead, safe to steal

        # Close the leaked fd from the failed flock attempt before reopening for steal.
        fd.close()
        lock_path.unlink(missing_ok=True)
        fd = open(lock_path, "w")
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fd.write(str(os.getpid()))
        fd.flush()
        return fd

    lock_fd = _acquire_lock()
    if lock_fd is None:
        print(json.dumps({"error": "another index-all is in progress"}))
        sys.exit(1)

    try:
        if args.dry_run:
            # Stream per-spec dry-run progress
            specs = Path("specs")
            if specs.is_dir():
                for spec_dir in sorted(
                    d for d in specs.iterdir()
                    if d.is_dir() and not d.name.startswith(".")
                ):
                    print(json.dumps({
                        "phase": "dry-run",
                        "spec": spec_dir.name,
                        "status": "ok",
                    }))
            else:
                print(json.dumps({"phase": "dry-run", "status": "ok"}))
            sys.exit(0)

        service = RAGService.from_config()
        if service is None:
            print(json.dumps({"error": "RAG service not available"}))
            sys.exit(1)

        def _on_progress(spec_name, status, total):
            print(json.dumps({
                "phase": "indexing",
                "spec": spec_name,
                "status": status,
                "total": total,
            }))
            sys.stdout.flush()

        service.index_all("specs", on_progress=_on_progress)
        print(json.dumps({"phase": "complete", "status": "ok"}))
    finally:
        if lock_fd is not None:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            except Exception:
                pass
            try:
                lock_fd.close()
            except Exception:
                pass


def cmd_doctor(args):
    """Doctor command: tiered health report with actual connectivity tests."""
    from .config import RAGConfig

    config = RAGConfig.load()

    checks = []

    # Phase 1: Config validation
    if not config.enabled:
        checks.append("WARN   enabled: false (RAG is disabled)")
        print("\n".join(checks))
        sys.exit(0)

    checks.append("OK     enabled: true")
    checks.append(f"OK     provider: {config.provider}")

    # Embedder config check
    ep = config.embedder.provider
    if ep == "local":
        checks.append("OK     embedder.provider: local (sentence-transformers)")
    elif ep == "openai":
        has_key = bool(config.embedder.api_key)
        checks.append(f"OK     embedder.provider: openai {'(key configured)' if has_key else '(no API key)'}")
    elif ep == "azure":
        has_ep = bool(config.embedder.azure_endpoint)
        checks.append(f"OK     embedder.provider: azure {'(endpoint configured)' if has_ep else '(no endpoint)'}")
    else:
        checks.append(f"WARN   embedder.provider: unknown ({ep})")

    # Vector DB endpoint check
    if config.provider == "qdrant":
        checks.append(f"OK     vector_db.endpoint: {config.vector_db.endpoint}")
    elif config.provider == "faiss":
        path = config.vector_db.faiss_index_path
        checks.append(f"OK     faiss.index_path: {path}" if path else "WARN   faiss.index_path: not configured")

    # Phase 2: Build RAGService for real connectivity tests
    from .service import RAGService

    service = RAGService.from_config()
    if service is None:
        checks.append("FAIL   service: unable to build RAGService (provider/embedder unavailable)")
        print("\n".join(checks))
        sys.exit(0)

    # Phase 3: Provider health check (actual connectivity)
    try:
        if service._provider.health_check():
            checks.append("OK     provider.connectivity: reachable")
        else:
            checks.append("FAIL   provider.connectivity: unreachable")
    except Exception as e:
        checks.append(f"FAIL   provider.connectivity: {e}")

    # Phase 4: Embedder health check (actual call)
    try:
        embedder_health = service._embedder.health_check()
        status = embedder_health.get("status", "unknown")
        dim = embedder_health.get("dimensions", 0)
        if status in ("ok", "ready"):
            checks.append(f"OK     embedder.connectivity: ready (dimensions: {dim})")
        elif status == "unhealthy":
            checks.append(f"FAIL   embedder.connectivity: {embedder_health.get('error', 'unknown')}")
        else:
            checks.append(f"WARN   embedder.connectivity: {status}")
    except Exception as e:
        checks.append(f"FAIL   embedder.connectivity: {e}")

    # Phase 5: Per-collection info
    try:
        all_collections = service._provider.list_collections()
        if not all_collections:
            checks.append("INFO   collections: none indexed (run index-all first)")
        else:
            checks.append(f"OK     collections: {len(all_collections)} indexed")
            embedder_dim = embedder_health.get("dimensions", 0)
            for coll in sorted(all_collections):
                try:
                    if hasattr(service._provider, "_get_client"):
                        client = service._provider._get_client()
                        if client:
                            info = client.get_collection(coll)
                            points = info.points_count or 0
                            vc = info.config.params.vectors if hasattr(info.config.params, "vectors") else None
                            vec_size = vc.size if vc and hasattr(vc, "size") else 0
                            checks.append(f"OK     collection.{coll}: {points} points, {vec_size} dims")
                            if vec_size and embedder_dim and vec_size != embedder_dim:
                                checks.append(f"WARN   collection.{coll}: vector dims ({vec_size}) != embedder dims ({embedder_dim})")
                except Exception as e:
                    checks.append(f"WARN   collection.{coll}: could not get info ({e})")
    except Exception as e:
        checks.append(f"WARN   collections: could not list ({e})")

    print("\n".join(checks))
    sys.exit(0)


def cmd_search(args):
    """Search indexed artifacts for relevant context."""
    from .service import RAGService

    service = RAGService.from_config()

    if service is None:
        print("(no results)")
        sys.exit(0)

    try:
        results = service.retrieve(args.query, "all", args.top_k)
    except Exception as e:
        print(f"(search error: {e})")
        sys.exit(0)

    if not results:
        print("(no results)")
        sys.exit(0)

    for i, r in enumerate(results, 1):
        print(f"{i}. {r.source_path}:{r.source_line_start} (score: {r.score:.3f})")
        print(f"   {r.content[:200]}")
    sys.exit(0)


def cmd_onboard(args):
    """Onboard subcommand: run the 8-step installer."""
    from .onboarding import (
        ConfigStep,
        DoctorStep,
        EmbedderStep,
        IndexBootstrapStep,
        ProjectNameStep,
        PythonDepsStep,
        PythonStep,
        VectorDBStep,
        run,
    )

    steps = [
        PythonStep(),
        PythonDepsStep(),
        VectorDBStep(),
        ProjectNameStep(),
        EmbedderStep(),
        ConfigStep(),
        IndexBootstrapStep(),
        DoctorStep(),
    ]

    interactive = not getattr(args, "non_interactive", False)
    run(steps, interactive=interactive)


def main():
    parser = argparse.ArgumentParser(
        prog="plugins.ralphharness.rag",
        description="RAG integration for RalphHarness",
    )
    subparsers = parser.add_subparsers(dest="command")

    retrieve_parser = subparsers.add_parser("retrieve", help="Retrieve relevant chunks")
    retrieve_parser.add_argument("--query", required=True)
    retrieve_parser.add_argument("--collection", required=True)
    retrieve_parser.add_argument("--top-k", type=int, default=3)
    retrieve_parser.set_defaults(func=cmd_retrieve)

    index_parser = subparsers.add_parser("index", help="Index chunks")
    index_parser.add_argument("--source", required=True)
    index_parser.add_argument("--collection", required=True)
    index_parser.add_argument("--spec-name", required=True)
    index_parser.set_defaults(func=cmd_index)

    index_all_parser = subparsers.add_parser("index-all", help="Index all specs")
    index_all_parser.add_argument("--force", action="store_true")
    index_all_parser.add_argument("--dry-run", action="store_true")
    index_all_parser.set_defaults(func=cmd_index_all)

    doctor_parser = subparsers.add_parser("doctor", help="Health check and diagnostics")
    doctor_parser.set_defaults(func=cmd_doctor)

    search_parser = subparsers.add_parser("search", help="Interactive search")
    search_parser.add_argument("--query", required=True)
    search_parser.add_argument("--top-k", type=int, default=10)
    search_parser.set_defaults(func=cmd_search)

    onboard_parser = subparsers.add_parser("onboard", help="Interactive onboarding")
    onboard_parser.add_argument("--non-interactive", action="store_true")
    onboard_parser.set_defaults(func=cmd_onboard)

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()
