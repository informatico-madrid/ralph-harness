"""CLI entry point for the RAG integration module.

Usage: python -m plugins.ralphharness.rag <command> [options]

Subcommands: retrieve, index, index-all, doctor, search, onboard
"""

import argparse
import fcntl
import json
import sys
import time
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
    from .config import RAGConfig
    from .service import RAGService

    config = RAGConfig.load()

    if not config.enabled:
        _print_stub(command="index-all", status="disabled")

    lock_dir = Path.home() / ".cache" / "smart-ralph" / "rag"
    lock_dir.mkdir(parents=True, exist_ok=True)
    lock_path = lock_dir / "index-all.lock"

    try:
        lock_fd = open(lock_path, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        # Check if lock is stale (> 60s)
        try:
            mtime = lock_path.stat().st_mtime
            if (time() - mtime) < 60:
                print(json.dumps({"error": "another index-all is in progress"}))
                sys.exit(1)
            # Stale lock — remove and retry
            lock_path.unlink(missing_ok=True)
            lock_fd = open(lock_path, "w")
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except Exception:
            print(json.dumps({"error": "another index-all is in progress"}))
            sys.exit(1)

    try:
        if args.dry_run:
            print(json.dumps({"phase": "dry-run", "status": "ok"}))
            sys.exit(0)

        service = RAGService.from_config()
        if service is None:
            print(json.dumps({"error": "RAG service not available"}))
            sys.exit(1)

        service.index_all()
        print(json.dumps({"phase": "complete", "status": "ok"}))
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()


def cmd_doctor(args):
    """Doctor command: print tiered health report."""
    from .config import RAGConfig

    config = RAGConfig.load()

    checks = []

    if config.enabled:
        checks.append("OK     enabled: true")
    else:
        checks.append("WARN   enabled: false (RAG is disabled)")

    checks.append(f"OK     provider: {config.provider}")

    if config.embedder.provider == "local":
        checks.append("OK     embeddings.provider: local (sentence-transformers)")
    elif config.embedder.provider == "openai":
        if config.embedder.api_key:
            checks.append("OK     embeddings.provider: openai (key configured)")
        else:
            checks.append("WARN   embeddings.provider: openai (no API key configured)")
    elif config.embedder.provider == "azure":
        if config.embedder.azure_endpoint:
            checks.append("OK     embeddings.provider: azure (endpoint configured)")
        else:
            checks.append("WARN   embeddings.provider: azure (no endpoint configured)")
    else:
        checks.append(f"WARN   embeddings.provider: unknown ({config.embedder.provider})")

    if config.provider == "qdrant":
        if config.vector_db.endpoint:
            checks.append(f"OK     vector_db.endpoint: {config.vector_db.endpoint}")
        else:
            checks.append("WARN   vector_db.endpoint: not configured (will use default)")
    elif config.provider == "faiss":
        if config.vector_db.faiss_index_path:
            checks.append(f"OK     faiss.index_path: {config.vector_db.faiss_index_path}")
        else:
            checks.append("WARN   faiss.index_path: not configured")

    report = "\n".join(checks)
    print(report)
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
    """Onboard subcommand: run the 7-step installer."""
    from .onboarding import (
        ConfigStep,
        DoctorStep,
        EmbedderStep,
        IndexBootstrapStep,
        PythonDepsStep,
        PythonStep,
        VectorDBStep,
        run,
    )

    steps = [
        PythonStep(),
        PythonDepsStep(),
        VectorDBStep(),
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
